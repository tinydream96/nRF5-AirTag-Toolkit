#!/bin/bash
# --- 自动路径配置 ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_unified_51822.txt"

# --- 全局变量 ---
# Mode: 1=Dynamic, 2=Static
MODE=""
# Debugger: 1=J-Link, 2=ST-Link
DEBUGGER=""

DEVICE_PREFIX=""
DEVICE_NUMBER=""
BASE_INTERVAL=2000
INTERVAL_STEP=10
CURRENT_INTERVAL=2000

# --- 日志记录函数 ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (Unified) - nRF51822" >> "$LOG_FILE"
        echo "日志创建时间: $timestamp" >> "$LOG_FILE"
        echo "========================================" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
    
    {
        echo "----------------------------------------"
        echo "刷写时间: $timestamp"
        echo "设备名称: $device_name"
        echo "刷写状态: $status"
        echo "执行命令: $flash_cmd"
        echo "----------------------------------------"
        echo ""
    } >> "$LOG_FILE"
}

# --- 连接检查函数 (J-Link) ---
check_jlink_connection() {
    echo
    echo "--- 步骤 2: 正在等待 J-Link 和 设备连接 (全自动) ---"
    while true; do
        IDS=$(nrfjprog -i)
        if [ -z "$IDS" ]; then
            echo "Waiting for J-Link... (未检测到调试器)"
            sleep 1
            continue
        fi

        echo "正在检查芯片连接 (J-Link ID: $IDS)..."
        if nrfjprog -f nrf51 --readregs >/dev/null 2>&1; then
            echo "✅ 芯片连接成功 (Auto Speed)!"
            break
        fi
        
        echo "⚠️  默认速度连接失败，尝试低速 (100kHz)..."
        if nrfjprog -f nrf51 --readregs --clock 100 >/dev/null 2>&1; then
            echo "✅ 芯片连接成功 (100kHz)!"
            break
        fi
        
        echo "⚠️  无法读取寄存器，尝试自动 Recover..."
        # 打印错误以便诊断
        nrfjprog -f nrf51 --readregs --clock 100
        
        if nrfjprog -f nrf51 --recover >/dev/null 2>&1; then
             echo "✅ 解锁成功。"
             break
        fi
        
        echo "❌ 连接失败。请检查: 1.芯片供电 2.SWD线序"
        echo "   (将在 2 秒后自动重试...)"
        sleep 2
    done
    echo "🔗 连接建立，准备刷写..."
    sleep 1
}

# --- 连接检查函数 (ST-Link / OpenOCD) ---
check_stlink_connection() {
    echo
    echo "--- 步骤 2: 正在等待 ST-Link 和 设备连接 (全自动) ---"
    while true; do
        OUTPUT=$(openocd -f interface/stlink.cfg -f target/nrf51.cfg -c "init; exit" 2>&1)
        if [ $? -eq 0 ]; then
             echo "✅ 检测到设备 (OpenOCD Init Success)"
             break
        fi
        
        if echo "$OUTPUT" | grep -q "Error: open failed"; then
             echo "Waiting for ST-Link... (未检测到调试器)"
        elif echo "$OUTPUT" | grep -q "unable to open fdi device"; then
            echo "Waiting for ST-Link... (未检测到调试器)"
        else
            echo "ST-Link 在线，但无法连接芯片..."
            echo "   -> 正在尝试自动解锁 (Mass Erase)..."
            openocd -f interface/stlink.cfg -f target/nrf51.cfg -c "init; nrf51 mass_erase; exit" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "✅ 解锁/擦除成功！"
                break
            else
                echo "❌ 连接失败。请检查: 1.芯片供电 2.SWD线序"
            fi
        fi
        sleep 1
    done
    echo "🔗 连接建立，准备刷写..."
    sleep 1
}

# --- 连接检查函数 (DAPLink) ---
check_daplink_connection() {
    echo
    echo "--- 步骤 2: 正在等待 DAPLink 和 设备连接 (全自动) ---"
    while true; do
        OUTPUT=$(openocd -f config/daplink.cfg -c "init; exit" 2>&1)
        if [ $? -eq 0 ]; then
             echo "✅ 检测到设备 (OpenOCD Init Success)"
             break
        fi
        
        if echo "$OUTPUT" | grep -q "Error: open failed"; then
             echo "Waiting for DAPLink... (未检测到调试器)"
        elif echo "$OUTPUT" | grep -q "unable to open cmsis-dap device"; then
             echo "Waiting for DAPLink... (未检测到调试器)"
        else
            echo "DAPLink 在线，但无法连接芯片..."
            echo "   -> 正在尝试自动解锁 (Mass Erase)..."
            openocd -f config/daplink.cfg -c "init; nrf51 mass_erase; exit" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "✅ 解锁/擦除成功！"
                break
            else
                echo "❌ 连接失败。请检查: 1.芯片供电 2.SWD线序"
            fi
        fi
        sleep 1
    done
    echo "🔗 连接建立，准备刷写..."
    sleep 1
}

# --- 主程序开始 ---
clear
echo "========================================"
echo "   nRF51822 统一刷写工具 (Unified)"
echo "========================================"
echo "请选择密钥模式:"
echo " 1. [Dynamic] 无限动态密钥 (自动生成Seed)"
echo " 2. [Static]  固定静态密钥 (需Keyfile)"
read -p "请输入选项 (默认 1): " MODE_CHOICE
if [ -z "$MODE_CHOICE" ]; then
    MODE_CHOICE="1"
    echo -e "\033[32m  -> 使用默认值: Dynamic\033[0m"
fi
MODE=$MODE_CHOICE

echo
echo "正在检测硬件..."
AUTO_DEBUGGER=""
if ioreg -p IOUSB -l | grep -qi "J-Link"; then
    AUTO_DEBUGGER="1"
    echo -e "\033[36m[AUTO] 检测到 Segger J-Link 连接\033[0m"
elif ioreg -p IOUSB -l | grep -Ei "CMSIS-DAP|DAPLink|Mbed" > /dev/null; then
    AUTO_DEBUGGER="3"
    echo -e "\033[36m[AUTO] 检测到 DAPLink (CMSIS-DAP) 连接\033[0m"
elif ioreg -p IOUSB -l | grep -Ei "ST-Link|STLINK" > /dev/null; then
    AUTO_DEBUGGER="2"
    echo -e "\033[36m[AUTO] 检测到 ST-Link 连接\033[0m"
fi

echo "请选择调试器:"
echo " 1. [J-Link]  nrfjprog (推荐)"
echo " 2. [ST-Link] OpenOCD"
echo " 3. [DAPLink] OpenOCD (CMSIS-DAP)"

DEFAULT_DEBUG_CHOICE=${AUTO_DEBUGGER:-1}
read -p "请输入选项 (默认 $DEFAULT_DEBUG_CHOICE): " DEBUG_CHOICE
DEBUG_CHOICE=${DEBUG_CHOICE:-$DEFAULT_DEBUG_CHOICE}
DEBUGGER=$DEBUG_CHOICE

echo
# 无论什么模式，都要求输入前缀，方便管理
while true; do
    read -p "请输入设备名称前缀 (如: AirTag/DYN/TCC): " DEVICE_PREFIX
    if [[ ! "$DEVICE_PREFIX" =~ ^[A-Za-z0-9_]{2,10}$ ]]; then echo "❌ 无效 (仅限字母数字下划线, 2-10位)"; continue; fi
    DEVICE_PREFIX=$(echo "$DEVICE_PREFIX" | tr '[:lower:]' '[:upper:]')
    break
done

while true; do
    read -p "请输入起始设备编号 (1-99): " DEVICE_NUMBER
    if [[ ! "$DEVICE_NUMBER" =~ ^[0-9]+$ ]]; then echo "❌ 无效"; continue; fi
    break
done

echo
echo "--- 广播间隔设置 ---"
read -p "请输入基础广播间隔 (默认 2000 ms): " INPUT_BASE_INTERVAL
if [ -z "$INPUT_BASE_INTERVAL" ]; then
    BASE_INTERVAL=2000
    echo -e "\033[32m  -> 使用默认值: 2000 ms\033[0m"
else
    BASE_INTERVAL=$INPUT_BASE_INTERVAL
fi

read -p "请输入递增步长 (默认 10 ms): " INPUT_INTERVAL_STEP
if [ -z "$INPUT_INTERVAL_STEP" ]; then
    INTERVAL_STEP=10
    echo -e "\033[32m  -> 使用默认值: 10 ms\033[0m"
else
    INTERVAL_STEP=$INPUT_INTERVAL_STEP
fi

echo
read -p "是否需要刷写 SoftDevice? (默认: Yes) [Y/n]: " FLASH_SD_CHOICE
if [ -z "$FLASH_SD_CHOICE" ]; then
    FLASH_SD_CHOICE="Y"
    echo -e "\033[32m  -> 使用默认值: Yes\033[0m"
fi

if [[ "$FLASH_SD_CHOICE" =~ ^[Yy]$ ]]; then
    SD_OPT="flash_softdevice"
    NEED_SD=true
else
    SD_OPT=""
    NEED_SD=false
fi

echo
read -p "是否启用 DCDC? (默认: No) [y/N]: " DCDC_CHOICE
if [ -z "$DCDC_CHOICE" ]; then
    DCDC_CHOICE="N"
    echo -e "\033[32m  -> 使用默认值: No\033[0m"
fi
HAS_DCDC_VAL=$([[ "$DCDC_CHOICE" =~ ^[Yy]$ ]] && echo "1" || echo "0")

# --- 主循环 ---
FIRST_RUN=true
while true; do
    
    # Calculate Interval (Fixed Formula: Base + N * Step)
    if [ "$FIRST_RUN" = true ]; then
        CURRENT_INTERVAL=$((BASE_INTERVAL + DEVICE_NUMBER * INTERVAL_STEP))
        FIRST_RUN=false
    else
        echo
        echo "--- 准备下一台设备 ---"
        DEVICE_NUMBER=$((DEVICE_NUMBER + 1))
        # Recalculate Name and Interval
        CURRENT_INTERVAL=$((BASE_INTERVAL + DEVICE_NUMBER * INTERVAL_STEP))
    fi
    
    # Ensure 3-digit padding (e.g. 1 -> 001)
    PADDED_NUM=$(printf "%03d" $DEVICE_NUMBER)
    DEVICE_NAME="${DEVICE_PREFIX}${PADDED_NUM}"
    
    echo "✅ 下一台设备: $DEVICE_NAME"

    echo
    echo -e "\033[1;33m========================================"
    echo "       本次参数预览"
    echo -e "========================================\033[0m"
    echo "  - 模式: $([ "$MODE" == "1" ] && echo "Dynamic (Seed Patch)" || echo "Static (Key Patch)")"
    echo "  - 调试器: $([ "$DEBUGGER" == "1" ] && echo "J-Link" || ([ "$DEBUGGER" == "2" ] && echo "ST-Link" || echo "DAPLink"))"
    echo "  - 设备: $DEVICE_NAME"
    echo "  - 广播间隔: $CURRENT_INTERVAL ms"
    echo -e "\033[1;33m========================================\033[0m"
    
    # Pre-flash preparations
    KEY_FILE_PATH=""
    SEED_FILE_DIR="$PROJECT_ROOT/seeds/$DEVICE_NAME"
    BUILD_DIR="heystack-nrf5x/nrf51822/armgcc/_build"
    
    # --- Dynamic Mode: Generate Seed ---
    if [ "$MODE" == "1" ]; then
        mkdir -p "$SEED_FILE_DIR"
        SEED_HEX_FILE="$SEED_FILE_DIR/seed_${DEVICE_NAME}.hex"
        SEED_BIN_FILE="$SEED_FILE_DIR/seed_${DEVICE_NAME}.bin"
        
        # Check if seed exists, ask to overwrite? No, assume new device logic or always new.
        # Generate 32 bytes (64 hex chars)
        openssl rand -hex 32 > "$SEED_HEX_FILE"
        if [ $? -ne 0 ]; then echo "❌ Seed 生成失败"; exit 1; fi
        
        # Convert hex string to binary
        xxd -r -p "$SEED_HEX_FILE" "$SEED_BIN_FILE"
        
        echo -e "\033[1;33m🔑 Generated Seed for $DEVICE_NAME: $(cat $SEED_HEX_FILE | cut -c 1-16)...\033[0m"
        echo -e "\033[1;33m📂 Seed saved to: $SEED_HEX_FILE\033[0m"
        
        # --- NEW: Generate Offline Keys from Seed ---
        echo
        read -p "是否需要生成离线 Key 文件用于追踪? (默认生成 200 个) [Y/n]: " GEN_KEYS_CHOICE
        if [ -z "$GEN_KEYS_CHOICE" ] || [[ "$GEN_KEYS_CHOICE" =~ ^[Yy]$ ]]; then
            read -p "请输入生成数量 (建议 < 2000, 默认 200): " GEN_COUNT
            GEN_COUNT=${GEN_COUNT:-200}
            
            echo -e "\033[1;33m⚙️  正在从 Seed 预计算 $GEN_COUNT 个密钥...\033[0m"
            # Get raw hex string
            SEED_HEX_STR=$(cat "$SEED_HEX_FILE")
            
            python3 "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys_from_seed.py" \
                -s "$SEED_HEX_STR" \
                -n "$GEN_COUNT" \
                -p "$DEVICE_NAME" \
                -o "$PROJECT_ROOT/config/" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo -e "\033[32m✅ 离线密钥生成成功!\033[0m"
                echo "   -> Config: config/${DEVICE_NAME}_devices.json"
            else
                echo -e "\033[31m❌ 密钥生成失败，请检查 python 环境\033[0m"
            fi
        fi
    fi
    
    # --- Static Mode: Check Keyfile ---
    if [ "$MODE" == "2" ]; then
        # Assume file naming convention TCC001_keyfile
        KEY_FILE_NAME=$(printf "${DEVICE_PREFIX}%03d_keyfile" $DEVICE_NUMBER)
        KEY_FILE_PATH="$PROJECT_ROOT/config/${KEY_FILE_NAME}"
        
        if [ ! -f "$KEY_FILE_PATH" ]; then
            echo -e "\033[31m⚠️  密钥文件不存在: $KEY_FILE_NAME\033[0m"
            # Offer Generate (g) or Skip (s) or Manual (m)
            read -p "选择操作? (g=自动生成, m=手动路径, s=跳过, 默认g): " ACTION
            ACTION=${ACTION:-g}
            
            if [[ "$ACTION" == "g" ]]; then
                echo -e "\033[1;33m⚙️  正在生成密钥 ($DEVICE_NAME)...\033[0m"
                
                # Ask for number of keys
                read -p "请输入要生成的 Key 数量 (建议不超过 200, 默认 200): " N_KEYS
                N_KEYS=${N_KEYS:-200}
                if [[ ! "$N_KEYS" =~ ^[0-9]+$ ]] || [ "$N_KEYS" -gt 200 ]; then
                    echo "⚠️  无效输入或超出上限 (200)，使用默认值 200."
                    N_KEYS=200
                fi

                TEMP_KEY_DIR="temp_keys_gen"
                # Use generate_keys.py. WARNING: It wipes output dir! Use temp dir.
                python3 "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys.py" -n "$N_KEYS" -p "$DEVICE_NAME" -o "$TEMP_KEY_DIR/" > /dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    # Move files to config/
                    GEN_KEYFILE="$TEMP_KEY_DIR/${DEVICE_NAME}_keyfile"
                    GEN_JSON="$TEMP_KEY_DIR/${DEVICE_NAME}_devices.json"
                    
                    if [ -f "$GEN_KEYFILE" ]; then
                        mv "$GEN_KEYFILE" "$PROJECT_ROOT/config/"
                        mv "$GEN_JSON" "$PROJECT_ROOT/config/" 2>/dev/null
                        # Cleanup
                        rm -rf "$TEMP_KEY_DIR"
                        echo -e "\033[32m✅ 密钥生成成功!\033[0m"
                        echo "   -> Keyfile: config/${DEVICE_NAME}_keyfile"
                        echo "   -> JSON:    config/${DEVICE_NAME}_devices.json"
                        # Reset PATH to valid one
                        KEY_FILE_PATH="$PROJECT_ROOT/config/${DEVICE_NAME}_keyfile"
                    else
                        echo "❌ 生成脚本运行成功但未找到文件."
                        rm -rf "$TEMP_KEY_DIR"
                        continue
                    fi
                else
                    echo "❌ 生成失败. 请检查 python 环境或 'cryptography' 库."
                    rm -rf "$TEMP_KEY_DIR"
                    continue
                fi
                
            elif [[ "$ACTION" == "m" ]]; then
                # User chose manual path
                while true; do
                    read -p "请手动输入密钥文件路径 (如 config/TCC001_keyfile): " ALT_PATH
                    if [ -f "$ALT_PATH" ]; then
                        KEY_FILE_PATH="$ALT_PATH"
                        echo -e "\033[32m✅ 使用自定义密钥文件: $ALT_PATH\033[0m"
                        break
                    elif [ -f "$PROJECT_ROOT/$ALT_PATH" ]; then
                         KEY_FILE_PATH="$PROJECT_ROOT/$ALT_PATH"
                         echo -e "\033[32m✅ 使用自定义密钥文件: $ALT_PATH\033[0m"
                         break
                    else
                        echo "❌ 文件不存在，请重新输入或输入 's' 跳过"
                        if [[ "$ALT_PATH" == "s" ]]; then continue 2; fi
                        if [[ "$ALT_PATH" == "q" ]]; then exit 0; fi
                    fi
                done
            else
                # Skip
                continue
            fi
        fi
        echo "📂 Using Keyfile: $(basename "$KEY_FILE_PATH")"
    fi

    # 1. Check Connection
    if [ "$DEBUGGER" == "1" ]; then
        check_jlink_connection
    elif [ "$DEBUGGER" == "2" ]; then
        check_stlink_connection
    else
        check_daplink_connection
    fi
    
    # 2. Clean
    echo "🧹 清理构建..."
    make -C heystack-nrf5x/nrf51822/armgcc clean > /dev/null
    
    # 3. Compile
    echo "🔨 编译..."
    make_args="HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 ADVERTISING_INTERVAL=$CURRENT_INTERVAL"
    
    if [ "$MODE" == "1" ]; then
        # Dynamic Mode Compilation
        make -C heystack-nrf5x/nrf51822/armgcc nrf51822_xxab $make_args DYNAMIC_KEYS=1 > /dev/null
    else
        # Static Mode Compilation
        # Note: We don't use the Makefile's patch logic anymore, we do it manually to be unified
        make -C heystack-nrf5x/nrf51822/armgcc nrf51822_xxab $make_args MAX_KEYS=200 > /dev/null
    fi
    
    if [ $? -ne 0 ]; then echo "❌ 编译失败"; exit 1; fi
    
    # 4. Patching (Common Logic)
    echo "🔧 Patching Firmware..."
    ORIG_HEX="$BUILD_DIR/nrf51822_xxab.hex"
    ORIG_BIN="$BUILD_DIR/nrf51822_xxab.bin"
    PATCH_BIN="$BUILD_DIR/nrf51822_xxab_patched.bin"
    PATCH_HEX="$BUILD_DIR/nrf51822_xxab_patched.hex"
    
    # Convert compiled hex to bin
    arm-none-eabi-objcopy -I ihex -O binary "$ORIG_HEX" "$ORIG_BIN"
    cp "$ORIG_BIN" "$PATCH_BIN"
    
    if [ "$MODE" == "1" ]; then
        # DYNAMIC PATCH: search for "LinkyTagDynamicSeedPlaceholder!!" (32 chars)
        OFFSET=$(grep -oba "LinkyTagDynamicSeedPlaceholder!!" "$ORIG_BIN" | cut -d ':' -f 1)
        if [ -z "$OFFSET" ]; then
            echo "❌ 错误: 未能在固件中找到 Seed Placeholder。请检查 main.c"
            exit 1
        fi
        echo "   -> Found Seed Placeholder at offset: $OFFSET"
        # Patch Seed (32 bytes)
        dd if="$SEED_BIN_FILE" of="$PATCH_BIN" bs=1 seek=$OFFSET count=32 conv=notrunc 2>/dev/null
        
    else
        # STATIC PATCH: search for "OFFLINEFINDINGPUBLICKEYHERE!" (28 chars)
        OFFSET=$(grep -oba "OFFLINEFINDINGPUBLICKEYHERE!" "$ORIG_BIN" | cut -d ':' -f 1)
        if [ -z "$OFFSET" ]; then
            echo "❌ 错误: 未能在固件中找到 Key Placeholder。"
            exit 1
        fi
        echo "   -> Found Key Placeholder at offset: $OFFSET"
        # Patch Keys using xxd from Keyfile
        xxd -p -c 100000 "$KEY_FILE_PATH" | xxd -r -p | dd of="$PATCH_BIN" skip=1 bs=1 seek=$OFFSET conv=notrunc 2>/dev/null
    fi

    # Convert back to Hex for nrfjprog (better sector handling)
    arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x1B000 "$PATCH_BIN" "$PATCH_HEX"

    # 5. Flash
    echo "⚡ 正在刷写..."
    
    if [ "$DEBUGGER" == "1" ]; then
        # J-Link
        if [ "$NEED_SD" = true ]; then
            echo "   -> Flashing SoftDevice..."
            nrfjprog -f nrf51 --program "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex" --sectorerase >/dev/null
        fi
        echo "   -> Flashing Application..."
        nrfjprog -f nrf51 --program "$PATCH_HEX" --sectorerase --verify
        nrfjprog -f nrf51 --reset
        
    elif [ "$DEBUGGER" == "2" ]; then
        # ST-Link
        # Construct OpenOCD commands
        CMDS="init; halt; nrf51 mass_erase;"
        if [ "$NEED_SD" = true ]; then
            echo "   -> Flashing SoftDevice..."
            SD_PATH="nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
            CMDS="$CMDS program $SD_PATH verify;"
        fi
        echo "   -> Flashing Application..."
        CMDS="$CMDS program $PATCH_HEX verify; reset; exit"
        
        openocd -f interface/stlink.cfg -f target/nrf51.cfg -c "$CMDS"
    else
        # DAPLink
        # Construct OpenOCD commands
        CMDS="init; halt; nrf51 mass_erase;"
        if [ "$NEED_SD" = true ]; then
            echo "   -> Flashing SoftDevice..."
            SD_PATH="nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
            CMDS="$CMDS program $SD_PATH verify;"
        fi
        echo "   -> Flashing Application..."
        CMDS="$CMDS program $PATCH_HEX verify; reset; exit"
        
        openocd -f config/daplink.cfg -c "$CMDS"
    fi

    echo "🎉 刷写完成!"
    log_flash_record "$DEVICE_NAME" "Flash Mode=$MODE Debugger=$DEBUGGER" "Success"
    
    echo "--------------------------------------------------------"
    # To avoid syntax errors with some chars, keep prompt extremely simple
    read -p "Press Enter to continue (or q to quit): " CONT
    if [[ "$CONT" == "q" ]]; then break; fi
done
