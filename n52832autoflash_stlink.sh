#!/bin/bash
# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录 (即项目根目录)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- 日志文件配置 ---
LOG_FILE="$PROJECT_ROOT/device_flash_log_stlink_52832.txt"

# --- 日志记录函数 (无修改) ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (ST-Link) - nRF52832" >> "$LOG_FILE"
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

# ==============================================================================
# 初始化全局变量
# ==============================================================================
DEVICE_PREFIX=""
DEVICE_NUMBER=""
FIRST_RUN=true

# ==============================================================================
# 开始无限循环，用于批量处理多个设备
# ==============================================================================
while true; do
    clear
    
    # ==============================================================================
    # 步骤 1: 用户交互，选择设备配置
    # ==============================================================================
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 请选择要刷写的设备配置 (nRF52832 ST-Link模式) ---"
        echo "    (输入 'q' 或 'quit' 可以随时退出程序)"
        
        while true; do
            read -p "请输入设备名称前缀 (如: BFX, TAG 等): " DEVICE_PREFIX
            if [[ "$DEVICE_PREFIX" == "q" || "$DEVICE_PREFIX" == "quit" ]]; then
                echo "用户选择退出程序。再见！"
                exit 0
            fi
            if ! [[ "$DEVICE_PREFIX" =~ ^[A-Za-z]{2,5}$ ]]; then
                echo "❌ 输入无效，请输入2-5个字母作为设备前缀。"
                continue
            fi
            DEVICE_PREFIX=$(echo "$DEVICE_PREFIX" | tr '[:lower:]' '[:upper:]')
            break
        done
        
        while true; do
            read -p "请输入起始设备编号 (1-99): " DEVICE_NUMBER
            if [[ "$DEVICE_NUMBER" == "q" || "$DEVICE_NUMBER" == "quit" ]]; then
                echo "用户选择退出程序。再见！"
                exit 0
            fi
            if ! [[ "$DEVICE_NUMBER" =~ ^[0-9]+$ ]]; then
                echo "❌ 输入无效，请输入一个数字。"
                continue
            fi
            if [ "$DEVICE_NUMBER" -lt 1 ] || [ "$DEVICE_NUMBER" -gt 99 ]; then
                echo "❌ 编号超出范围，请输入 1 到 99 之间的数字。"
                continue
            fi
            break
        done
        
        # --- SoftDevice 询问 ---
        read -p "是否需要刷写 SoftDevice (首次刷写空芯片必须选 y)? (y/N): " FLASH_SD_CHOICE
        if [[ "$FLASH_SD_CHOICE" == "y" || "$FLASH_SD_CHOICE" == "Y" ]]; then
            FLASH_TARGETS="flash_softdevice flash"
            echo "✅ 将刷写: SoftDevice (S132) + Application"
        else
            FLASH_TARGETS="flash"
            echo "✅ 将刷写: 仅 Application"
        fi
        
        # --- DCDC 询问 ---
        read -p "是否启用 DCDC (如果不确定，请选 n)? (y/N): " DCDC_CHOICE
        if [[ "$DCDC_CHOICE" == "y" || "$DCDC_CHOICE" == "Y" ]]; then
            HAS_DCDC_VAL="1"
            echo "✅ DCDC: 启用"
        else
            HAS_DCDC_VAL="0"
            echo "✅ DCDC: 禁用 (安全模式)"
        fi

        FIRST_RUN=false
        echo "📝 刷写记录将保存到: $LOG_FILE"
        sleep 1
    else
        echo "--- 继续批量刷写下一个设备 ---"
        DEVICE_NUMBER=$((DEVICE_NUMBER + 1))
        
        if [ "$DEVICE_NUMBER" -gt 99 ]; then
            echo "⚠️  设备编号已达到最大值 99，无法继续递增。"
            echo "如需继续，请重新运行脚本。"
            break
        fi
        
        echo "✅ 自动递增到下一个设备编号: $DEVICE_NUMBER"
        sleep 1
    fi
    
    # --- 根据用户输入生成动态配置 ---
    ADVERTISING_INTERVAL=$((2000 + DEVICE_NUMBER * 10))
    KEY_FILE_NAME=$(printf "${DEVICE_PREFIX}%03d_keyfile" $DEVICE_NUMBER)
    
    KEY_FILE_PATH="$PROJECT_ROOT/config/${KEY_FILE_NAME}"
    if [ ! -f "$KEY_FILE_PATH" ]; then
        echo "⚠️  警告: 密钥文件不存在: $KEY_FILE_PATH"
        echo "请确认该文件存在，或者检查设备前缀和编号是否正确。"
        read -p "是否要继续？(y/N): " CONTINUE_WITHOUT_FILE
        if [[ "$CONTINUE_WITHOUT_FILE" != "y" && "$CONTINUE_WITHOUT_FILE" != "Y" ]]; then
            continue
        fi
    else
        echo "✅ 找到密钥文件: $KEY_FILE_PATH"
    fi
    
    echo "--------------------------------------------------------"
    echo "✅ 本轮配置:"
    echo "   - 设备前缀: $DEVICE_PREFIX"
    echo "   - 设备编号: $DEVICE_NUMBER"
    echo "   - 完整设备名: ${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    echo "   - 广播间隔: $ADVERTISING_INTERVAL"
    echo "   - 密钥文件: $KEY_FILE_NAME"
    echo "--------------------------------------------------------"
    sleep 1
    
    DIR_TO_DELETE="$PROJECT_ROOT/heystack-nrf5x/nrf52832/armgcc/_build"

    # 使用 nrf52832 的 Makefile 路径及参数
    # 注意：这里的 FLASH_CMD 仅用于日志记录，实际执行我们会分别手动调用
    FLASH_CMD="make -C heystack-nrf5x/nrf52832/armgcc [ST-LINK] $FLASH_TARGETS HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1"
    
    # ==============================================================================
    # 后续步骤 (设备连接、清理、烧录)
    # ==============================================================================
    
    # 步骤 2: 循环检查 ST-Link 连接
    echo
    echo "--- 步骤 2: 正在循环检查 ST-Link 设备连接... ---"
    
    while true; do
        echo "正在尝试连接设备 (OpenOCD)..."
        
        # 捕获 OpenOCD 输出以进行分析
        OCD_OUTPUT=$(openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; exit" 2>&1)
        OCD_EXIT_CODE=$?
        
        # 检查是否连接成功
        if [ $OCD_EXIT_CODE -eq 0 ]; then
            # 虽然退出码为0，但如果有 examination failed，说明芯片可能被锁或者连接有问题
            if echo "$OCD_OUTPUT" | grep -q "examination failed"; then
                echo "⚠️  连接建立，但 CPU 检测失败。"
                echo "   可能原因: 芯片被读保护 (Locked) 或 接线不稳定。"
                echo "   🛑 注意: ST-Link 无法解锁被保护的 nRF52 芯片！"
                echo "   如果这是新芯片，请检查接线。如果是旧芯片，请使用 J-Link 进行 Recover。"
                
                read -p "   是否忽略警告强行尝试? (y/N): " FORCE_TRY
                if [[ "$FORCE_TRY" == "y" || "$FORCE_TRY" == "Y" ]]; then
                    echo "✅ 用户选择强行继续..."
                    break
                else
                     echo "   正在重试..."
                     sleep 2
                     continue
                fi
            else
                echo "✅ 设备/调试器连接成功。"
                break
            fi
        else
             echo "⚠️  无法连接设备。"
             echo "   可能原因: 1. 未连接 ST-Link  2. 芯片未上电或接线错误"
             echo "   正在重试..."
             sleep 2
        fi
    done
    
    # 步骤 3: 清理构建目录
    echo
    echo "--- 步骤 3: 正在清理构建目录 ---"
    if [ -d "$DIR_TO_DELETE" ]; then
        echo "发现旧的构建目录，正在删除..."
        rm -rf "$DIR_TO_DELETE"
    else
        echo "ℹ️ 构建目录不存在，无需清理。"
    fi
    
    # 步骤 4: 等待并执行烧录命令
    echo "✅ 清理完成，等待 1 秒后开始烧录..."
    sleep 1
    echo
    echo "--- 步骤 4: 正在执行烧录 (ST-Link/OpenOCD) ---"
    
    DEVICE_FULL_NAME="${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "开始刷写"
    
    EXIT_CODE=0
    
    # ----------------------------------------------------------------------
    # A. 编译固件 (Make)
    # ----------------------------------------------------------------------
    echo "🔨 正在编译固件..."
    BUILD_CMD="make -C heystack-nrf5x/nrf52832/armgcc nrf52832_xxaa HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    
    eval $BUILD_CMD
    if [ $? -ne 0 ]; then
        echo "❌ 编译失败。"
        exit 1
    fi
    
    # ----------------------------------------------------------------------
    # B. 手动执行密钥修补 (Patching)
    # ----------------------------------------------------------------------
    echo "🔑 正在注入密钥..."
    
    BUILD_DIR="$PROJECT_ROOT/heystack-nrf5x/nrf52832/armgcc/_build"
    ORIG_HEX="$BUILD_DIR/nrf52832_xxaa.hex"
    ORIG_BIN="$BUILD_DIR/nrf52832_xxaa.bin"
    PATCHED_BIN="$BUILD_DIR/nrf52832_xxaa_patched.bin"
    PATCHED_HEX="$BUILD_DIR/nrf52832_xxaa_patched.hex"
    
    # B.1 转换 HEX -> BIN
    arm-none-eabi-objcopy -I ihex -O binary "$ORIG_HEX" "$ORIG_BIN"
    
    # B.2 复制
    cp "$ORIG_BIN" "$PATCHED_BIN"
    
    # B.3 查找偏移
    KEY_OFFSET=$(grep -oba "OFFLINEFINDINGPUBLICKEYHERE!" "$ORIG_BIN" | cut -d ':' -f 1)
    
    if [ -z "$KEY_OFFSET" ]; then
        echo "❌ 错误: 在固件中找不到密钥占位符！"
        EXIT_CODE=1
    else
        # B.4 注入密钥
        xxd -p -c 100000 "$KEY_FILE_PATH" | xxd -r -p | dd of="$PATCHED_BIN" skip=1 bs=1 seek=$KEY_OFFSET conv=notrunc 2>/dev/null
        
        # B.5 转回 HEX (S132 App base: 0x26000)
        arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x26000 "$PATCHED_BIN" "$PATCHED_HEX"
        echo "✅ 密钥已注入到: $PATCHED_HEX"
    fi

    # ----------------------------------------------------------------------
    # C. 执行 OpenOCD 烧录
    # ----------------------------------------------------------------------
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🔥 正在通过 OpenOCD 刷写..."
        
        SD_HEX="$PROJECT_ROOT/nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s132/hex/s132_nrf52_6.1.1_softdevice.hex"
        APP_HEX="$PATCHED_HEX"
        
        OPENOCD_CMDS=""
        
        # 1. 解锁 (可选): 如果芯片被锁，尝试 recover
        # OpenOCD 的 nrf52 mass_erase 命令可以解锁，或者使用 nrf52 recover (如果版本支持)
        # 我们先尝试普通的 program，如果失败再提示
        
        OPENOCD_CMDS+="init; reset halt;"
        
        if [[ "$FLASH_TARGETS" == *"flash_softdevice"* ]]; then
            # 如果刷 SoftDevice，通常意味着全片擦除比较好
            echo "   (包含 SoftDevice - 执行全片擦除)"
            OPENOCD_CMDS+="nrf5 mass_erase;" 
            OPENOCD_CMDS+="program $SD_HEX verify;"
        else
            # 仅刷 App，执行扇区擦除即可？或者 program 自动擦除
            # 注意: nRF52 只能按 Page 擦除。OpenOCD program 命令默认会擦除需要的扇区
            :
        fi
        
        OPENOCD_CMDS+="program $APP_HEX verify reset exit;"
        
        openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "$OPENOCD_CMDS"
        EXIT_CODE=$?
    fi
    
    echo "--------------------------------------------------------"
    
    # 步骤 5: 报告本轮结果
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} (nRF52832) 操作成功完成！🎉🎉🎉"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "✅ 刷写成功"
        echo "📝 成功记录已保存到日志文件"
    else
        echo "❌ 错误: 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} 烧录过程中发生错误 (退出码: $EXIT_CODE)。"
        echo "   (如果是 'Locked' 错误，请尝试断电重连，或手动运行一次全片擦除: openocd ... -c 'nrf5 mass_erase' )"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "❌ 刷写失败"
        EXIT_CODE=1 # Ensure loop knows failure
    fi
    
    # 步骤 6: 询问是否继续
    echo
    echo "🚀 准备刷写下一个设备..."
    echo "   下一个设备将是: ${DEVICE_PREFIX}$(printf "%03d" $((DEVICE_NUMBER + 1)))"
    read -p "按 Enter 继续，或输入 'q' 退出: " CONTINUE_CHOICE
    
    if [[ "$CONTINUE_CHOICE" == "q" || "$CONTINUE_CHOICE" == "Q" || "$CONTINUE_CHOICE" == "quit" ]]; then
        break
    fi
    
    if [ $((DEVICE_NUMBER + 1)) -gt 99 ]; then
        break
    fi
done

echo
echo "所有批量任务已完成。程序退出。"
exit 0
