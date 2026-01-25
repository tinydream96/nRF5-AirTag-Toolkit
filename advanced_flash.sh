#!/bin/bash

# ==========================================
# nRF51822 Advanced Build & Flash (CLI)
# ==========================================
# Usage:
#   ./advanced_flash.sh -n DEVICE_NAME -m <static|dynamic> -d <jlink|stlink> [-i INTERVAL]
# ==========================================

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Defaults
DEVICE_NAME=""
MODE="dynamic"
DEBUGGER="jlink"
INTERVAL=2000

usage() {
    echo "Usage: $0 -n <NAME> [-m static|dynamic] [-d jlink|stlink] [-i INTERVAL_MS]"
    exit 1
}

while getopts "n:m:d:i:" opt; do
    case ${opt} in
        n) DEVICE_NAME=$OPTARG ;;
        m) MODE=$OPTARG ;;
        d) DEBUGGER=$OPTARG ;;
        i) INTERVAL=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$DEVICE_NAME" ]; then usage; fi

echo "🚀 Starting Flash Process for $DEVICE_NAME ($MODE, $DEBUGGER, ${INTERVAL}ms)"

# 1. Clean
make -C heystack-nrf5x/nrf51822/armgcc clean > /dev/null

# 2. Compile
DCDC_FLAG="HAS_DCDC=0" # Default off for safety, change if needed
DYN_FLAG=""
if [ "$MODE" == "dynamic" ]; then DYN_FLAG="DYNAMIC_KEYS=1"; fi

echo "🔨 Compiling..."
make -C heystack-nrf5x/nrf51822/armgcc nrf51822_xxab $DCDC_FLAG HAS_BATTERY=1 ADVERTISING_INTERVAL=$INTERVAL $DYN_FLAG > /dev/null
if [ $? -ne 0 ]; then echo "❌ Compile Failed"; exit 1; fi

# 3. Patch
echo "🔧 Patching..."
BUILD_DIR="heystack-nrf5x/nrf51822/armgcc/_build"
ORIG_BIN="$BUILD_DIR/nrf51822_xxab.bin"
PATCH_BIN="$BUILD_DIR/nrf51822_xxab_patched.bin"
PATCH_HEX="$BUILD_DIR/nrf51822_xxab_patched.hex"

arm-none-eabi-objcopy -I ihex -O binary "$BUILD_DIR/nrf51822_xxab.hex" "$ORIG_BIN"
cp "$ORIG_BIN" "$PATCH_BIN"

if [ "$MODE" == "dynamic" ]; then
    SEED_FILE="$PROJECT_ROOT/seeds/$DEVICE_NAME/seed_${DEVICE_NAME}.bin"
    if [ ! -f "$SEED_FILE" ]; then echo "❌ Seed file not found: $SEED_FILE"; exit 1; fi
    
    OFFSET=$(grep -oba "LinkyTagDynamicSeedPlaceholder!!" "$ORIG_BIN" | cut -d ':' -f 1)
    dd if="$SEED_FILE" of="$PATCH_BIN" bs=1 seek=$OFFSET count=32 conv=notrunc 2>/dev/null
else
    KEY_FILE="$PROJECT_ROOT/config/${DEVICE_NAME}_keyfile"
    if [ ! -f "$KEY_FILE" ]; then echo "❌ Key file not found: $KEY_FILE"; exit 1; fi
    
    OFFSET=$(grep -oba "OFFLINEFINDINGPUBLICKEYHERE!" "$ORIG_BIN" | cut -d ':' -f 1)
    # Patch Keyfile (Skip 1st byte count)
    xxd -p -c 100000 "$KEY_FILE" | xxd -r -p | dd of="$PATCH_BIN" skip=1 bs=1 seek=$OFFSET conv=notrunc 2>/dev/null
fi

# Convert back to hex
arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x1B000 "$PATCH_BIN" "$PATCH_HEX"

# 4. Flash
echo "⚡ Flashing..."
if [ "$DEBUGGER" == "jlink" ]; then
    nrfjprog -f nrf51 --program "$PATCH_HEX" --sectorerase --verify
    nrfjprog -f nrf51 --reset
else
    openocd -f interface/stlink.cfg -f target/nrf51.cfg -c "init; halt; nrf51 mass_erase; program $PATCH_HEX verify; reset; exit"
fi

if [ $? -eq 0 ]; then
    echo "🎉 Success!"
else
    echo "❌ Flash Failed"
    exit 1
fi
