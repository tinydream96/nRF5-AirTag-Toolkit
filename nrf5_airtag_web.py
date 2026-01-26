#!/usr/bin/env python3
import os
import sys
import threading
import subprocess
import binascii
import shutil
import zipfile
import time
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_from_directory

app = Flask(__name__, template_folder='templates', static_folder='static')

# --- Global State ---
STATE = {
    "is_flashing": False,
    "current_device": "",
    "logs": [],
    "last_log_index": 0,
    "status_message": "Ready",
    "last_generated_file": None
}

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(PROJECT_ROOT, "device_flash_log_web.txt")
CONFIG_DIR = os.path.join(PROJECT_ROOT, "config")

# --- Chip Config Map (NEW) ---
CHIP_MAP = {
    "1": {
        "name": "nRF51822",
        "family": "nrf51",
        "make_dir": "heystack-nrf5x/nrf51822/armgcc",
        "build_name": "nrf51822_xxab",
        "offset": "0x1B000",
        "sd_hex": "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex",
        "openocd_target": "target/nrf51.cfg"
    },
    "2": {
        "name": "nRF52832",
        "family": "nrf52",
        "make_dir": "heystack-nrf5x/nrf52832/armgcc",
        "build_name": "nrf52832_xxaa",
        "offset": "0x26000",
        "sd_hex": "nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s132/hex/s132_nrf52_6.1.1_softdevice.hex",
        "openocd_target": "target/nrf52.cfg"
    },
    "3": {
        "name": "nRF52810",
        "family": "nrf52",
        "make_dir": "heystack-nrf5x/nrf52810/armgcc",
        "build_name": "nrf52810_xxaa",
        "offset": "0x19000",
        "sd_hex": "nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s112/hex/s112_nrf52_6.1.1_softdevice.hex",
        "openocd_target": "target/nrf52.cfg"
    }
}

def log(msg, level="info"):
    """Log to memory and file"""
    timestamp = datetime.now().strftime('%H:%M:%S')
    
    # CSS classes for frontend
    css_class = ""
    if level == "error": css_class = "text-red-500"
    elif level == "success": css_class = "text-green-500 font-bold"
    elif level == "warning": css_class = "text-yellow-500"
    elif level == "accent": css_class = "text-purple-400 font-bold"
    else: css_class = "text-gray-300"
    
    entry = {
        "time": timestamp,
        "msg": msg,
        "class": css_class
    }
    STATE["logs"].append(entry)
    
    # File logging
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] [{level.upper()}] {msg}\n")
        
    print(f"[{timestamp}] {msg}")

def run_command(cmd, cwd=None):
    """Run shell command and capture output"""
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        if proc.returncode != 0:
            return False, proc.stderr.strip()
        return True, proc.stdout.strip()
    except Exception as e:
        return False, str(e)

def flash_task(config):
    # Logs are cleared in api_flash now to ensure fresh start
    STATE["status_message"] = "Initializing..."
    STATE["last_generated_file"] = None
    
    # Logic: Total 6 chars. 
    prefix = config['prefix'].upper()
    start_num = int(config['start_num'])
    padding = 6 - len(prefix)
    if padding < 1: padding = 1 # Safety minimum
    
    device_name = f"{prefix}{start_num:0{padding}d}"
    
    STATE["current_device"] = device_name
    files_to_zip = [] # List of (abis_path, arcname)
    
    # Get Chip Config
    chip_id = config.get('chip', '1')
    CHIP_CFG = CHIP_MAP.get(chip_id)
    if not CHIP_CFG:
        log(f"Invalid Chip ID: {chip_id}", "error")
        STATE["is_flashing"] = False
        return

    try:
        log("=" * 40, "info")
        log(f"READY: Starting Flash Task for {device_name}", "accent")
        log(f"Chip: {CHIP_CFG['name']}", "accent")
        log("=" * 40, "info")
        log(f"Configuration: {config}", "info")
        
        # --- 1. Prepare Paths ---
        seed_dir = os.path.join(PROJECT_ROOT, "seeds", device_name)
        
        # New dynamic paths
        make_dir = os.path.join(PROJECT_ROOT, CHIP_CFG['make_dir'])
        build_dir = os.path.join(make_dir, "_build")
        
        # --- 2. Seed/Key Gen ---
        seed_bin_file = None
        key_file_path = None
        
        if config['mode'] == '1': # Dynamic
            if not os.path.exists(seed_dir): os.makedirs(seed_dir)
            seed_hex_file = os.path.join(seed_dir, f"seed_{device_name}.hex")
            seed_bin_file = os.path.join(seed_dir, f"seed_{device_name}.bin")
            
            # Generate Seed
            seed_hex = binascii.b2a_hex(os.urandom(32)).decode()
            log(f"Generated Seed: {seed_hex}", "accent")
            
            with open(seed_hex_file, "w") as f: f.write(seed_hex)
            with open(seed_bin_file, "wb") as f: f.write(binascii.unhexlify(seed_hex))
            
            # Add seeds to zip list
            files_to_zip.append((seed_hex_file, f"seed_{device_name}.hex"))
            files_to_zip.append((seed_bin_file, f"seed_{device_name}.bin"))
            
            log("Generating Offline Keys...", "info")
            gen_script = os.path.join(PROJECT_ROOT, "heystack-nrf5x/tools/generate_keys_from_seed.py")
            
            # Use sys.executable for compatibility
            cmd = [sys.executable, gen_script, "-s", seed_hex, "-n", "200", "-p", device_name, "-o", os.path.join(PROJECT_ROOT, "config")]
            success, output = run_command(cmd)
            
            if success:
                json_file = os.path.join(PROJECT_ROOT, "config", f"{device_name}_devices.json")
                if os.path.exists(json_file):
                    files_to_zip.append((json_file, f"{device_name}_devices.json"))
                    log("Offline keys generated.", "info")
            else:
                 log(f"Offline key gen warning: {output}", "warning")
                
        else: # Static
            key_filename = f"{device_name}_keyfile"
            key_file_path = os.path.join(PROJECT_ROOT, "config", key_filename)
            json_file = os.path.join(PROJECT_ROOT, "config", f"{device_name}_devices.json")
            
            if not os.path.exists(key_file_path):
                log(f"Keyfile missing. Generating...", "warning")
                # Auto-gen logic
                temp_dir = os.path.join(PROJECT_ROOT, "temp_keys_web")
                if not os.path.exists(temp_dir): os.makedirs(temp_dir)
                gen_script = os.path.join(PROJECT_ROOT, "heystack-nrf5x/tools/generate_keys.py")
                key_count = config.get('key_count', 200)
                # Ensure output path ends with slash
                out_dir = temp_dir if temp_dir.endswith(os.sep) else temp_dir + os.sep
                cmd = [sys.executable, gen_script, "-n", str(key_count), "-p", device_name, "-o", out_dir]
                log(f"Generator Command: {' '.join(cmd)}", "info")
                success, output = run_command(cmd)
                if success:
                    # Verify file exists before moving
                    kf_path = os.path.join(temp_dir, f"{device_name}_keyfile")
                    js_path = os.path.join(temp_dir, f"{device_name}_devices.json")
                    
                    if os.path.exists(kf_path):
                        shutil.move(kf_path, os.path.join(PROJECT_ROOT, "config"))
                        if os.path.exists(js_path):
                            shutil.move(js_path, os.path.join(PROJECT_ROOT, "config"))
                        shutil.rmtree(temp_dir)
                        log("Keyfile generated and moved to config.", "success")
                    else:
                        raise Exception(f"Generator reported success but {device_name}_keyfile not found in {temp_dir}")
                else:
                    raise Exception(f"Keygen failed: {output}")
            
            # Prepare Static Zip
            if os.path.exists(json_file):
                files_to_zip.append((json_file, f"{device_name}_devices.json"))

        # --- Create Zip Bundle ---
        if files_to_zip:
            zip_name = f"{device_name}_bundle.zip"
            zip_path = os.path.join(CONFIG_DIR, zip_name)
            try:
                with zipfile.ZipFile(zip_path, 'w') as zf:
                    for file_path, arcname in files_to_zip:
                        zf.write(file_path, arcname)
                STATE["last_generated_file"] = zip_name
                log(f"Bundle created: {zip_name}", "info")
            except Exception as e:
                log(f"Zip creation failed: {e}", "warning")


        # --- 3. Build ---
        STATE["status_message"] = "Compiling Firmware..."
        log(f"Compiling firmware for {CHIP_CFG['name']}...", "info")
        run_command(["make", "-C", make_dir, "clean"])
        
        interval = int(config['base_interval']) + (int(config['start_num']) * int(config['interval_step']))
        has_dcdc = "1" if config.get('dcdc', False) else "0"
        
        flags = [
            f"HAS_DCDC={has_dcdc}", "HAS_BATTERY=1", "KEY_ROTATION_INTERVAL=900", f"ADVERTISING_INTERVAL={interval}"
        ]
        if config['mode'] == '1': flags.append("DYNAMIC_KEYS=1")
        else: flags.append("MAX_KEYS=200")
        
        # Use dynamic build name
        cmd = ["make", "-C", make_dir, CHIP_CFG['build_name']] + flags
        success, output = run_command(cmd)
        if not success: raise Exception(f"Make failed: {output}")
        log("Compilation success.", "success")
        
        # --- 4. Patch ---
        STATE["status_message"] = "Patching Binary..."
        log("Patching binary...", "info")
        orig_hex = os.path.join(build_dir, f"{CHIP_CFG['build_name']}.hex")
        orig_bin = os.path.join(build_dir, f"{CHIP_CFG['build_name']}.bin")
        patch_bin = os.path.join(build_dir, f"{CHIP_CFG['build_name']}_patched.bin")
        patch_hex = os.path.join(build_dir, f"{CHIP_CFG['build_name']}_patched.hex")
        
        run_command(["arm-none-eabi-objcopy", "-I", "ihex", "-O", "binary", orig_hex, orig_bin])
        
        with open(orig_bin, "rb") as f: fw_data = bytearray(f.read())
        
        if config['mode'] == '1':
            offset = fw_data.find(b"LinkyTagDynamicSeedPlaceholder!!")
            if offset == -1: raise Exception("Seed Placeholder not found")
            with open(seed_bin_file, "rb") as f: seed_data = f.read()
            fw_data[offset : offset+len(seed_data)] = seed_data
        else:
            offset = fw_data.find(b"OFFLINEFINDINGPUBLICKEYHERE!")
            if offset == -1: raise Exception("Key Placeholder not found")
            with open(key_file_path, "rb") as f: key_data = f.read()
            real_key = key_data[1:]
            fw_data[offset : offset+len(real_key)] = real_key
            
        with open(patch_bin, "wb") as f: f.write(fw_data)
        
        # Use dynamic offset
        run_command(["arm-none-eabi-objcopy", "-I", "binary", "-O", "ihex", "--change-addresses", CHIP_CFG['offset'], patch_bin, patch_hex])
        
        # --- 5. Flash ---
        STATE["status_message"] = "Flashing..."
        log(f"Flashing device...", "info")
        
        if config['debugger'] == '1': # J-Link
            log("Flashing with J-Link...", "info")
            nrfjprog_success = False
            
            # --- 1. Try nrfjprog first ---
            try:
                log("Attempting with nrfjprog...", "info")
                if config.get('flash_sd', False):
                    log(" Performing Mass Erase & Stack Install...", "warning")
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex']), "--chiperase"])
                
                log(" Flashing Firmware App...", "info")
                s, o = run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", patch_hex, "--sectorerase", "--verify"])
                if s:
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--reset"])
                    nrfjprog_success = True
                    log("SUCCESS (nrfjprog)", "success")
            except:
                pass

            # --- 2. Fallback to JLinkExe ---
            if not nrfjprog_success:
                log("nrfjprog failed. Falling back to JLinkExe...", "warning")
                
                # Generate JLink Script
                jlink_script_path = os.path.join(PROJECT_ROOT, "flash_cmd_web.jlink")
                jlink_device = ""
                
                if CHIP_CFG['family'] == 'nrf51':
                    jlink_device = "nRF51822_xxAA"
                elif CHIP_CFG['name'] == 'nRF52832':
                    jlink_device = "nRF52832_xxAA"
                elif CHIP_CFG['name'] == 'nRF52810':
                    jlink_device = "nRF52810_xxAA"
                    
                with open(jlink_script_path, "w") as f:
                    f.write(f"device {jlink_device}\n")
                    f.write("si SWD\n")
                    f.write("speed 4000\n")
                    f.write("connect\n")
                    f.write("r\n")
                    f.write("h\n")
                    
                    if config.get('flash_sd', False):
                        log("Performing Mass Erase (JLink)...", "warning")
                        log("Flashing SoftDevice...", "info")
                        sd_full_path = os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])
                        
                        if CHIP_CFG['family'] == 'nrf52':
                            # nRF52 Erase Sequence
                            f.write("w4 4001e504 2\n") # NVMC.CONFIG = ERASE
                            f.write("w4 4001e50c 1\n") # ERASEALL = 1
                            f.write("sleep 100\n")
                            f.write("w4 4001e504 0\n") # NVMC.CONFIG = READONLY
                            f.write("r\n")
                        else:
                            # nRF51 can just use erase
                            f.write("erase\n")
                            
                        f.write(f"loadfile {sd_full_path}\n")
                        f.write("r\n")
                    
                    # Flash App
                    f.write(f"loadfile {patch_hex}\n")
                    f.write("r\n")
                    f.write("g\n")
                    f.write("exit\n")
                
                # Execute JLinkExe
                success, output = run_command(["JLinkExe", "-CommandFile", jlink_script_path])
                
                # Cleanup
                if os.path.exists(jlink_script_path):
                    os.remove(jlink_script_path)
                    
                # JLinkExe often returns 0 even on failure. We must check output text.
                # Common failure keywords: "Cannot connect", "failed", "Error"
                if not success or "Cannot connect to target" in output or "Connection failed" in output or "Error while" in output or "FAILED" in output:
                     log(f"JLinkExe Output:\n{output}", "error") # Log full output for debug
                     raise Exception(f"JLinkExe failed: See log for details.")
                
                log("SUCCESS (JLinkExe)", "success")
            
        else: # ST-Link
            flash_family = CHIP_CFG['family'] # nrf51 or nrf52
            o_cmds = ["init", "halt", f"{flash_family} mass_erase"]
            if config.get('flash_sd', False):
                sd_path = os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])
                o_cmds.append(f"program {sd_path} verify")
            o_cmds.append(f"program {patch_hex} verify")
            o_cmds.append("reset; exit")
            
            cmd_str = "; ".join(o_cmds)
            success, output = run_command(["openocd", "-f", "interface/stlink.cfg", "-f", CHIP_CFG['openocd_target'], "-c", cmd_str])
            if not success: raise Exception(f"OpenOCD failed: {output}")

        log(f"SUCCESS: {device_name} Flashed!", "success")
        STATE["status_message"] = f"SUCCESS: {device_name} Flashed!"
        
    except Exception as e:
        log(f"ERROR: {str(e)}", "error")
        STATE["status_message"] = "Error"
    finally:
        STATE["is_flashing"] = False

# --- Routes ---
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/download/<path:filename>')
def download_file(filename):
    return send_from_directory(CONFIG_DIR, filename, as_attachment=True)

@app.route('/api/detect_debugger')
def api_detect_debugger():
    # ... existing detection logic ...
    try:
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        if "J-Link" in output: return jsonify({"debugger": "1"})
        if "ST-Link" in output or "STLINK" in output: return jsonify({"debugger": "2"})
    except: pass
    return jsonify({"debugger": None})

@app.route('/api/logs/clear', methods=['POST'])
def clear_logs_api():
    STATE["logs"] = []
    STATE["status_message"] = "Ready"
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w") as f: f.write("")
    return jsonify({"success": True})

@app.route('/api/flash', methods=['POST'])
def api_flash():
    if STATE["is_flashing"]:
        return jsonify({"error": "Already flashing"}), 400
    
    config = request.json
    if not config.get('prefix'): return jsonify({"error": "Missing prefix"}), 400
    
    STATE["is_flashing"] = True
    STATE["status_message"] = "Starting task..."
    
    t = threading.Thread(target=flash_task, args=(config,))
    t.start()
    
    return jsonify({"success": True})

@app.route('/api/logs')
def api_logs():
    return jsonify({
        "logs": STATE["logs"],
        "status": STATE["status_message"],
        "is_flashing": STATE["is_flashing"],
        "download_file": STATE["last_generated_file"]
    })

if __name__ == '__main__':
    if not os.path.exists(os.path.join(PROJECT_ROOT, 'templates')):
        os.makedirs(os.path.join(PROJECT_ROOT, 'templates'))
    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR)
        
    log("nRF5 AirTag Web Tool Started at http://127.0.0.1:5001", "success")
    app.run(host='0.0.0.0', port=5001)
