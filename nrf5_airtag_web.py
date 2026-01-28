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
    "is_flashing": False,
    "current_device": "",
    "logs": [],
    "last_log_index": 0,
    "status_message": "Ready",
    "last_generated_file": None,
    "stop_signal": False
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

# Auto-detection: map chip name to config key
CHIP_NAME_TO_KEY = {
    "nRF51822": "1",
    "nRF52832": "2",
    "nRF52810": "3",
    "nRF52811": "4",
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

def run_command(cmd, cwd=None, timeout=None):
    """Run shell command and capture output"""
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        if proc.returncode != 0:
            return False, proc.stderr.strip()
        return True, proc.stdout.strip()
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)

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
            else:
                return False, None, None, 'debugger_missing', "J-Link 调试器未检测到。请检查 USB 连接。"
        else:  # ST-Link
            # ST-Link shows as "STM32 STLink" on macOS, also check other variations
            if "STLink" in output or "ST-Link" in output or "STLINK" in output or "stlink" in output.lower():
                debugger_info = "ST-Link V2"
                if "STLINK-V3" in output or "V3" in output:
                    debugger_info = "ST-Link V3"
            else:
                return False, None, None, 'debugger_missing', "ST-Link 调试器未检测到。请检查 USB 连接。"
    except Exception as e:
        return False, None, None, 'debugger_missing', f"调试器检测失败: {str(e)}"
    
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
            
    else:  # ST-Link (OpenOCD)
        try:
            # Quick OpenOCD test
            target_file = chip_cfg.get('openocd_target', 'target/nrf51.cfg')
            success, output = run_command([
                "openocd", "-f", "interface/stlink.cfg", "-f", target_file,
                "-c", "init; targets; shutdown"
            ], timeout=8)
            
            if success:
                if "target halted" in output.lower() or "cortex_m" in output.lower() or "target state" in output.lower():
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
                return False, debugger_info, None, 'chip_disconnected', "SWD 通信失败。请检查连线和目标芯片电源。"
            else:
                return False, debugger_info, None, 'chip_disconnected', "无法连接芯片。请检查调试器与芯片的连线。"
                
        except Exception as e:
            return False, debugger_info, None, 'chip_disconnected', f"OpenOCD 检测失败: {str(e)}"
    
    return True, debugger_info, chip_info, None, None

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
    
    # Get initial Chip Config (may be overridden by auto-detection)
    chip_id = config.get('chip', '1')
    CHIP_CFG = CHIP_MAP.get(chip_id)
    if not CHIP_CFG:
        log(f"Invalid Chip ID: {chip_id}", "error")
        STATE["is_flashing"] = False
        return

    try:
        log("-" * 40, "info")
        log(f"READY: {device_name} | 启动刷写任务 | Starting Flash Task", "accent")
        log("-" * 40, "info")
        log(f"Config: {config}", "info")
        
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
            if auto_chip_id != chip_id:
                log(f"[感知系统] 硬件架构偏移: 检测到 {detected_chip}，已自动同步固件配置 | [Sensing] Architecture mismatch: {detected_chip} detected, auto-synced.", "info")
            CHIP_CFG = CHIP_MAP.get(auto_chip_id, CHIP_CFG)
        
        STATE["status_message"] = f"Chip: {CHIP_CFG['name']}"
        log(f"Chip: {CHIP_CFG['name']} ✓ | 芯片已就绪", "success")
        
        log("[感知系统] 硬件链路验证通过，正在启动智能构建流程... | [Sensing] Link verified. Starting smart build process...", "success")
        
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
            log(f"Generated Seed: {seed_hex} | 已生成随机种子", "accent")
            
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
                    log("Offline keys generated. | 离线密钥对已生成", "info")
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
                        log("Keyfile generated and moved to config. | 密钥文件已就绪", "success")
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
                log(f"Bundle created: {zip_name} | 资源包已打包", "info")
            except Exception as e:
                log(f"Zip creation failed: {e}", "warning")


        # --- 3. Build ---
        STATE["status_message"] = "Compiling Firmware..."
        log(f"Compiling firmware for {CHIP_CFG['name']}... | 正在编译固件...", "info")
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
        log("Compilation success. | 固件编译完成", "success")
        
        # --- 4. Patch ---
        STATE["status_message"] = "Patching Binary..."
        log("Patching binary... | 正在注入引导配置...", "info")
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
        log("Binary patched. | 配置注入完成", "success")
        
        # --- 5. Flash or Loop ---
        autoflash = config.get('autoflash', False)
        if autoflash:
            STATE["status_message"] = "Waiting for Device..."
            log("Waiting for connection...", "warning")
        else:
            STATE["status_message"] = "Flashing..."
            log("Flashing device...", "info")

        # Inner helper to perform one flash attempt
        def do_flash_one_attempt(timeout_val=None, probe_only=False):
            if config['debugger'] == '1': # J-Link
                nrfjprog_success = False
                
                # nrfjprog is not good for probing, skips directly to JLinkExe if probing
                if not probe_only: 
                    try:
                        if config.get('flash_sd', False):
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
                        f.write(f"device {jlink_device}\n")
                        f.write("si SWD\n")
                        f.write("speed 4000\n")
                        f.write("connect\n")
                        if probe_only:
                            f.write("exit\n") # Just connect and exit
                        else:
                            f.write("r\n")
                            f.write("h\n")
                            if config.get('flash_sd', False):
                                sd_full_path = os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])
                                if CHIP_CFG['family'] == 'nrf52':
                                    f.write("w4 4001e504 2\n") # ERASE
                                    f.write("w4 4001e50c 1\n") # ERASEALL
                                    f.write("sleep 100\n")
                                    f.write("w4 4001e504 0\n")
                                    f.write("r\n")
                                else:
                                    f.write("erase\n")
                                f.write(f"loadfile {sd_full_path}\n")
                                f.write("r\n")
                            f.write(f"loadfile {patch_hex}\n")
                            f.write("r\n")
                            f.write("g\n")
                            f.write("exit\n")
                    
                    # Use timeout if provided
                    t_jlink = timeout_val if timeout_val else 20
                    success, output = run_command(["JLinkExe", "-CommandFile", jlink_script_path], timeout=t_jlink)
                    if os.path.exists(jlink_script_path): os.remove(jlink_script_path)
                    
                    if not success or "Cannot connect" in output or "FAILED" in output or "Could not connect" in output or "Failed to attach" in output or "Error occurred" in output:
                         raise Exception("JLinkExe failed: Connection Error")
                    if not probe_only: log("SUCCESS (JLinkExe)", "success")
                    
            else: # ST-Link
                flash_family = CHIP_CFG['family']
                o_cmds = []
                if probe_only:
                    o_cmds = ["init", "exit"]
                else: 
                    o_cmds = ["init", "halt", f"{flash_family} mass_erase"]
                    if config.get('flash_sd', False):
                        o_cmds.append(f"program {os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])} verify")
                    o_cmds.append(f"program {patch_hex} verify")
                    o_cmds.append("reset; exit")
                
                # Use timeout if provided
                t_st = timeout_val if timeout_val else 20
                success, output = run_command(["openocd", "-f", "interface/stlink.cfg", "-f", CHIP_CFG['openocd_target'], "-c", "; ".join(o_cmds)], timeout=t_st)
                if not success: raise Exception(f"OpenOCD: {output}")

        # Execute Loop
        if autoflash:
            STATE["status_message"] = "Waiting..."
            log("Mode: Auto-Flash. Waiting for device...", "warning")

        while True:
            # 1. Check Cancellation often
            if STATE.get('stop_signal'):
                STATE["status_message"] = "Cancelled"
                log("Flash task cancelled.", "warning")
                break
            
            try:
                # --- Step 1: Check Debugger Connection (USB) ---
                # This is a lightweight check to ensure the probe itself is plugged in.
                if config['debugger'] == '1': # J-Link
                    # On macOS, we can check for J-Link in ioreg quickly, but JLinkExe is authoritative.
                    pass 
                
                if autoflash:
                    STATE["status_message"] = "WAITING_CONNECTION: Waiting for Target Chip..."
                    # --- Step 2: Probe Phase (Strict Connection Check) ---
                    # We use a specific probe script that attempts to CONNECT but does not erase/program.
                    try:
                        if config['debugger'] == '1': # J-Link
                            probe_script = os.path.join(PROJECT_ROOT, "probe.jlink")
                            jlink_device = ""
                            if CHIP_CFG['family'] == 'nrf51': jlink_device = "nRF51822_xxAA"
                            elif CHIP_CFG['name'] == 'nRF52832': jlink_device = "nRF52832_xxAA"
                            elif CHIP_CFG['name'] == 'nRF52810': jlink_device = "nRF52810_xxAA"

                            with open(probe_script, "w") as f:
                                f.write(f"device {jlink_device}\n")
                                f.write("si SWD\n")
                                f.write("speed 4000\n")
                                f.write("connect\n") # Try to connect
                                f.write("exit\n")
                            
                            # Run JLinkExe with short timeout
                            s_probe, o_probe = run_command(["JLinkExe", "-CommandFile", probe_script], timeout=3)
                            if os.path.exists(probe_script): os.remove(probe_script)

                            # Analyze Output
                            if not s_probe: raise Exception("Probe Timeout")
                            
                            if "Could not connect" in o_probe or "Failed to attach" in o_probe or "Error occurred" in o_probe:
                                time.sleep(0.5); continue
                            
                            if "Cortex-M" not in o_probe and "Device" not in o_probe:
                                time.sleep(0.5); continue

                        else: # ST-Link (OpenOCD)
                            flash_family = CHIP_CFG['family']
                            # Just try to init. If it fails, not connected. 
                            # If it succeeds but fails later, might be protection (handled in flash step)
                            cmd = ["openocd", "-f", "interface/stlink.cfg", "-f", CHIP_CFG['openocd_target'], "-c", "init; exit"]
                            s_probe, o_probe = run_command(cmd, timeout=5)
                            
                            if not s_probe:
                                # OpenOCD returns non-zero on init fail
                                # Common errors: "target not examined", "unable to connect", "Error: init mode failed"
                                if "Error:" in o_probe or "unable to connect" in o_probe:
                                    time.sleep(0.5); continue
                                raise Exception("Probe Error") # Other error
                            
                            # If return code 0, check output just in case
                            if "target not examined" in o_probe:
                                time.sleep(0.5); continue

                        # If we get here, Connection is GOOD.
                        STATE["status_message"] = "DEVICE_CONNECTED: Chip Detected! Flashing..."
                        log("Debugger connected. Chip detected. | 调试器已连接，芯片已感知", "success")
                        log("Starting Flash Process... | 启动自动刷写流程...", "info")
                        
                        # --- Step 3: Perform Flash ---
                        do_flash_one_attempt(timeout_val=60, probe_only=False)
                        
                        STATE["status_message"] = f"SUCCESS: {device_name} Flashed!"
                        log(f"SUCCESS: {device_name} Flashed!", "success")
                        break # Done for this task

                    except Exception as e:
                        # Probe failed, wait and retry
                        time.sleep(0.5)
                        continue
                else:
                    # Normal Mode: Direct Flash
                    # We still do the check implicitly in do_flash_one_attempt
                    log("Checking Debugger & Chip... | 正在建立硬件连接...", "info")
                    do_flash_one_attempt(timeout_val=60, probe_only=False)
                    STATE["status_message"] = f"SUCCESS: {device_name} Flashed!"
                    log(f"SUCCESS: {device_name} Flashed! | 任务成功完成", "success")
                    break 
                    
            except Exception as e:
                # If Flash failed (not probe), we log error and break
                log(f"Flash Error: {str(e)}", "red")
                # Special handling: If it was a connection error during flash, maybe we shouldn't break in autoflash?
                # But user wants strict checks. If flash started and failed, it's an Error.
                STATE["status_message"] = "Error"
                break

    except Exception as e:
        log(f"ERROR: {str(e)}", "error")
        STATE["status_message"] = "Error"
    finally:
        STATE["is_flashing"] = False
        STATE["stop_signal"] = False


# --- Routes ---
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/download/<path:filename>')
def download_file(filename):
    return send_from_directory(CONFIG_DIR, filename, as_attachment=True)

@app.route('/api/detect_debugger')
def api_detect_debugger():
    try:
        cmd = "ioreg -p IOUSB -l"
        output = subprocess.check_output(cmd, shell=True).decode('utf-8')
        
        # J-Link detection
        if "J-Link" in output:
            name = "Segger J-Link"
            if "J-Link OB" in output:
                name = "Segger J-Link OB"
            elif "J-Link EDU" in output:
                name = "J-Link EDU"
            return jsonify({"debugger": "1", "name": name, "detected": True})
        
        # ST-Link detection (shows as "STM32 STLink" on macOS)
        if "STLink" in output or "ST-Link" in output or "STLINK" in output:
            name = "ST-Link V2"
            if "STLINK-V3" in output or "V3" in output:
                name = "ST-Link V3"
            return jsonify({"debugger": "2", "name": name, "detected": True})
            
    except: pass
    return jsonify({"debugger": None, "name": None, "detected": False})

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
    STATE["stop_signal"] = False
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

@app.route('/api/history')
def api_get_history():
    """List all generated device bundles"""
    files = []
    try:
        # scan for *_bundle.zip
        pattern = os.path.join(CONFIG_DIR, "*_bundle.zip")
        for fpath in glob.glob(pattern):
            fname = os.path.basename(fpath)
            # format: NAME_bundle.zip
            name = fname.replace("_bundle.zip", "")
            ts = os.path.getmtime(fpath)
            time_str = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
            files.append({
                "name": name,
                "filename": fname,
                "time": time_str,
                "ts": ts
            })
        # Sort by latest first
        files.sort(key=lambda x: x['ts'], reverse=True)
    except Exception as e:
        log(f"History fetch error: {e}", "error")
    return jsonify({"files": files})

@app.route('/api/history/delete', methods=['POST'])
def api_delete_history():
    """Delete selected files"""
    data = request.json
    filenames = data.get('filenames', [])
    deleted = []
    errors = []
    
    for fname in filenames:
        # Security check: filename must be simple and exist in CONFIG_DIR
        if os.sep in fname or '..' in fname or not fname.endswith('_bundle.zip'):
            errors.append(f"Invalid file: {fname}")
            continue
            
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
        
        return jsonify({"success": True, "download_url": f"/api/download/{archive_name}"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    if not os.path.exists(os.path.join(PROJECT_ROOT, 'templates')):
        os.makedirs(os.path.join(PROJECT_ROOT, 'templates'))
    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR)
        
    log("nRF5 AirTag Web Tool Started at http://127.0.0.1:5001", "success")
    app.run(host='0.0.0.0', port=5001)
