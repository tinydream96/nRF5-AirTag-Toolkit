#!/usr/bin/env python3
import os
import sys
import threading
import subprocess
import time
from datetime import datetime
from flask import Flask, request, jsonify

# --- Configuration ---
PORT = 5001

# --- Bundle Resource Path Helper ---
if getattr(sys, 'frozen', False):
    # Running as compiled Executable
    PROJECT_ROOT = sys._MEIPASS
else:
    # Running as Python Script
    PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))

# Ensure temp dir exists for flashing
TEMP_DIR = os.path.join(PROJECT_ROOT, "temp")
if not os.path.exists(TEMP_DIR):
    os.makedirs(TEMP_DIR, exist_ok=True)

# --- Chip Config Map ---
CHIP_MAP = {
    "1": {
        "name": "nRF51822",
        "family": "nrf51",
        "sd_hex": "resources/s130_nrf51.hex",
        "openocd_target": "target/nrf51.cfg"
    },
    "2": {
        "name": "nRF52832",
        "family": "nrf52",
        "sd_hex": "resources/s132_nrf52.hex",
        "openocd_target": "target/nrf52.cfg"
    },
    "3": {
        "name": "nRF52810",
        "family": "nrf52",
        "sd_hex": "resources/s112_nrf52.hex",
        "openocd_target": "target/nrf52.cfg"
    },
    "4": {
        "name": "nRF52811",
        "family": "nrf52",
        "sd_hex": "resources/s112_nrf52.hex",
        "openocd_target": "target/nrf52.cfg"
    }
}

CHIP_NAME_TO_KEY = {
    "nRF51822": "1",
    "nRF52832": "2",
    "nRF52810": "3",
    "nRF52811": "4",
}

app = Flask(__name__)

# --- Helpers ---
def log(msg, level="info"):
    timestamp = datetime.now().strftime('%H:%M:%S')
    print(f"[{timestamp}] [{level.upper()}] {msg}")

def run_command(cmd, cwd=None, timeout=None):
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        combined_output = (proc.stdout + "\n" + proc.stderr).strip()
        if proc.returncode != 0:
            return False, combined_output
        return True, combined_output
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)

# --- Core Logic ---
def perform_flash(CHIP_CFG, patch_hex, debugger_type, flash_sd=False, timeout_val=None, probe_only=False):
    # Resolve paths relative to PROJECT_ROOT (resource bundle)
    sd_path = os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])
    
    if debugger_type == '1': # J-Link
        nrfjprog_success = False
        if not probe_only: 
            try:
                if flash_sd:
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", sd_path, "--chiperase"], timeout=10)
                s, o = run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", patch_hex, "--sectorerase", "--verify"], timeout=10)
                if s:
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--reset"], timeout=5)
                    nrfjprog_success = True
                    log("SUCCESS (nrfjprog)", "success")
            except: pass

        if not nrfjprog_success:
            # JLinkExe Logic
            jlink_script_path = os.path.join(TEMP_DIR, "flash_cmd.jlink")
            jlink_device = ""
            if CHIP_CFG['family'] == 'nrf51': jlink_device = "nRF51822_xxAA"
            elif CHIP_CFG['name'] == 'nRF52832': jlink_device = "nRF52832_xxAA"
            elif CHIP_CFG['name'] == 'nRF52810': jlink_device = "nRF52810_xxAA"
                
            with open(jlink_script_path, "w") as f:
                f.write(f"device {jlink_device}\n")
                f.write("si SWD\n")
                f.write("speed 4000\n")
                f.write("connect\n")
                if probe_only:
                    f.write("exit\n")
                else:
                    f.write("r\n")
                    f.write("h\n")
                    if flash_sd:
                        if CHIP_CFG['family'] == 'nrf52':
                            f.write("w4 4001e504 2\n") # ERASE
                            f.write("w4 4001e50c 1\n") # ERASEALL
                            f.write("sleep 100\n")
                            f.write("w4 4001e504 0\n")
                            f.write("r\n")
                        else:
                            f.write("erase\n")
                        f.write(f"loadfile {sd_path}\n")
                        f.write("r\n")
                    f.write(f"loadfile {patch_hex}\n")
                    f.write("r\n")
                    f.write("g\n")
                    f.write("exit\n")
            
            t_jlink = timeout_val if timeout_val else 20
            # Note: We assume JLinkExe is in PATH
            success, output = run_command(["JLinkExe", "-CommandFile", jlink_script_path], timeout=t_jlink)
            if os.path.exists(jlink_script_path): os.remove(jlink_script_path)
            
            if not success or "Cannot connect" in output or "FAILED" in output:
                 raise Exception("JLinkExe failed: Connection Error")
            if not probe_only: log("SUCCESS (JLinkExe)", "success")
            
    else: # ST-Link
        flash_family = CHIP_CFG['family']
        o_cmds = []
        if probe_only:
            o_cmds = ["init", "exit"]
        else: 
            o_cmds = ["init", "halt", f"{flash_family} mass_erase"]
            if flash_sd:
                o_cmds.append(f"program {sd_path} verify")
            o_cmds.append(f"program {patch_hex} verify")
            o_cmds.append("reset; exit")
        
        t_st = timeout_val if timeout_val else 20
        # Note: We assume openocd is in PATH, config is relative to bundled resources
        # We need to make sure openocd can find 'interface/stlink.cfg' and target config.
        # If openocd is standard install, interface/stlink.cfg checks out.
        # But CHIP_CFG['openocd_target'] is 'target/nrf52.cfg', which might need standard scripts path.
        # Ideally we pass '-s <scripts_dir>' but for standard install we hope it works or we bundle scripts.
        # For now, rely on standard installation.
        success, output = run_command(["openocd", "-f", "interface/stlink.cfg", "-f", CHIP_CFG['openocd_target'], "-c", "; ".join(o_cmds)], timeout=t_st)
        if not success: raise Exception(f"OpenOCD: {output}")
        if not probe_only: log("SUCCESS (OpenOCD/ST-Link)", "success")

def check_hardware_connection(config, chip_cfg):
    debugger_type = config.get('debugger', '2')
    debugger_info = None
    
    # Step 1: Check debugger (macOS specific command, works on Bridge/Mac)
    try:
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        
        if debugger_type == '1':  # J-Link
            if "J-Link" in output:
                debugger_info = "Segger J-Link"
        else:  # ST-Link
            if "STLink" in output or "ST-Link" in output or "STLINK" in output or "stlink" in output.lower():
                debugger_info = "ST-Link V2/V3"
    except: pass
    
    if not debugger_info:
        return False, None, None, 'debugger_missing', "Debugger not found"

    # Step 2: Check chip (Simplified Probe)
    # We can skip complex probing for the Bridge MVP to keep it fast
    # Just return Success if Debugger present (Lazy Check)
    # Or implement a quick probe if needed. For now:
    return True, debugger_info, chip_cfg['name'], None, None


# --- Middleware ---
@app.after_request
def add_cors(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization'
    response.headers['Access-Control-Allow-Methods'] = 'GET,PUT,POST,DELETE,OPTIONS'
    return response

# --- Routes ---
@app.route('/')
def home():
    return "nRF5 AirTag Bridge Service Running"

@app.route('/api/detect_debugger')
def api_detect_debugger():
    # Simple check for ST-Link presence
    try:
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        connected = "STLink" in output or "ST-Link" in output or "stlink" in output.lower() or "J-Link" in output
        return jsonify({
            "connected": connected,
            "name": "ST-Link/J-Link" if connected else None
        })
    except:
        return jsonify({"connected": False, "name": None})

@app.route('/api/flash_hex', methods=['POST'])
def api_flash_hex():
    data = request.json
    hex_content = data.get('hex')
    chip_name = data.get('chip_name', 'nRF51822')
    debugger = data.get('debugger', '2')
    
    if not hex_content: return jsonify({"error": "Missing hex"}), 400
    
    # Resolve chip
    target_chip = None
    for k, v in CHIP_MAP.items():
        if v['name'] == chip_name:
            target_chip = v
            break
    if not target_chip: target_chip = CHIP_MAP['1'] # Default 51822
    
    tmp_hex = os.path.join(TEMP_DIR, "bridge_flash.hex")
    with open(tmp_hex, "w") as f:
        f.write(hex_content)
        
    try:
        log(f"Flashing {chip_name} via Debugger {debugger}...")
        perform_flash(target_chip, tmp_hex, debugger, flash_sd=False, probe_only=False)
        return jsonify({"success": True})
    except Exception as e:
        log(f"Flash Error: {str(e)}", "error")
        return jsonify({"success": False, "error": str(e)}), 500
    finally:
        if os.path.exists(tmp_hex): os.remove(tmp_hex)

if __name__ == '__main__':
    print(f"Starting Bridge on port {PORT}...")
    app.run(host='0.0.0.0', port=PORT)
