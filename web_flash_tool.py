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
    STATE["is_flashing"] = True
    STATE["status_message"] = "Initializing..."
    STATE["last_generated_file"] = None
    
    # Logic: Total 6 chars. 
    # If prefix is 'MSF' (3), number pads to 3. 
    # If prefix is 'A' (1), number pads to 5.
    prefix = config['prefix'].upper()
    start_num = int(config['start_num'])
    padding = 6 - len(prefix)
    if padding < 1: padding = 1 # Safety minimum
    
    device_name = f"{prefix}{start_num:0{padding}d}"
    
    STATE["current_device"] = device_name
    files_to_zip = [] # List of (abis_path, arcname)
    
    try:
        log(f"Starting Flash Process for {device_name}", "info")
        log(f"Configuration: {config}", "info")
        
        # --- 1. Prepare Paths ---
        seed_dir = os.path.join(PROJECT_ROOT, "seeds", device_name)
        build_dir = os.path.join(PROJECT_ROOT, "heystack-nrf5x/nrf51822/armgcc/_build")
        make_dir = os.path.join(PROJECT_ROOT, "heystack-nrf5x/nrf51822/armgcc")
        
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
            
            # Always generate offline keys for download if requested (or default)
            # The prompt says "Dynamic can download json and two formats of seeds"
            # It seems user always wants this available.
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
                cmd = [sys.executable, gen_script, "-n", str(key_count), "-p", device_name, "-o", temp_dir]
                success, output = run_command(cmd)
                if success:
                    # Move keyfile
                    if os.path.exists(os.path.join(temp_dir, f"{device_name}_keyfile")):
                        shutil.move(os.path.join(temp_dir, f"{device_name}_keyfile"), os.path.join(PROJECT_ROOT, "config"))
                    
                    # Move json
                    if os.path.exists(os.path.join(temp_dir, f"{device_name}_devices.json")):
                         shutil.move(os.path.join(temp_dir, f"{device_name}_devices.json"), os.path.join(PROJECT_ROOT, "config"))

                    shutil.rmtree(temp_dir)
                    log("Keyfile generated.", "success")
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
        log("Compiling firmware...", "info")
        run_command(["make", "-C", make_dir, "clean"])
        
        interval = int(config['base_interval']) + (int(config['start_num']) * int(config['interval_step']))
        has_dcdc = "1" if config.get('dcdc', False) else "0"
        
        flags = [
            f"HAS_DCDC={has_dcdc}", "HAS_BATTERY=1", "KEY_ROTATION_INTERVAL=900", f"ADVERTISING_INTERVAL={interval}"
        ]
        if config['mode'] == '1': flags.append("DYNAMIC_KEYS=1")
        else: flags.append("MAX_KEYS=200")
        
        cmd = ["make", "-C", make_dir, "nrf51822_xxab"] + flags
        success, output = run_command(cmd)
        if not success: raise Exception(f"Make failed: {output}")
        log("Compilation success.", "success")
        
        # --- 4. Patch ---
        STATE["status_message"] = "Patching Binary..."
        log("Patching binary...", "info")
        orig_hex = os.path.join(build_dir, "nrf51822_xxab.hex")
        orig_bin = os.path.join(build_dir, "nrf51822_xxab.bin")
        patch_bin = os.path.join(build_dir, "nrf51822_xxab_patched.bin")
        patch_hex = os.path.join(build_dir, "nrf51822_xxab_patched.hex")
        
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
        run_command(["arm-none-eabi-objcopy", "-I", "binary", "-O", "ihex", "--change-addresses", "0x1B000", patch_bin, patch_hex])
        
        # --- 5. Flash ---
        STATE["status_message"] = "Flashing..."
        log("Flashing device...", "info")
        
        if config['debugger'] == '1': # J-Link
            if config.get('flash_sd', False):
                log("Flashing SoftDevice...", "info")
                sd_path = "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
                run_command(["nrfjprog", "-f", "nrf51", "--program", sd_path, "--sectorerase"])
            
            success, output = run_command(["nrfjprog", "-f", "nrf51", "--program", patch_hex, "--sectorerase", "--verify"])
            if not success: raise Exception(f"Flash failed: {output}")
            run_command(["nrfjprog", "-f", "nrf51", "--reset"])
            
        else: # ST-Link
            o_cmds = ["init", "halt", "nrf51 mass_erase"]
            if config.get('flash_sd', False):
                sd_path = "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
                o_cmds.append(f"program {sd_path} verify")
            o_cmds.append(f"program {patch_hex} verify")
            o_cmds.append("reset; exit")
            
            cmd_str = "; ".join(o_cmds)
            success, output = run_command(["openocd", "-f", "interface/stlink.cfg", "-f", "target/nrf51.cfg", "-c", cmd_str])
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

@app.route('/api/flash', methods=['POST'])
def api_flash():
    if STATE["is_flashing"]:
        return jsonify({"error": "Already flashing"}), 400
    
    config = request.json
    if not config.get('prefix'): return jsonify({"error": "Missing prefix"}), 400
    
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
        
    log("Web Flash Tool Started at http://127.0.0.1:5001", "success")
    app.run(host='0.0.0.0', port=5001)
