#!/bin/bash

# ==========================================
# nRF51822 Advanced Key Generator (CLI)
# ==========================================
# Usage: 
#   ./advanced_keygen.sh -m static -p PREFIX -n COUNT
#   ./advanced_keygen.sh -m dynamic -p PREFIX [-c COUNT]
# ==========================================

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PYTHON="python3"

# Defaults
MODE="dynamic"
PREFIX=""
COUNT=1

usage() {
    echo "Usage: $0 -m <static|dynamic> -p <DEVICE_PREFIX> [-n <KEY_COUNT>]"
    echo "  -m : Mode 'static' or 'dynamic'"
    echo "  -p : Device Name Prefix (e.g. MSF001)"
    echo "  -n : Number of keys to generate (Default: 1 for Static, 200 for Dynamic offline)"
    exit 1
}

while getopts "m:p:n:" opt; do
    case ${opt} in
        m) MODE=$OPTARG ;;
        p) PREFIX=$OPTARG ;;
        n) COUNT=$OPTARG ;;
        *) usage ;;
    esac
done

if [ -z "$PREFIX" ]; then usage; fi

# Output Dirs
CONFIG_DIR="$PROJECT_ROOT/config"
SEED_DIR="$PROJECT_ROOT/seeds/$PREFIX"
mkdir -p "$CONFIG_DIR"

if [ "$MODE" == "static" ]; then
    echo "🔵 [Static Mode] Generating $COUNT keys for $PREFIX..."
    TEMP_DIR="temp_keygen_static"
    mkdir -p "$TEMP_DIR"
    
    $PYTHON "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys.py" -n "$COUNT" -p "$PREFIX" -o "$TEMP_DIR/" > /dev/null
    
    if [ $? -eq 0 ]; then
        mv "$TEMP_DIR/${PREFIX}_keyfile" "$CONFIG_DIR/"
        mv "$TEMP_DIR/${PREFIX}_devices.json" "$CONFIG_DIR/" 2>/dev/null
        rm -rf "$TEMP_DIR"
        echo "✅ Created: $CONFIG_DIR/${PREFIX}_keyfile"
    else
        echo "❌ Error in python script generation"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

elif [ "$MODE" == "dynamic" ]; then
    echo "🟣 [Dynamic Mode] Generating Seed for $PREFIX..."
    mkdir -p "$SEED_DIR"
    SEED_HEX_FILE="$SEED_DIR/seed_${PREFIX}.hex"
    SEED_BIN_FILE="$SEED_DIR/seed_${PREFIX}.bin"
    
    # 1. Generate Seed
    openssl rand -hex 32 > "$SEED_HEX_FILE"
    xxd -r -p "$SEED_HEX_FILE" "$SEED_BIN_FILE"
    echo "✅ Seed Created: $SEED_HEX_FILE"
    
    # 2. Offline Calc (Default 200 if not specified greater)
    CALC_COUNT=${COUNT:-200}
    if [ "$CALC_COUNT" -eq 1 ]; then CALC_COUNT=200; fi
    
    echo "🟣 Pre-calculating $CALC_COUNT offline keys for tracking..."
    SEED_STR=$(cat "$SEED_HEX_FILE")
    $PYTHON "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys_from_seed.py" \
        -s "$SEED_STR" -n "$CALC_COUNT" -p "$PREFIX" -o "$CONFIG_DIR/" > /dev/null
        
    if [ $? -eq 0 ]; then
        echo "✅ Offline Keys: $CONFIG_DIR/${PREFIX}_devices.json"
    else
        echo "❌ Error in offline key calculation"
        exit 1
    fi

else
    usage
fi
