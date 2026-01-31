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
import glob
from flask import Flask, render_template, request, jsonify, send_from_directory

app = Flask(__name__, template_folder='templates', static_folder='static')

# --- Global State ---
STATE = {
    "logs": {},  # session_id -> [log_list]
    "session_state": {},  # session_id -> {"is_flashing": bool, ...}
    "last_log_index": 0,
    "status_message": "Ready",
    "stop_signal": False
}

# --- Configuration ---
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
STATIC_FOLDER = os.path.join(PROJECT_ROOT, "templates")
CONFIG_DIR = os.path.join(PROJECT_ROOT, "config")
SESSIONS_DIR = os.path.join(PROJECT_ROOT, "user_sessions")

# Ensure directories exist
for d in [CONFIG_DIR, SESSIONS_DIR]:
    if not os.path.exists(d):
        os.makedirs(d)

# Global Build Lock to prevent race conditions during 'make'
BUILD_LOCK = threading.Lock()
LOG_FILE = os.path.join(PROJECT_ROOT, "device_flash_log_web.txt")
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
    },
    "4": {  # nRF52811 uses same config as nRF52810
        "name": "nRF52811",
        "family": "nrf52",
        "make_dir": "heystack-nrf5x/nrf52810/armgcc",  # Same as 52810
        "build_name": "nrf52810_xxaa",  # Same as 52810
        "offset": "0x19000",
        "sd_hex": "nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s112/hex/s112_nrf52_6.1.1_softdevice.hex",
        "openocd_target": "target/nrf52.cfg"
    }
}

# Debugger Configuration Map
# ID 1 is reserved for Native nrfjprog (J-Link)
OPENOCD_INTERFACES = {
    '2': 'interface/stlink.cfg',      # ST-Link
    '3': 'interface/cmsis-dap.cfg',   # DAPLink / CMSIS-DAP
    '4': 'interface/jlink.cfg',       # J-Link (via OpenOCD)
}

def get_openocd_interface(debugger_id):
    return OPENOCD_INTERFACES.get(str(debugger_id), 'interface/stlink.cfg')

# Auto-detection: map chip name to config key
CHIP_NAME_TO_KEY = {
    "nRF51822": "1",
    "nRF52832": "2",
    "nRF52810": "3",
    "nRF52811": "4",
}

def log(msg, level="info", session_id=None):
    """Log to memory and file, optionally isolated by session"""
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
    
    # Session isolation
    if session_id:
        if session_id not in STATE["logs"]:
            STATE["logs"][session_id] = []
        STATE["logs"][session_id].append(entry)
    else:
        # Fallback for truly global/system logs
        if "global" not in STATE["logs"]:
            STATE["logs"]["global"] = []
        STATE["logs"]["global"].append(entry)

    # console preview
    print(f"[{timestamp}] {msg}")
    
    # file persistence
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] [{level.upper()}] {msg}\n")
    except:
        pass

# Session State Helpers
def get_session_state(session_id, key, default=None):
    """Get a value from session state"""
    if not session_id:
        return default
    session_state = STATE["session_state"].get(session_id, {})
    return session_state.get(key, default)

def set_session_state(session_id, key, value):
    """Set a value in session state"""
    if not session_id:
        return
    if session_id not in STATE["session_state"]:
        STATE["session_state"][session_id] = {}
    STATE["session_state"][session_id][key] = value

def run_command(cmd, cwd=None, timeout=None):
    """Run shell command and capture output (stdout + stderr combined)"""
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        # Combine stdout and stderr for tools like OpenOCD that output to stderr
        combined_output = (proc.stdout + "\n" + proc.stderr).strip()
        if proc.returncode != 0:
            return False, combined_output
        return True, combined_output
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)

# Helper to perform one flash attempt (Global)
def perform_flash(CHIP_CFG, patch_hex, debugger_type, flash_sd=False, timeout_val=None, probe_only=False):
    if debugger_type == '1': # J-Link
        nrfjprog_success = False
        
        # nrfjprog is not good for probing, skips directly to JLinkExe if probing
        if not probe_only: 
            try:
                if flash_sd:
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex']), "--chiperase"], timeout=10)
                s, o = run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--program", patch_hex, "--sectorerase", "--verify"], timeout=10)
                if s:
                    run_command(["nrfjprog", "-f", CHIP_CFG['family'], "--reset"], timeout=5)
                    nrfjprog_success = True
                    log("SUCCESS (nrfjprog) | 刷写成功", "success")
            except: pass

        if not nrfjprog_success:
            # JLinkExe Logic
            jlink_script_path = os.path.join(PROJECT_ROOT, "flash_cmd_web.jlink")
            jlink_device = ""
            if CHIP_CFG['family'] == 'nrf51': jlink_device = "nRF51822_xxAA"
            elif CHIP_CFG['name'] == 'nRF52832': jlink_device = "nRF52832_xxAA"
            elif CHIP_CFG['name'] == 'nRF52810': jlink_device = "nRF52810_xxAA"
                
            with open(jlink_script_path, "w") as f:
                f.write(f"device {jlink_device}\\n")
                f.write("si SWD\\n")
                f.write("speed 4000\\n")
                f.write("connect\\n")
                if probe_only:
                    f.write("exit\\n") # Just connect and exit
                else:
                    f.write("r\\n")
                    f.write("h\\n")
                    if flash_sd:
                        sd_full_path = os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])
                        if CHIP_CFG['family'] == 'nrf52':
                            f.write("w4 4001e504 2\\n") # ERASE
                            f.write("w4 4001e50c 1\\n") # ERASEALL
                            f.write("sleep 100\\n")
                            f.write("w4 4001e504 0\\n")
                            f.write("r\\n")
                        else:
                            f.write("erase\\n")
                        f.write(f"loadfile {sd_full_path}\\n")
                        f.write("r\\n")
                    f.write(f"loadfile {patch_hex}\\n")
                    f.write("r\\n")
                    f.write("g\\n")
                    f.write("exit\\n")
            
            # Use timeout if provided
            t_jlink = timeout_val if timeout_val else 20
            success, output = run_command(["JLinkExe", "-CommandFile", jlink_script_path], timeout=t_jlink)
            if os.path.exists(jlink_script_path): os.remove(jlink_script_path)
            
            if not success or "Cannot connect" in output or "FAILED" in output or "Could not connect" in output or "Failed to attach" in output or "Error occurred" in output:
                    raise Exception("JLinkExe failed: Connection Error")
            if not probe_only: log("SUCCESS (JLinkExe)", "success")
            
    else: # OpenOCD based debuggers (ST-Link, DAPLink, etc.)
        interface = get_openocd_interface(debugger_type)
        flash_family = CHIP_CFG['family']
        o_cmds = []
        if probe_only:
            o_cmds = ["init", "exit"]
        else: 
            o_cmds = ["init", "halt", f"{flash_family} mass_erase"]
            if flash_sd:
                o_cmds.append(f"program {os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])} verify")
            o_cmds.append(f"program {patch_hex} verify")
            o_cmds.append("reset; exit")
        
        # Use timeout if provided
        t_st = timeout_val if timeout_val else 20
        # Determine interface config arg
        interface_cfg = interface
        
        success, output = run_command(["openocd", "-f", interface_cfg, "-f", CHIP_CFG['openocd_target'], "-c", "; ".join(o_cmds)], timeout=t_st)
        if not success: raise Exception(f"OpenOCD ({interface}): {output}")
        if not probe_only: log(f"SUCCESS (OpenOCD/{interface})", "success")

def check_hardware_connection(config, chip_cfg):
    """
    Check debugger and chip connection before starting compilation.
    Returns: (success, debugger_info, chip_info, error_type, error_msg)
    error_type: None, 'debugger_missing', 'chip_disconnected', 'chip_protected'
    """
    debugger_type = config.get('debugger', '2')
    chip_id = config.get('chip', '1')
    debugger_info = None
    chip_info = None
    
    # Step 1: Check debugger
    try:
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        
        if debugger_type == '1':  # J-Link
            if "J-Link" in output:
                # Try to get J-Link serial/model
                debugger_info = "Segger J-Link"
                if "J-Link OB" in output:
                    debugger_info = "Segger J-Link OB"
                elif "J-Link EDU" in output:
                    debugger_info = "Segger J-Link EDU"
                elif "J-Link Plus" in output:
                    debugger_info = "Segger J-Link Plus"
        else: # ST-Link
             if "STLink" in output or "ST-Link" in output or "STLINK" in output or "stlink" in output.lower():
                debugger_info = "ST-Link V2"
                if "STLINK-V3" in output or "V3" in output:
                    debugger_info = "ST-Link V3"
        
        # Check for DAPLink regardless of selection for info logging
        if not debugger_info and any(k in output for k in ["CMSIS-DAP", "DAPLink", "Mbed"]):
             debugger_info = "DAPLink (CMSIS-DAP)"


    except Exception as e:
        log(f"Debugger pre-check (ioreg) failed: {e}. Proceeding to probe...", "warning")
    
    # If debugger info is still None, default to generic
    if not debugger_info:
        if debugger_type == '1': debugger_info = "J-Link (Probing...)"
        elif debugger_type == '3': debugger_info = "DAPLink (Probing...)"
        else: debugger_info = "ST-Link (Probing...)"
    
    # Step 2: Check chip connection
    chip_family = chip_cfg['family']
    target_chip = chip_cfg['name']
    
    if debugger_type == '1':  # J-Link
        # Use nrfjprog to probe chip - MUST actually read memory to verify connection
        try:
            # First try to read FICR.INFO.PART to identify the actual chip
            # nRF51: 0x10000100, nRF52: 0x10000100
            # Try nrf52 first since it's more common
            detected_chip = None
            detected_family = None
            
            for try_family in ['nrf52', 'nrf51']:
                success, output = run_command([
                    "nrfjprog", "-f", try_family, "--memrd", "0x10000100", "--n", "4"
                ], timeout=8)
                
                # Check for actual success (not just return code, but valid output)
                if output.strip() and "0x10000100:" in output:
                    # Parse the chip ID from output
                    # Format: "0x10000100: 00051822" or "0x10000100: 0x00052810"
                    try:
                        lines = output.strip().split('\n')
                        for line in lines:
                            if '0x10000100:' in line:
                                # Get the hex value after the colon
                                hex_part = line.split(':')[-1].strip().split()[0]
                                # Remove 0x prefix if present
                                if hex_part.startswith('0x'):
                                    hex_part = hex_part[2:]
                                part_id = int(hex_part, 16)
                                
                                # Identify chip by part ID
                                if part_id == 0x51822:
                                    detected_chip = "nRF51822"
                                    detected_family = "nrf51"
                                elif part_id == 0x52832:
                                    detected_chip = "nRF52832"
                                    detected_family = "nrf52"
                                elif part_id == 0x52810:
                                    detected_chip = "nRF52810"
                                    detected_family = "nrf52"
                                elif part_id == 0x52840:
                                    detected_chip = "nRF52840"
                                    detected_family = "nrf52"
                                elif part_id == 0x52811:
                                    detected_chip = "nRF52811"
                                    detected_family = "nrf52"
                                elif part_id == 0x52833:
                                    detected_chip = "nRF52833"
                                    detected_family = "nrf52"
                                
                                if detected_chip:
                                    break
                    except Exception as e:
                        pass
                    
                    if detected_chip:
                        break
            
            if detected_chip:
                # Chip detected successfully - return it for auto-selection
                return True, debugger_info, detected_chip, None, None
            else:
                # Couldn't identify chip, try basic memory read
                success, output = run_command([
                    "nrfjprog", "-f", chip_family, "--memrd", "0x10000000", "--n", "4"
                ], timeout=8)
                
                if success:
                    chip_info = target_chip
                    return True, debugger_info, chip_info, None, None
                    
                # Memory read failed - analyze the error
                output_lower = output.lower()
                
                # Check for read protection
                if "approtect" in output_lower or "read protection" in output_lower or "protected" in output_lower:
                    return False, debugger_info, None, 'chip_protected', "芯片已被保护（APPROTECT 启用）。执行 nrfjprog -f nrf51 --recover 可恢复。"
                
                # Check for no connection
                return False, debugger_info, None, 'chip_disconnected', "无法识别芯片型号。请检查连线。"
                
        except Exception as e:
            return False, debugger_info, None, 'chip_disconnected', f"芯片检测异常: {str(e)}"
            
    else:  # OpenOCD based debuggers (ST-Link, DAPLink, etc.)
        interface = get_openocd_interface(debugger_type)
        try:
            # Quick OpenOCD test
            target_file = chip_cfg.get('openocd_target', 'target/nrf51.cfg')
            success, output = run_command([
                "openocd", "-f", interface, "-f", target_file,
                "-c", "init; targets; shutdown"
            ], timeout=8)
            
            if success:
                output_lower = output.lower()
                # Match various success indicators from OpenOCD
                if any(pattern in output_lower for pattern in [
                    "target halted", "cortex-m", "cortex_m", "processor detected",
                    "target state", "nrf51", "nrf52", "breakpoints"
                ]):
                    chip_info = target_chip
                    return True, debugger_info, chip_info, None, None
                elif "TAP" in output or "JTAG" in output:
                    chip_info = target_chip
                    return True, debugger_info, chip_info, None, None
            
            # Parse error messages
            output_lower = output.lower()
            if "protected" in output_lower or "locked" in output_lower:
                return False, debugger_info, None, 'chip_protected', "芯片已被保护。请使用 mass erase 解锁。"
            elif "no swd" in output_lower or "transport" in output_lower:
                return False, debugger_info, None, 'chip_disconnected', "无法识别芯片 SWD 接口。"
            
            return False, debugger_info, None, 'chip_disconnected', f"OpenOCD Error: {output[:100]}..."
            
        except Exception as e:
            return False, debugger_info, None, 'chip_disconnected', f"OpenOCD Check Failed: {str(e)}"

    
    return True, debugger_info, chip_info, None, None

def generate_firmware(config, chip_cfg=None):
    """
    Core logic to generate a patched firmware bundle.
    Returns: (success, result_dict, error_msg)
    """
    # --- 1. Name Generation (with timestamp for uniqueness) ---
    prefix = config.get('prefix', 'DEV')
    start_num = int(config.get('start_num', 1))
    padding = int(config.get('padding', 2))
    
    # Generate base device name
    base_name = f"{prefix}{start_num:0{padding}d}"
    
    # Add timestamp for uniqueness (format: YYYYMMDD_HHMMSS)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    device_name = f"{base_name}_{timestamp}"
    
    # Get initial Chip Config
    if not chip_cfg:
        chip_id = config.get('chip', '1')
        chip_cfg = CHIP_MAP.get(chip_id)
        
        if not chip_cfg:
            return False, None, f"Invalid Chip ID: {config.get('chip')}"

    # Determine Output Directory (Session Isolation)
    session_id = config.get('session_id')
    if session_id:
        # Isolated Session Directory - CREATE but DON'T DELETE existing files!
        output_dir = os.path.join(SESSIONS_DIR, session_id)
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
    else:
        # Fallback to global config dir (legacy behavior)
        output_dir = CONFIG_DIR

    files_to_zip = [] # List of (abis_path, arcname)
    
    try:
        # --- 1. Prepare Paths ---
        # Seed dir remains global/persistent as it is based on device name
        seed_dir = os.path.join(PROJECT_ROOT, "seeds", device_name)
        
        make_dir = os.path.join(PROJECT_ROOT, chip_cfg['make_dir'])
        # Global build artifacts location
        global_build_hex = os.path.join(make_dir, "_build", f"{chip_cfg['build_name']}.hex")
        global_build_bin = os.path.join(make_dir, "_build", f"{chip_cfg['build_name']}.bin")

        # --- 2. Seed/Key Gen (Output to Session Dir) ---
        seed_bin_file = None
        key_file_path = None
        
        if config['mode'] == '1': # Dynamic
            if not os.path.exists(seed_dir): os.makedirs(seed_dir)
            seed_hex_file = os.path.join(seed_dir, f"seed_{device_name}.hex")
            seed_bin_file = os.path.join(seed_dir, f"seed_{device_name}.bin")
            
            # Generate Seed
            seed_hex = binascii.b2a_hex(os.urandom(32)).decode()
            log(f"Generated Seed: {seed_hex} | 已生成随机种子", "accent", session_id=session_id)
            
            with open(seed_hex_file, "w") as f: f.write(seed_hex)
            with open(seed_bin_file, "wb") as f: f.write(binascii.unhexlify(seed_hex))
            
            files_to_zip.append((seed_hex_file, f"seed_{device_name}.hex"))
            files_to_zip.append((seed_bin_file, f"seed_{device_name}.bin"))
            
            log("Generating Offline Keys...", "info", session_id=session_id)
            gen_script = os.path.join(PROJECT_ROOT, "heystack-nrf5x/tools/generate_keys_from_seed.py")
            
            
            # Use sys.executable for compatibility
            # Output keys to session directory
            cmd = [sys.executable, gen_script, "-s", seed_hex, "-n", "200", "-p", device_name, "-o", output_dir]
            success, output = run_command(cmd)
            
            if success:
                json_file = os.path.join(output_dir, f"{device_name}_devices.json")
                if os.path.exists(json_file):
                    files_to_zip.append((json_file, f"{device_name}_devices.json"))
                log("Offline keys generated. | 离线密钥对已生成", "info", session_id=session_id)
            else:
                 log(f"Offline key gen warning: {output}", "warning", session_id=session_id)
                
        else: # Static
            key_filename = f"{device_name}_keyfile"
            key_file_path = os.path.join(CONFIG_DIR, key_filename) # Check in global config dir first
            json_file = os.path.join(CONFIG_DIR, f"{device_name}_devices.json") # Check in global config dir first
            
            if not os.path.exists(key_file_path):
                log(f"Keyfile missing. Generating...", "warning", session_id=session_id)
                # Auto-gen logic
                temp_dir = os.path.join(PROJECT_ROOT, "temp_keys_web")
                if not os.path.exists(temp_dir): os.makedirs(temp_dir)
                gen_script = os.path.join(PROJECT_ROOT, "heystack-nrf5x/tools/generate_keys.py")
                key_count = config.get('key_count', 200)
                # Ensure output path ends with slash
                out_dir = temp_dir if temp_dir.endswith(os.sep) else temp_dir + os.sep
                cmd = [sys.executable, gen_script, "-n", str(key_count), "-p", device_name, "-o", out_dir]
                log(f"Generator Command: {' '.join(cmd)}", "info", session_id=session_id)
                success, output = run_command(cmd)
                if success:
                    # Verify file exists before moving
                    kf_path = os.path.join(temp_dir, f"{device_name}_keyfile")
                    js_path = os.path.join(temp_dir, f"{device_name}_devices.json")
                    
                    if os.path.exists(kf_path):
                        shutil.move(kf_path, output_dir)
                        if os.path.exists(js_path):
                            shutil.move(js_path, output_dir)
                        shutil.rmtree(temp_dir)
                        
                        # Update paths to new location
                        key_file_path = os.path.join(output_dir, key_filename)
                        json_file = os.path.join(output_dir, f"{device_name}_devices.json")
                        
                        log("Keyfile generated and prepared. | 密钥文件已就绪", "success", session_id=session_id)
                    else:
                        return False, None, f"Generator reported success but {device_name}_keyfile not found in {temp_dir}"
                else:
                    return False, None, f"Keygen failed: {output}"
            
            # Prepare Static Zip
            # Ensure json_file points to the session directory if it was moved or generated there
            json_file = os.path.join(output_dir, f"{device_name}_devices.json")
            if os.path.exists(json_file):
                files_to_zip.append((json_file, f"{device_name}_devices.json"))

        # --- 3. Build ---
        log(f"Compiling firmware for {chip_cfg['name']}... | 正在编译固件...", "info", session_id=session_id)
        run_command(["make", "-C", make_dir, "clean"])
        
        interval = int(config['base_interval']) + (int(config['start_num']) * int(config['interval_step']))
        has_dcdc = "1" if config.get('dcdc', False) else "0"
        
        flags = [
            f"HAS_DCDC={has_dcdc}", "HAS_BATTERY=1", "KEY_ROTATION_INTERVAL=900", f"ADVERTISING_INTERVAL={interval}"
        ]
        if config['mode'] == '1': flags.append("DYNAMIC_KEYS=1")
        else: flags.append("MAX_KEYS=200")
        
        # Use dynamic build name
        cmd = ["make", "-C", make_dir, chip_cfg['build_name']] + flags
        
        # --- CRITICAL SECTION: COMPILE ---
        # We must lock the build process because 'make' uses a shared _build directory.
        log("Waiting for build lock... | 等待编译队列...", "info", session_id=session_id)
        with BUILD_LOCK:
            log(f"Compiling firmware for {chip_cfg['name']}... | 正在编译固件...", "info", session_id=session_id)
            run_command(["make", "-C", make_dir, "clean"])
            success, output = run_command(cmd)
            
            if not success: return False, None, f"Make failed: {output}"
            
            # COPY artifacts to session directory immediately to release lock safely
            if os.path.exists(global_build_hex):
                shutil.copy(global_build_hex, os.path.join(output_dir, "raw_firmware.hex"))
            if os.path.exists(global_build_bin):
                shutil.copy(global_build_bin, os.path.join(output_dir, "raw_firmware.bin"))
                
        # --- END CRITICAL SECTION ---
        log("Compilation success. | 固件编译完成", "success", session_id=session_id)
        
        # --- 4. Patch (Operate on Session Copy) ---
        log("Patching binary... | 正在注入引导配置...", "info", session_id=session_id)
        
        # Paths in Session Dir
        orig_hex = os.path.join(output_dir, "raw_firmware.hex")
        orig_bin = os.path.join(output_dir, "raw_firmware.bin")
        patch_bin = os.path.join(output_dir, f"{chip_cfg['build_name']}_patched.bin")
        patch_hex = os.path.join(output_dir, f"{chip_cfg['build_name']}_patched.hex")
        
        # Ensure bin validation (sometimes make doesn't produce bin, so we make it from hex)
        if not os.path.exists(orig_bin):
             run_command(["arm-none-eabi-objcopy", "-I", "ihex", "-O", "binary", orig_hex, orig_bin])
        
        with open(orig_bin, "rb") as f: fw_data = bytearray(f.read())
        
        if config['mode'] == '1':
            offset = fw_data.find(b"LinkyTagDynamicSeedPlaceholder!!")
            if offset == -1: return False, None, "Seed Placeholder not found"
            with open(seed_bin_file, "rb") as f: seed_data = f.read()
            fw_data[offset : offset+len(seed_data)] = seed_data
        else:
            offset = fw_data.find(b"OFFLINEFINDINGPUBLICKEYHERE!")
            if offset == -1: return False, None, "Key Placeholder not found"
            with open(key_file_path, "rb") as f: key_data = f.read()
            real_key = key_data[1:]
            fw_data[offset : offset+len(real_key)] = real_key
            
        with open(patch_bin, "wb") as f: f.write(fw_data)
        
        # Use dynamic offset
        run_command(["arm-none-eabi-objcopy", "-I", "binary", "-O", "ihex", "--change-addresses", chip_cfg['offset'], patch_bin, patch_hex])
        log("Binary patched. | 配置注入完成", "success", session_id=session_id)

        # --- 4. Final Bundle Packing (After Compilation) ---
        # Add the firmware hex to zip
        files_to_zip.append((patch_hex, "firmware.hex"))
        
        # Add SoftDevice hex to zip
        sd_path = os.path.join(PROJECT_ROOT, chip_cfg['sd_hex'])
        log(f"Bundle created for session {session_id}", "info", session_id=session_id)
        if os.path.exists(sd_path):
            files_to_zip.append((sd_path, "softdevice.hex"))

        # Create Offline Flash Scripts
        flash_sh_content = f"""#!/bin/bash
# Auto-generated offline flash script for {chip_cfg['name']}
echo "========================================="
echo "  Offline Flasher for {device_name}"
echo "========================================="

# Change to script directory to find firmware.hex
cd "$(dirname "$0")" || exit


# Detect Chip Family
FAMILY="{chip_cfg['family']}"
OOCD_TARGET="{chip_cfg['openocd_target']}"

echo "Select Debugger:"
echo "1. ST-Link V2/V3 (OpenOCD)"
echo "2. J-Link (nrfjprog)"
read -p "Choice [1]: " CHOICE
CHOICE=${{CHOICE:-1}}

if [ "$CHOICE" == "1" ]; then
    echo "Starting OpenOCD for $FAMILY..."
    openocd -f interface/stlink.cfg -f $OOCD_TARGET -c "init; reset halt; $FAMILY mass_erase; program softdevice.hex verify; program firmware.hex verify; reset; exit"
else
    echo "Starting nrfjprog for $FAMILY..."
    nrfjprog -f $FAMILY --program softdevice.hex --chiperase --verify 
    nrfjprog -f $FAMILY --program firmware.hex --verify --reset
fi

echo "Done."
read -p "Press Enter to exit..."
"""
        
        flash_bat_content = f"""@echo off
rem Auto-generated offline flash script for {chip_cfg['name']}
echo =========================================
echo   Offline Flasher for {device_name}
echo =========================================

rem Change to script directory
cd /d "%~dp0"


set FAMILY={chip_cfg['family']}
set OOCD_TARGET={chip_cfg['openocd_target']}

echo Select Debugger:
echo 1. ST-Link V2/V3 (OpenOCD)
echo 2. J-Link (nrfjprog)
set /p CHOICE="Choice [1]: "
if "%CHOICE%"=="" set CHOICE=1

if "%CHOICE%"=="1" (
    echo Starting OpenOCD for %FAMILY%...
    openocd -f interface/stlink.cfg -f %OOCD_TARGET% -c "init; reset halt; %FAMILY% mass_erase; program softdevice.hex verify; program firmware.hex verify; reset; exit"
) else (
    echo Starting nrfjprog for %FAMILY%...
    nrfjprog -f %FAMILY% --program softdevice.hex --chiperase --verify
    nrfjprog -f %FAMILY% --program firmware.hex --verify --reset
)

echo Done.
pause
"""
        
        # Write scripts to session dir
        with open(os.path.join(output_dir, "flash_linux.sh"), "w") as f:
            f.write(flash_sh_content)
        os.chmod(os.path.join(output_dir, "flash_linux.sh"), 0o755)
            
        with open(os.path.join(output_dir, "flash_win.bat"), "w") as f:
            f.write(flash_bat_content)
            
        files_to_zip.append((os.path.join(output_dir, "flash_linux.sh"), "flash_linux.sh"))
        files_to_zip.append((os.path.join(output_dir, "flash_win.bat"), "flash_win.bat"))

        # --- Create Zip Bundle (In Session Dir) ---
        bundle_filename = f"{device_name}_bundle.zip"
        bundle_path = os.path.join(output_dir, bundle_filename)
        
        with zipfile.ZipFile(bundle_path, 'w') as zf:
            for file_path, arcname in files_to_zip:
                if os.path.exists(file_path):
                    zf.write(file_path, arcname)
        
        log(f"Bundle created: {bundle_filename} | 资源包已打包", "info")

        return True, {
            "device_name": device_name,
            "patch_hex": patch_hex,
            "bundle_file": bundle_filename, # Return filename for download route
            "bundle_path": bundle_path, # Return full path for internal use
            "chip_cfg": chip_cfg
        }, None

    except Exception as e:
        return False, None, str(e)

@app.route('/api/flash', methods=['POST'])
def api_flash():
    if STATE["is_flashing"]:
        return jsonify({"error": "Busy"}), 400
    
    config = request.json
    STATE["is_flashing"] = True
    STATE["log_history"] = [] # Clear logs
    
    # Run flashing in background thread
    thread = threading.Thread(target=flash_task, args=(config,))
    thread.daemon = True
    thread.start()
    
    return jsonify({"success": True, "message": "Flash process started"})

def flash_task(config):
    # Logs are cleared in api_flash now to ensure fresh start
    STATE["status_message"] = "Initializing..."
    STATE["last_generated_file"] = None
    
    # Get initial Chip Config (may be overridden by auto-detection)
    chip_id = config.get('chip', '1')
    CHIP_CFG = CHIP_MAP.get(chip_id)
    if not CHIP_CFG:
        log(f"Invalid Chip ID: {chip_id}", "error")
        STATE["is_flashing"] = False
        return

    try:
        log("-" * 40, "info")
        log(f"PRE-CHECK: 启动链路探测 | Probing Hardware Link", "accent")
        log("-" * 40, "info")
        
        # --- 0. Hardware Pre-Check (BEFORE compiling!) ---
        STATE["status_message"] = "Checking Hardware..."
        log("Checking debugger & chip connection... | 正在检测调试器与芯片连接...", "info")
        
        hw_success, debugger_info, detected_chip, error_type, error_msg = check_hardware_connection(config, CHIP_CFG)
        
        if debugger_info:
            log(f"Debugger: {debugger_info} ✓ | 调试器已就绪", "success")
            STATE["status_message"] = f"Debugger: {debugger_info}"
        
        if not hw_success:
            if error_type == 'debugger_missing':
                STATE["status_message"] = f"ERROR: Debugger Not Found"
                log(f"DEBUGGER ERROR: {error_msg}", "error")
            elif error_type == 'chip_disconnected':
                STATE["status_message"] = f"ERROR: Chip Disconnected"
                log(f"CHIP ERROR: {error_msg}", "error")
            elif error_type == 'chip_protected':
                STATE["status_message"] = f"ERROR: Chip Protected"
                log(f"PROTECTION ERROR: {error_msg}", "error")
            else:
                STATE["status_message"] = f"ERROR: Hardware Check Failed"
                log(f"HARDWARE ERROR: {error_msg}", "error")
            
            STATE["is_flashing"] = False
            return
        
        # --- Auto-select chip config based on detected chip ---
        if detected_chip and detected_chip in CHIP_NAME_TO_KEY:
            auto_chip_id = CHIP_NAME_TO_KEY[detected_chip]
            CHIP_CFG = CHIP_MAP.get(auto_chip_id, CHIP_CFG)
        
        STATE["status_message"] = f"Chip: {CHIP_CFG['name']}"
        log(f"Chip: {CHIP_CFG['name']} ✓ | 芯片已就绪", "success")
        log("[感知系统] 硬件链路验证通过，正在启动智能构建流程... | [Sensing] Link verified. Starting smart build process...", "success")
        
        # --- 1. Generate Firmware ---
        STATE["status_message"] = "Generating Firmware..."
        success, result, err = generate_firmware(config, CHIP_CFG)
        if not success:
            raise Exception(err)
            
        device_name = result["device_name"]
        patch_hex = result["patch_hex"]
        CHIP_CFG = result["chip_cfg"] # Update CHIP_CFG in case it was auto-detected
        # STATE["current_device"] and STATE["last_generated_file"] removed for session isolation
        
        autoflash = config.get('autoflash', False)
        if autoflash:
            STATE["status_message"] = "Waiting for Device..."
            log("Waiting for connection...", "warning")
        else:
            STATE["status_message"] = "Flashing..."
            log("Flashing device...", "info")

        # Loop for auto-flash or run once
        while True:
            if STATE["stop_signal"]: break
            
            try:
                # Perform the flash
                perform_flash(CHIP_CFG, patch_hex, config['debugger'], config.get('flash_sd', False), probe_only=False)
                
                if autoflash:
                    STATE["status_message"] = "Cycle Complete. Remove device."
                    log("Cycle Done. Re-insert new device...", "info")
                    time.sleep(3) # Debounce
                else:
                    break # Single run done
                    
            except Exception as e:
                # Wait and retry for autoflash if it's a connection error
                if autoflash:
                    time.sleep(1)
                    continue
                else:
                    raise e

    except Exception as e:
        log(f"ERROR: {str(e)}", "error")
        STATE["status_message"] = "Error"
    finally:
        STATE["is_flashing"] = False
        STATE["stop_signal"] = False


# --- Routes ---
@app.route('/')
def home():
    """Render the main page"""
    return render_template('index.html')

@app.route('/api/stop', methods=['POST'])
def api_stop():
    STATE["stop_signal"] = True
    return jsonify({"status": "stopping"})

@app.route('/api/logs')
def api_logs():
    session_id = request.args.get('session_id', 'global')
    start = int(request.args.get('start', 0))
    
    session_logs = STATE["logs"].get(session_id, [])
    new_logs = session_logs[start:]
    
    # Get session-specific is_flashing status
    session_state = STATE["session_state"].get(session_id, {})
    is_flashing = session_state.get("is_flashing", False)
    
    return jsonify({
        "logs": new_logs, 
        "next_index": len(session_logs),
        "status_message": STATE["status_message"],
        "is_flashing": is_flashing
    })

@app.route('/api/download/<path:filename>')
def api_download(filename):
    """Serve global config files"""
    return send_from_directory(CONFIG_DIR, filename, as_attachment=True)

@app.route('/api/session_download/<session_id>/<path:filename>')
def api_session_download(session_id, filename):
    """Serve session-isolated files"""
    # Security: Ensure session_id is a simple alphanumeric string to prevent directory traversal
    if not session_id.isalnum(): return "Invalid session ID", 400
    
    session_dir = os.path.join(SESSIONS_DIR, session_id)
    return send_from_directory(session_dir, filename, as_attachment=True)

@app.route('/api/history')
def api_history():
    """List generated device bundles - session-isolated by default, global if requested"""
    session_id = request.args.get('session_id')  # Get session_id from query params
    show_all = request.args.get('show_all', 'false').lower() == 'true'  # Optional: show all files
    
    files = []
    try:
        if show_all:
            # Global mode: show all files (legacy behavior)
            # 1. Scan global CONFIG_DIR for legacy bundles
            pattern = os.path.join(CONFIG_DIR, "*_bundle.zip")
            for fpath in glob.glob(pattern):
                fname = os.path.basename(fpath)
                name = fname.replace("_bundle.zip", "")
                ts = os.path.getmtime(fpath)
                time_str = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
                files.append({
                    "name": name,
                    "filename": fname,
                    "time": time_str,
                    "ts": ts,
                    "source": "global"
                })
            
            # 2. Scan all session directories
            if os.path.exists(SESSIONS_DIR):
                for sid in os.listdir(SESSIONS_DIR):
                    session_path = os.path.join(SESSIONS_DIR, sid)
                    if not os.path.isdir(session_path):
                        continue
                    
                    session_pattern = os.path.join(session_path, "*_bundle.zip")
                    for fpath in glob.glob(session_pattern):
                        fname = os.path.basename(fpath)
                        name = fname.replace("_bundle.zip", "")
                        ts = os.path.getmtime(fpath)
                        time_str = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
                        files.append({
                            "name": name,
                            "filename": fname,
                            "time": time_str,
                            "ts": ts,
                            "source": "session",
                            "session_id": sid
                        })
        else:
            # Session-isolated mode: show only this session's files
            if session_id and os.path.exists(SESSIONS_DIR):
                session_path = os.path.join(SESSIONS_DIR, session_id)
                if os.path.isdir(session_path):
                    session_pattern = os.path.join(session_path, "*_bundle.zip")
                    for fpath in glob.glob(session_pattern):
                        fname = os.path.basename(fpath)
                        name = fname.replace("_bundle.zip", "")
                        ts = os.path.getmtime(fpath)
                        time_str = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
                        files.append({
                            "name": name,
                            "filename": fname,
                            "time": time_str,
                            "ts": ts,
                            "source": "session",
                            "session_id": session_id
                        })
        
        # Sort by latest first
        files.sort(key=lambda x: x['ts'], reverse=True)
    except Exception as e:
        log(f"History fetch error: {e}", "error")
    return jsonify({"files": files})

@app.route('/api/history/delete', methods=['POST'])
def api_delete_history():
    """Delete selected files (supports both global and session files)"""
    data = request.json
    files = data.get('files', [])  # Changed from 'filenames' to 'files' to include metadata
    deleted = []
    errors = []
    
    for file_info in files:
        # Support both old format (string) and new format (dict with source/session_id)
        if isinstance(file_info, str):
            fname = file_info
            source = 'global'
            session_id = None
        else:
            fname = file_info.get('filename')
            source = file_info.get('source', 'global')
            session_id = file_info.get('session_id')
        
        # Security check
        if os.sep in fname or '..' in fname or not fname.endswith('_bundle.zip'):
            errors.append(f"Invalid file: {fname}")
            continue
        
        # Determine file path based on source
        if source == 'session' and session_id:
            fpath = os.path.join(SESSIONS_DIR, session_id, fname)
        else:
            fpath = os.path.join(CONFIG_DIR, fname)
        
        try:
            if os.path.exists(fpath):
                os.remove(fpath)
                deleted.append(fname)
            else:
                errors.append(f"Not found: {fname}")
        except Exception as e:
            errors.append(f"Error {fname}: {str(e)}")
            
    return jsonify({"success": True, "deleted": deleted, "errors": errors})

@app.route('/api/history/archive', methods=['POST'])
def api_archive_history():
    """Zip multiple selected bundles into one"""
    data = request.json
    filenames = data.get('filenames', [])
    if not filenames:
        return jsonify({"error": "No files selected"}), 400
        
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    archive_name = f"Batch_Keys_{timestamp}.zip"
    archive_path = os.path.join(CONFIG_DIR, archive_name)
    
    try:
        with zipfile.ZipFile(archive_path, 'w') as zf:
            for fname in filenames:
                fpath = os.path.join(CONFIG_DIR, fname)
                if os.path.exists(fpath):
                    # Store as flat file inside zip
                    zf.write(fpath, fname) 
        
        return jsonify({"success": True, "download_url": f"/download/{archive_name}"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/detect_debugger')
def api_detect_debugger():
    """
    Detect locally connected debugger. 
    NOW: In Hybrid Mode, we can also check if Local Bridge is running (port 5001).
    But this is Server-Side python. 
    If Server is Cloud, it CANNOT check User's USB.
    So this endpoint is only relevant for LOCAL deployment.
    """
    try:
        # Check USB devices using system_profiler on macOS
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        
        # Tighten the check to avoid false positives from "Host", "System", etc.
        # REMOVED "STM32" because some USB Hubs identify as "STM32 Virtual COM Port" but are NOT debuggers.
        # ST-Link debuggers usually have "STLink" or "ST-Link" in their name.
        # REMOVED .lower() check to avoid matching random system strings containing "stlink" (unlikely but possible).
        is_st = "STLink" in output or "ST-Link" in output or "STLINK" in output
        is_jlink = "J-Link" in output
        is_dap = "CMSIS-DAP" in output or "DAPLink" in output or "Mbed" in output
        
        connected = is_st or is_jlink or is_dap
        
        available = []
        if is_jlink: available.append('1')
        if is_dap: available.append('3')
        if is_st: available.append('2')

        debugger_name = None
        debugger_id = None
        
        # Priority Logic: J-Link > DAPLink > ST-Link
        if is_jlink: 
            debugger_name = "Segger J-Link"
            debugger_id = '1'
        elif is_dap:
            debugger_name = "DAPLink (CMSIS-DAP)"
            debugger_id = '3'
        elif is_st: 
            debugger_name = "ST-Link"
            debugger_id = '2'
            
        return jsonify({
            "detected": connected,
            "connected": connected,
            "debugger": debugger_id,
            "name": debugger_name,
            "available": available
        })
    except Exception as e:
        return jsonify({"detected": False, "connected": False, "error": str(e)})


@app.route('/api/generate', methods=['POST'])
def api_generate():
    """
    Cloud Firmware Generation Endpoint.
    Compiles firmware and patches it, returns HEX content.
    Does NOT flash.
    """
    config = request.json
    session_id = config.get('session_id')  # Get session_id from request
    set_session_state(session_id, "is_flashing", True)  # Mark busy during build
    
    try:
        # Get chip config
        chip_id = config.get('chip', '1')
        CHIP_CFG = CHIP_MAP.get(chip_id)
        if not CHIP_CFG: raise Exception("Invalid Chip ID")
        
        log(f"[Cloud] Requesting firmware...", "accent")
        
        # 1. Generate & Compile
        success, result, err = generate_firmware(config, CHIP_CFG)
        if not success: raise Exception(err)
        
        # 2. Read HEX content
        hex_file = result["patch_hex"]
        with open(hex_file, 'r') as f:
            hex_content = f.read()
            
        # Determine Download URL base
        sess_id = config.get('session_id')
        filename = os.path.basename(result['bundle_file'])
        
        if sess_id:
            dl_url = f"/api/session_download/{sess_id}/{filename}"
        else:
            dl_url = f"/api/download/{filename}"
            
        return jsonify({
            "success": True, 
            "hex": hex_content,
            "device_name": result["device_name"],
            "bundle_url": dl_url
        })
        
    except Exception as e:
        log(f"[Cloud] Build Error: {str(e)}", "error")
        return jsonify({"success": False, "error": str(e)}), 500
    finally:
        set_session_state(session_id, "is_flashing", False)

@app.route('/api/flash_hex', methods=['POST'])
def api_flash_hex():
    """
    Accepts arbitrary HEX data to flash using local backend (OpenOCD/JLink).
    Design for 'Hybrid Mode': Cloud Generate -> Frontend -> Local Flash.
    Payload: { "hex": "...", "chip_name": "nRF51822", "debugger": "2" }
    """
    if STATE["is_flashing"]:
        return jsonify({"error": "Already flashing"}), 400
        
    data = request.json
    hex_content = data.get('hex')
    chip_name = data.get('chip_name', 'nRF52832') # Default to nRF52832
    debugger = data.get('debugger', '2') # Default ST-Link
    
    if not hex_content: return jsonify({"error": "Missing hex content"}), 400
    
    # Resolve chip config
    target_chip = None
    for k, v in CHIP_MAP.items():
        if v['name'] == chip_name:
            target_chip = v
            break
    if not target_chip: 
        log(f"Chip name '{chip_name}' not found, defaulting to nRF52832", "warning")
        target_chip = CHIP_MAP['2'] # Default to nRF52832 if not found
    
    # Save temp hex
    tmp_hex = os.path.join(PROJECT_ROOT, "temp_flash.hex")
    with open(tmp_hex, "w") as f:
        f.write(hex_content)
        
    def run_flash():
        STATE["is_flashing"] = True
        STATE["status_message"] = "Local Flashing..."
        try:
            log(f"Starting Local Flash for {chip_name}...", "info")
            perform_flash(target_chip, tmp_hex, debugger, flash_sd=False, probe_only=False)
            STATE["status_message"] = "Flash Complete"
        except Exception as e:
            log(f"Local Flash Error: {str(e)}", "error")
            STATE["status_message"] = "Error"
        finally:
            STATE["is_flashing"] = False
            if os.path.exists(tmp_hex): os.remove(tmp_hex)
            
    t = threading.Thread(target=run_flash)
    t.start()
    
    return jsonify({"success": True})



if __name__ == '__main__':
    if not os.path.exists(os.path.join(PROJECT_ROOT, 'templates')):
        os.makedirs(os.path.join(PROJECT_ROOT, 'templates'))
    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR)
        
    log("nRF5 AirTag Web Tool Started at http://127.0.0.1:52810", "success")
    app.run(host='0.0.0.0', port=52810)
