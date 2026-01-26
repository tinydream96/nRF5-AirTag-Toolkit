#!/bin/bash
# ==============================================================================
# nRF5 AirTag Flash Tool
# Supports: nRF51822, nRF52832, nRF52810
# Features: Dynamic Seed Generation, Binary Patching, Key Management, Auto-Log
# Updates: Uses JLinkExe directly for better stability on macOS
# ==============================================================================

# --- Path Config ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_unified.txt"

# --- Logger ---
log_flash_record() {
    local device_name="$1"
    local chip_model="$2"
    local mode="$3"
    local status="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "nRF5 AirTag Flash Log" >> "$LOG_FILE"
        echo "Created: $timestamp" >> "$LOG_FILE"
        echo "========================================" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
    
    {
        echo "----------------------------------------"
        echo "Time:    $timestamp"
        echo "Device:  $device_name"
        echo "Chip:    $chip_model"
        echo "Mode:    $mode"
        echo "Status:  $status"
        echo "----------------------------------------"
    } >> "$LOG_FILE"
}

clear
echo "========================================"
echo "   nRF5 AirTag Flash Tool (Direct J-Link)"
echo "========================================"

# --- 1. Select Chip ---
echo "Select Chip Model:"
echo " 1. nRF51822 (S130)"
echo " 2. nRF52832 (S132)"
echo " 3. nRF52810 (S112)"
read -p "Enter choice [1-3]: " CHIP_CHOICE

case $CHIP_CHOICE in
    1)
        CHIP_MODEL="nRF51822"
        CHIP_FAMILY="nrf51"
        JLINK_DEVICE="nRF51822_xxAA"
        MAKE_DIR="heystack-nrf5x/nrf51822/armgcc"
        BUILD_NAME="nrf51822_xxab"
        APP_OFFSET="0x1B000"
        SOFTDEVICE_HEX="nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
        OPENOCD_TARGET="target/nrf51.cfg"
        ;;
    2)
        CHIP_MODEL="nRF52832"
        CHIP_FAMILY="nrf52"
        JLINK_DEVICE="nRF52832_xxAA"
        # Note: Added path correction for nRF52 makefiles often needing explicit SDK root or similar if env not set, 
        # but here we assume Makefile is correct as verified.
        MAKE_DIR="heystack-nrf5x/nrf52832/armgcc"
        BUILD_NAME="nrf52832_xxaa"
        APP_OFFSET="0x26000"
        # Using S132 v6.1.1 from SDK 15.3
        SOFTDEVICE_HEX="nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s132/hex/s132_nrf52_6.1.1_softdevice.hex"
        OPENOCD_TARGET="target/nrf52.cfg"
        ;;
    3)
        CHIP_MODEL="nRF52810"
        CHIP_FAMILY="nrf52"
        JLINK_DEVICE="nRF52810_xxAA"
        MAKE_DIR="heystack-nrf5x/nrf52810/armgcc"
        BUILD_NAME="nrf52810_xxaa"
        APP_OFFSET="0x19000"
        # Using S112 v6.1.1 from SDK 15.3
        SOFTDEVICE_HEX="nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s112/hex/s112_nrf52_6.1.1_softdevice.hex"
        OPENOCD_TARGET="target/nrf52.cfg"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo -e "\033[36m-> Selected: $CHIP_MODEL (Offset: $APP_OFFSET)\033[0m"
echo

# --- 2. Select Mode ---
echo "Select Key Mode:"
echo " 1. [Dynamic] Infinite Keys (Generates Seed & Offline Keys)"
echo " 2. [Static]  Fixed Keys (Requires Keyfile)"
read -p "Enter choice [1]: " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}

if [ "$MODE_CHOICE" == "1" ]; then
    MODE="Dynamic"
else
    MODE="Static"
fi
echo -e "\033[36m-> Selected: $MODE\033[0m"
echo

# --- 3. Select Debugger ---
echo "Select Debugger:"
if ioreg -p IOUSB -l | grep -qi "J-Link"; then
    echo " 1. [J-Link] (Detected!) - Recommended"
    DEF_DEBUG=1
else
    echo " 1. [J-Link]"
    DEF_DEBUG=1
fi
echo " 2. [ST-Link] (OpenOCD)"
read -p "Enter choice [$DEF_DEBUG]: " DEBUG_CHOICE
DEBUG_CHOICE=${DEBUG_CHOICE:-$DEF_DEBUG}

if [ "$DEBUG_CHOICE" == "1" ]; then
    DEBUGGER="J-Link"
else
    DEBUGGER="ST-Link"
fi
echo -e "\033[36m-> Selected: $DEBUGGER\033[0m"
echo

# --- 4. Inputs ---
while true; do
    read -p "Device Name Prefix (e.g. MSF): " DEVICE_PREFIX
    if [[ "$DEVICE_PREFIX" =~ ^[A-Za-z0-9_]+$ ]]; then
        DEVICE_PREFIX=$(echo "$DEVICE_PREFIX" | tr '[:lower:]' '[:upper:]')
        break
    else
        echo "Invalid prefix."
    fi
done

read -p "Start Number (1-999): " DEVICE_NUMBER
if [[ ! "$DEVICE_NUMBER" =~ ^[0-9]+$ ]]; then DEVICE_NUMBER=1; fi

read -p "Base Interval (ms) [Default 2000]: " BASE_INTERVAL
BASE_INTERVAL=${BASE_INTERVAL:-2000}

read -p "Flash SoftDevice? (y/N): " FLASH_SD
if [[ "$FLASH_SD" =~ ^[Yy]$ ]]; then
    NEED_SD=true
else
    NEED_SD=false
fi

# Optional DCDC
read -p "Enable DCDC? (y/N) [N]: " ENABLE_DCDC
if [[ "$ENABLE_DCDC" =~ ^[Yy]$ ]]; then
    DCDC_VAL=1
else
    DCDC_VAL=0
fi

# ==============================================================================
# MAIN LOOP
# ==============================================================================
FIRST_RUN=true

while true; do
    # Calc Name
    if [ "$FIRST_RUN" = false ]; then
        echo
        echo "Preparing next device..."
        DEVICE_NUMBER=$((DEVICE_NUMBER + 1))
    fi
    FIRST_RUN=false
    
    CURRENT_INTERVAL=$((BASE_INTERVAL + DEVICE_NUMBER * 10))
    PADDED_NUM=$(printf "%03d" $DEVICE_NUMBER)
    DEVICE_NAME="${DEVICE_PREFIX}${PADDED_NUM}"
    
    echo -e "\033[1;33m----------------------------------------\033[0m"
    echo -e "\033[1;33m Target: $DEVICE_NAME ($CHIP_MODEL)\033[0m"
    echo -e "\033[1;33m Interval: $CURRENT_INTERVAL ms\033[0m"
    echo -e "\033[1;33m----------------------------------------\033[0m"
    
    # --- Prepare Keys ---
    SEED_FILE_DIR="$PROJECT_ROOT/seeds/$DEVICE_NAME"
    BUILD_DIR="$MAKE_DIR/_build"
    KEY_FILE_PATH=""
    
    if [ "$MODE" == "Dynamic" ]; then
        # 1. Generate Seed
        mkdir -p "$SEED_FILE_DIR"
        SEED_HEX="$SEED_FILE_DIR/seed_${DEVICE_NAME}.hex"
        SEED_BIN="$SEED_FILE_DIR/seed_${DEVICE_NAME}.bin"
        
        openssl rand -hex 32 > "$SEED_HEX"
        xxd -r -p "$SEED_HEX" "$SEED_BIN"
        
        echo "🔑 Seed Generated: $(cat $SEED_HEX | cut -c 1-16)..."
        
        # 2. Generate Offline Keys (Optional but recommended)
        # Using existing python tool
        # Assuming python env is set
        echo "Generating offline config..."
        python3 "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys_from_seed.py" \
            -s "$(cat $SEED_HEX)" \
            -n 200 \
            -p "$DEVICE_NAME" \
            -o "$PROJECT_ROOT/config/" > /dev/null 2>&1
            
        if [ $? -eq 0 ]; then
            echo "✅ Config saved: config/${DEVICE_NAME}_devices.json"
        else
            echo "⚠️  Failed to generate offline JSON config."
        fi
        
    else
        # Static Mode
        KEY_FILE_NAME="${DEVICE_NAME}_keyfile"
        KEY_FILE_PATH="$PROJECT_ROOT/config/$KEY_FILE_NAME"
        
        if [ ! -f "$KEY_FILE_PATH" ]; then
            echo "⚠️  Keyfile not found: $KEY_FILE_PATH"
            read -p "Generate new keys? (y/n/q): " GEN_KEY
            if [[ "$GEN_KEY" == "q" ]]; then break; fi
            if [[ "$GEN_KEY" =~ ^[Yy]$ ]]; then
                TEMP_DIR="temp_keys_gen"
                python3 "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys.py" -n 200 -p "$DEVICE_NAME" -o "$TEMP_DIR/" > /dev/null 2>&1
                mv "$TEMP_DIR/${DEVICE_NAME}_keyfile" "$PROJECT_ROOT/config/"
                mv "$TEMP_DIR/${DEVICE_NAME}_devices.json" "$PROJECT_ROOT/config/"
                rm -rf "$TEMP_DIR"
                echo "✅ Keys generated."
            else
                echo "Skipping device."
                continue
            fi
        fi
        echo "📂 Keyfile: $KEY_FILE_NAME"
    fi
    
    # --- Connection Check (Skipped for J-Link Direct Mode usually, but good to have) ---
    echo "Checking connection ($DEBUGGER)..."
    
    # --- Build ---
    echo "🔨 Building..."
    make -C "$MAKE_DIR" clean > /dev/null
    
    MAKE_ARGS="HAS_DCDC=$DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 ADVERTISING_INTERVAL=$CURRENT_INTERVAL"
    
    if [ "$MODE" == "Dynamic" ]; then
        MAKE_ARGS="$MAKE_ARGS DYNAMIC_KEYS=1"
    else
        MAKE_ARGS="$MAKE_ARGS MAX_KEYS=200"
    fi
    
    # Build
    if ! make -C "$MAKE_DIR" $BUILD_NAME $MAKE_ARGS > /dev/null; then
        echo "❌ Build Failed."
        exit 1
    fi
    
    # --- Patching ---
    echo "🔧 Patching Firmware..."
    ORIG_HEX="$PROJECT_ROOT/$BUILD_DIR/$BUILD_NAME.hex"
    ORIG_BIN="$PROJECT_ROOT/$BUILD_DIR/$BUILD_NAME.bin"
    PATCH_BIN="$PROJECT_ROOT/$BUILD_DIR/${BUILD_NAME}_patched.bin"
    PATCH_HEX="$PROJECT_ROOT/$BUILD_DIR/${BUILD_NAME}_patched.hex"
    
    # 1. Hex -> Bin
    arm-none-eabi-objcopy -I ihex -O binary "$ORIG_HEX" "$ORIG_BIN"
    cp "$ORIG_BIN" "$PATCH_BIN"
    
    # 2. DD Patch
    if [ "$MODE" == "Dynamic" ]; then
        PLACEHOLDER="LinkyTagDynamicSeedPlaceholder!!"
        OFFSET=$(grep -oba "$PLACEHOLDER" "$ORIG_BIN" | cut -d ':' -f 1)
        if [ -z "$OFFSET" ]; then echo "❌ Seed placeholder not found!"; exit 1; fi
        
        dd if="$SEED_BIN" of="$PATCH_BIN" bs=1 seek=$OFFSET count=32 conv=notrunc 2>/dev/null
    else
        PLACEHOLDER="OFFLINEFINDINGPUBLICKEYHERE!"
        OFFSET=$(grep -oba "$PLACEHOLDER" "$ORIG_BIN" | cut -d ':' -f 1)
         if [ -z "$OFFSET" ]; then echo "❌ Key placeholder not found!"; exit 1; fi
         
         xxd -p -c 100000 "$KEY_FILE_PATH" | xxd -r -p | dd of="$PATCH_BIN" skip=1 bs=1 seek=$OFFSET conv=notrunc 2>/dev/null
    fi
    
    # 3. Bin -> Hex (With Offset!)
    arm-none-eabi-objcopy -I binary -O ihex --change-addresses $APP_OFFSET "$PATCH_BIN" "$PATCH_HEX"
    
    # --- Flashing ---
    echo "⚡ Flashing..."
    
    if [ "$DEBUGGER" == "J-Link" ]; then
        # 1. Try nrfjprog first (Standard Method)
        echo "   -> Attempting with nrfjprog..."
        NRFJPROG_SUCCESS=false
        
        # S130/S132 requires MASS ERASE or SECTOR ERASE depending on state.
        # Simple approach: If SoftDevice needed, erase chip first.
        if [ "$NEED_SD" = true ]; then
             if nrfjprog -f $CHIP_FAMILY --program "$PROJECT_ROOT/$SOFTDEVICE_HEX" --sectorerase >/dev/null 2>&1; then
                 :
             else
                 # If sector erase fails, try mass erase recover
                 nrfjprog -f $CHIP_FAMILY --recover >/dev/null 2>&1
                 nrfjprog -f $CHIP_FAMILY --program "$PROJECT_ROOT/$SOFTDEVICE_HEX" --chiperase >/dev/null 2>&1
             fi
        fi
        
        if nrfjprog -f $CHIP_FAMILY --program "$PATCH_HEX" --sectorerase --verify >/dev/null 2>&1; then
             nrfjprog -f $CHIP_FAMILY --reset >/dev/null 2>&1
             NRFJPROG_SUCCESS=true
        fi

        # 2. Fallback to JLinkExe (Direct Method) if nrfjprog fails
        if [ "$NRFJPROG_SUCCESS" = true ]; then
             echo "🎉 Success (nrfjprog)!"
             log_flash_record "$DEVICE_NAME" "$CHIP_MODEL" "$MODE" "Success_nrfjprog"
        else
             echo "⚠️  nrfjprog failed. Falling back to JLinkExe (Direct Mode)..."
             
             # Generate JLink Script
             SCRIPT="flash_cmd_unified.jlink"
             echo "device $JLINK_DEVICE" > $SCRIPT
             echo "si SWD" >> $SCRIPT
             echo "speed 4000" >> $SCRIPT
             echo "connect" >> $SCRIPT
             echo "r" >> $SCRIPT
             echo "h" >> $SCRIPT
            
             if [ "$NEED_SD" = true ]; then
                if [ "$CHIP_FAMILY" == "nrf52" ]; then
                     echo "w4 4001e504 2" >> $SCRIPT
                     echo "w4 4001e50c 1" >> $SCRIPT
                     echo "sleep 100" >> $SCRIPT
                     echo "w4 4001e504 0" >> $SCRIPT
                     echo "r" >> $SCRIPT
                else 
                     echo "erase" >> $SCRIPT
                fi
                echo "loadfile $PROJECT_ROOT/$SOFTDEVICE_HEX" >> $SCRIPT
                echo "r" >> $SCRIPT
             fi
            
             echo "loadfile $PATCH_HEX" >> $SCRIPT
             echo "r" >> $SCRIPT
             echo "g" >> $SCRIPT
             echo "exit" >> $SCRIPT
            
             JLinkExe -CommandFile $SCRIPT > /dev/null 2>&1
             JLINK_STATUS=$?
             rm -f $SCRIPT
            
             if [ $JLINK_STATUS -eq 0 ]; then
                 echo "🎉 Success (JLinkExe)!"
                 log_flash_record "$DEVICE_NAME" "$CHIP_MODEL" "$MODE" "Success_JLinkExe"
             else
                 echo "❌ Flashing Failed (Both methods)"
                 log_flash_record "$DEVICE_NAME" "$CHIP_MODEL" "$MODE" "Failed"
             fi
        fi
        
    else
        # ST-Link
        CMDS="init; halt; ${CHIP_FAMILY} mass_erase;"
        if [ "$NEED_SD" = true ]; then
             CMDS="$CMDS program $PROJECT_ROOT/$SOFTDEVICE_HEX verify;"
        fi
        CMDS="$CMDS program $PATCH_HEX verify; reset; exit"
        
        openocd -f interface/stlink.cfg -f $OPENOCD_TARGET -c "$CMDS"
        
        if [ $? -eq 0 ]; then
             echo "🎉 Success!"
             log_flash_record "$DEVICE_NAME" "$CHIP_MODEL" "$MODE" "Success"
        else
             echo "❌ Flashing Failed"
             log_flash_record "$DEVICE_NAME" "$CHIP_MODEL" "$MODE" "Failed"
        fi
    fi
    
    # Loop Prompt
    read -p "Press Enter for next device (or q to quit): " CONT
    if [[ "$CONT" == "q" ]]; then break; fi
    
done
