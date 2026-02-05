#!/bin/bash

# Configuration
JLINK_EXE="JLinkExe"
# Using generic M0 to allow initial ID check
TARGET_DEVICE="Cortex-M0"
INTERFACE="SWD"
SPEED="4000"

# Temporary scripts
TMP_SCRIPT="/tmp/jlink_check_Connection.jlink"
TMP_UNLOCK_SCRIPT="/tmp/jlink_unlock.jlink"

# Create a temporary J-Link command script for checking connection
cat << EOF > "$TMP_SCRIPT"
connect
mem32 0x10000014, 1
mem32 0x10000100, 1
exit
EOF

echo "==========================================="
echo "   J-Link Chip Monitor (Auto-Format Mode)  "
echo "==========================================="
echo "Target Architecture: $TARGET_DEVICE"
echo "Interface: $INTERFACE"
echo "Speed: $SPEED kHz"
echo "Action: Auto-Recover (Format) on Connect"
echo "Press [CTRL+C] to stop."
echo "==========================================="
echo ""

last_status="disconnected"

perform_recover() {
    echo -e "\033[1;33m⚙️  Executing Recover (Format)...\033[0m"
    
    # 1. CRITICAL: Kill any stale processes that might hold USB handle
    killall -9 JLinkExe > /dev/null 2>&1
    killall -9 nrfjprog > /dev/null 2>&1
    
    # 2. Wait for USB to fully release (LIBUSB needs time)
    sleep 3

    # 3. Try nrfjprog first (Official tool, best for nRF51)
    if command -v nrfjprog &> /dev/null; then
        echo "   -> Attempting nrfjprog --recover ..."
        # Use timeout to prevent hanging forever. Recovery can take 30s+
        perl -e 'alarm shift; exec @ARGV' 45 nrfjprog --recover > /tmp/nrfjprog_rec.log 2>&1
        RET=$?
        if [ $RET -eq 0 ]; then
             echo -e "\033[32m   ✅ nrfjprog Recover Successful!\033[0m"
             return 0
        else
             echo "   ⚠️  nrfjprog failed (Code $RET). Trying OpenOCD fallback..."
             cat /tmp/nrfjprog_rec.log | head -n 5
        fi
    fi

    echo "   -> Attempting OpenOCD Raw Unlock..."
    
    # Kill again in case nrfjprog left something behind
    killall -9 JLinkExe > /dev/null 2>&1
    killall -9 nrfjprog > /dev/null 2>&1
    sleep 2
    
    # 4. OpenOCD Fallback: Manual Register Write
    # NVMC.CONFIG = 2 (Erase) -> 0x4001E504
    # NVMC.ERASEALL = 1 -> 0x4001E50C
    # We use 'mww' (valid even if internal debugging is partial, usually works for AP bypass)
    LOG_FILE="/tmp/openocd_recover.log"
    
    openocd -f interface/jlink.cfg -c "transport select swd" -f target/nrf51.cfg \
        -c "init; mww 0x4001e504 2; mww 0x4001e50c 1; sleep 200; mww 0x4001e504 0; shutdown" > "$LOG_FILE" 2>&1
    
    RET=$?
    # OpenOCD might return non-zero if it can't cleanly shutdown from this state, 
    # but the write might have succeeded. We check logs.
    
    if [ $RET -eq 0 ]; then
         echo -e "\033[32m   ✅ OpenOCD Unlock Command Sent!\033[0m"
    else
         echo -e "\033[33m   ⚠️  OpenOCD Code $RET (Check if device is unlocked after Power Cycle)\033[0m"
         echo "   🔍 Debug Info (OpenOCD Output):"
         echo "   ----------------------------------------"
         cat "$LOG_FILE"
         echo "   ----------------------------------------"
    fi
}

while true; do
    # Run JLinkExe
    OUTPUT=$($JLINK_EXE -device "$TARGET_DEVICE" -if "$INTERFACE" -speed "$SPEED" -autoconnect 1 -ExitOnError 1 -CommandFile "$TMP_SCRIPT" 2>&1)
    
    # Check for successful connection
    if echo "$OUTPUT" | grep -q "Found SW-DP"; then
        CORE_ID=$(echo "$OUTPUT" | grep "Found SW-DP" | head -n 1 | awk '{print $NF}')
        
        NRF51_CODE_LINE=$(echo "$OUTPUT" | grep "10000014 = ")
        NRF51_CODE_VAL=$( [ ! -z "$NRF51_CODE_LINE" ] && echo "$NRF51_CODE_LINE" | awk '{print $3}' )
        
        CHIP_MODEL="Unknown ($CORE_ID)"
        if [[ "$CORE_ID" == "0x0BB11477" ]]; then
            if [ ! -z "$NRF51_CODE_VAL" ] && [ "$NRF51_CODE_VAL" != "00000000" ]; then
                SIZE_DEC=$((16#$NRF51_CODE_VAL))
                if [ "$SIZE_DEC" -eq 256 ]; then CHIP_MODEL="nRF51822 (256kB)";
                else CHIP_MODEL="nRF51 ($SIZE_DEC Pages)"; fi
            else CHIP_MODEL="nRF51 (Locked/Unknown)"; fi
        fi

        if [ "$last_status" != "connected" ]; then
            echo -e "\n\033[32m[$(date '+%H:%M:%S')] ✅ Chip Connected!\033[0m"
            echo "   -> Model:   $CHIP_MODEL"
            echo "   -> Core ID: $CORE_ID"
            
            # --- ACTION ---
            perform_recover
            # --------------
            
            echo "   -> Ready for next."
            last_status="connected"
        else
            :
        fi
    else
        if [ "$last_status" != "disconnected" ]; then
            echo -e "\n\033[31m[$(date '+%H:%M:%S')] ❌ Connection Lost. Scanning...\033[0m"
            last_status="disconnected"
        else
             echo -ne "\rScanning... [$(date '+%H:%M:%S')] "
        fi
    fi
    sleep 1
done
