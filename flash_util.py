
# Helper to perform one flash attempt (Refactored from flash_task)
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
                f.write(f"device {jlink_device}\n")
                f.write("si SWD\n")
                f.write("speed 4000\n")
                f.write("connect\n")
                if probe_only:
                    f.write("exit\n") # Just connect and exit
                else:
                    f.write("r\n")
                    f.write("h\n")
                    if flash_sd:
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
            if flash_sd:
                o_cmds.append(f"program {os.path.join(PROJECT_ROOT, CHIP_CFG['sd_hex'])} verify")
            o_cmds.append(f"program {patch_hex} verify")
            o_cmds.append("reset; exit")
        
        # Use timeout if provided
        t_st = timeout_val if timeout_val else 20
        success, output = run_command(["openocd", "-f", "interface/stlink.cfg", "-f", CHIP_CFG['openocd_target'], "-c", "; ".join(o_cmds)], timeout=t_st)
        if not success: raise Exception(f"OpenOCD: {output}")
        if not probe_only: log("SUCCESS (OpenOCD/ST-Link)", "success")
