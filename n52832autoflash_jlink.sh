#!/bin/bash
# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录 (即项目根目录)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- 日志文件配置 ---
LOG_FILE="$PROJECT_ROOT/device_flash_log_jlink_52832.txt"

# --- 日志记录函数 (无修改) ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (J-Link) - nRF52832" >> "$LOG_FILE"
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
        echo "--- 步骤 1: 请选择要刷写的设备配置 (nRF52832 J-Link模式) ---"
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
    
    # --- 命令和目录配置 ---
    # nRF52832 device ID for JLink - 使用 nrfjprog 替代 JLinkExe 进行检查
    # 这能确保环境一致性，并且 nrfjprog 的输出更易于解析
    # JLINK_CHECK_CMD='nrfjprog -f nrf52 --verify' # verify 需要连接芯片，适合用来检测连接状态
    
    DIR_TO_DELETE="$PROJECT_ROOT/heystack-nrf5x/nrf52832/armgcc/_build"

    # 使用 nrf52832 的 Makefile 路径及参数
    FLASH_CMD="make -C heystack-nrf5x/nrf52832/armgcc $FLASH_TARGETS HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    
    # ==============================================================================
    # 后续步骤 (设备连接、清理、烧录)
    # ==============================================================================
    
    # 步骤 2: 循环检查 J-Link 连接
    echo
    echo "--- 步骤 2: 正在循环检查 J-Link 设备连接... ---"
    
    while true; do
        echo "正在尝试连接设备 (nRF52832)..."
        
        # 1. 首先检查是否有 J-Link 调试器在线
        IDS=$(nrfjprog -i)
        if [ -z "$IDS" ]; then
            echo "❌ 未检测到 J-Link 调试器连接到电脑。"
            echo "   请检查 USB 连接。"
            sleep 1
            continue
        fi

        # 2. 尝试连接芯片 (使用 readregs 检测是否能读寄存器，这比 verify 更快且不需擦除)
        # 如果芯片锁住了，这一步可能会失败，但至少说明 debugger 在线
        nrfjprog -f nrf52 --readregs > /dev/null 2>&1
        EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then 
             # 如果 readregs 失败，可能是锁住了，也可能是没电。
             # 尝试 recover 预检测 (不真正执行 recover，只是看报错)
             # 但这里我们主要目的是检测物理连接。
             
             echo "⚠️  检测到 J-Link ($IDS)，但无法读取芯片寄存器。"
             echo "   可能原因: 1. 芯片未上电 (VTref=0V)  2. 接线错误  3. 芯片已锁 (稍后会自动尝试 recover)"
             
             # 只要 J-Link 在，我们就假设可能连接上了，跳出循环尝试 recover
             # 为了避免死循环，这里给用户一个确认或者自动重试
             # 这里我们选择：如果连续失败，提示用户。
             
             echo "   >>> 请务必确保: 芯片已外接电源 (电池或VCC供电) <<<"
             read -t 2 -p "   按任意键立即开始尝试强行 Recover，或等待重试..." || true
             # 稍微放宽一点，直接去尝试 recover，因为 recover 本身就是用来解决连接问题的
             break
        else
            echo "✅ 设备连接成功 (ID: $IDS)，寄存器可读取。"
            break
        fi
    done
    
    # 步骤 3: 清理构建目录
    echo
    echo "--- 步骤 3: 正在清理构建目录 ---"
    if [ -d "$DIR_TO_DELETE" ]; then
        echo "发现旧的构建目录，正在删除..."
        rm -rf "$DIR_TO_DELETE"
        if [ -d "$DIR_TO_DELETE" ]; then
            echo "❌ 错误: 删除目录 $DIR_TO_DELETE 失败！请检查文件权限。"
            exit 1
        else
            echo "✅ 目录已成功删除。"
        fi
    else
        echo "ℹ️ 构建目录不存在，无需清理。"
    fi
    
    # 步骤 4: 等待并执行烧录命令
    echo "✅ 清理完成，等待 2 秒后开始烧录..."
    sleep 2
    echo
    echo "--- 步骤 4: 正在执行烧录 (J-Link) ---"
    echo "--------------------------------------------------------"
    echo "执行: $FLASH_CMD"
    
    DEVICE_FULL_NAME="${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "开始刷写"
    
    PROCEED_TO_FLASH=true

    # <<< NEW: 如果需要刷写 SoftDevice，先执行 recover 解锁/擦除全片
    if [[ "$FLASH_TARGETS" == *"flash_softdevice"* ]]; then
        echo "🧹 正在尝试 nrfjprog Recover..."
        nrfjprog -f nrf52 --recover > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "⚠️  nrfjprog Recover 失败，尝试使用 J-Link 寄存器直接解锁 (Manual Unlock)..."
            
            # 生成手动解锁脚本
            UNLOCK_SCRIPT="unlock_script.jlink"
            echo "si SWD" > $UNLOCK_SCRIPT
            echo "speed 1000" >> $UNLOCK_SCRIPT
            echo "device nRF52832_xxAA" >> $UNLOCK_SCRIPT
            echo "connect" >> $UNLOCK_SCRIPT
            # NVMC.CONFIG = 0x02 (Erase)
            echo "w4 4001e504 2" >> $UNLOCK_SCRIPT
            # NVMC.ERASEALL = 0x01 (Start Erase)
            echo "w4 4001e50c 1" >> $UNLOCK_SCRIPT
            echo "sleep 500" >> $UNLOCK_SCRIPT
            # NVMC.CONFIG = 0x00 (Read Only)
            echo "w4 4001e504 0" >> $UNLOCK_SCRIPT
            echo "r" >> $UNLOCK_SCRIPT
            echo "exit" >> $UNLOCK_SCRIPT
            
            JLinkExe -CommandFile $UNLOCK_SCRIPT > /dev/null 2>&1
            rm $UNLOCK_SCRIPT
            
            echo "✅ Manual Unlock 执行完毕，继续尝试刷写..."
        else
            echo "✅ nrfjprog Recover 成功。"
        fi
        sleep 1
    fi
    
    # 无条件尝试刷写，因为 Manual Unlock 的结果很难通过 exit code 判断
    # 如果真的失败，后面的刷写步骤自然会报错
    if [ "$PROCEED_TO_FLASH" = true ]; then
        # 1. 先执行编译 (只编译，不刷写)
        echo "🔨 正在编译固件..."
        # 移除 'flash' 和 'flash_softdevice' 目标，只保留默认目标构建
        BUILD_CMD="make -C heystack-nrf5x/nrf52832/armgcc nrf52832_xxaa HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
        
        eval $BUILD_CMD
        BUILD_STATUS=$?
        
        if [ $BUILD_STATUS -ne 0 ]; then
            echo "❌ 编译失败。"
            exit 1
        fi
        
        # 2. 手动执行密钥修补 (Patching)
        echo "🔑 正在注入密钥..."
        
        BUILD_DIR="$PROJECT_ROOT/heystack-nrf5x/nrf52832/armgcc/_build"
        ORIG_HEX="$BUILD_DIR/nrf52832_xxaa.hex"
        ORIG_BIN="$BUILD_DIR/nrf52832_xxaa.bin"
        PATCHED_BIN="$BUILD_DIR/nrf52832_xxaa_patched.bin"
        PATCHED_HEX="$BUILD_DIR/nrf52832_xxaa_patched.hex"
        
        # 2.1 转换 HEX -> BIN
        arm-none-eabi-objcopy -I ihex -O binary "$ORIG_HEX" "$ORIG_BIN"
        
        # 2.2 复制一份作为修补目标
        cp "$ORIG_BIN" "$PATCHED_BIN"
        
        # 2.3 查找密钥占位符偏移量
        KEY_OFFSET=$(grep -oba "OFFLINEFINDINGPUBLICKEYHERE!" "$ORIG_BIN" | cut -d ':' -f 1)
        
        if [ -z "$KEY_OFFSET" ]; then
            echo "❌ 错误: 在固件中找不到密钥占位符！"
            exit 1
        fi
        
        # 2.4 注入密钥 (跳过密钥文件的第一个字节，因为它通常是长度还是什么？参考 Makefile: skip=1)
        # Makefile: xxd -p ... | dd ... skip=1 ... seek=$OFFSET
        xxd -p -c 100000 "$KEY_FILE_PATH" | xxd -r -p | dd of="$PATCHED_BIN" skip=1 bs=1 seek=$KEY_OFFSET conv=notrunc 2>/dev/null
        
        # 2.5 转换回 HEX (注意: S132 v6.1.1 的应用程序起始地址通常是 0x26000)
        # 为策万全，我们读取原 HEX 的第一行来猜测？不，硬编码 0x26000 对于 S132 6.x 是标准的
        arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x26000 "$PATCHED_BIN" "$PATCHED_HEX"
        
        echo "✅ 密钥已注入到: $PATCHED_HEX"
        
        # 3. 生成 J-Link 刷写脚本
        JLINK_SCRIPT="flash_script.jlink"
        echo "📝 生成 J-Link 刷写脚本..."
        
        # 绝对路径配置
        SD_HEX="$PROJECT_ROOT/nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s132/hex/s132_nrf52_6.1.1_softdevice.hex"
        APP_HEX="$PATCHED_HEX"  # 使用修补后的 HEX
        
        # 开始构建脚本内容
        echo "device nRF52832_xxAA" > $JLINK_SCRIPT
        echo "si SWD" >> $JLINK_SCRIPT
        echo "speed 1000" >> $JLINK_SCRIPT
        echo "connect" >> $JLINK_SCRIPT
        
        # 如果需要刷 SoftDevice
        if [[ "$FLASH_TARGETS" == *"flash_softdevice"* ]]; then
             echo "loadfile $SD_HEX" >> $JLINK_SCRIPT
        fi
        
        echo "loadfile $APP_HEX" >> $JLINK_SCRIPT
        echo "r" >> $JLINK_SCRIPT
        echo "g" >> $JLINK_SCRIPT
        echo "exit" >> $JLINK_SCRIPT
        
        # 3. 执行刷写
        echo "🔥 正在通过 JLinkExe 直接刷写 (绕过 nrfjprog)..."
        
        # 捕获输出以便检查错误
        JLINK_OUTPUT=$(JLinkExe -CommandFile $JLINK_SCRIPT 2>&1)
        echo "$JLINK_OUTPUT"
        
        # JLinkExe 即使执行失败通常也返回 0，所以必须检查输出中的关键字
        if echo "$JLINK_OUTPUT" | grep -iq "Error occurred\|Cannot connect\|Failed to connect\|Target connection not established"; then
            echo "❌ J-Link 执行过程中检测到错误！"
            EXIT_CODE=1
        else
            EXIT_CODE=0
        fi
        
        rm $JLINK_SCRIPT
    else
        EXIT_CODE=1
    fi
    echo "--------------------------------------------------------"
    
    # 步骤 5: 报告本轮结果并记录日志
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} (nRF52832) 操作成功完成！🎉🎉🎉"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "✅ 刷写成功"
        echo "📝 成功记录已保存到日志文件"
    else
        echo "❌ 错误: 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} 烧录过程中发生错误 (退出码: $EXIT_CODE)。"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "❌ 刷写失败 (退出码: $EXIT_CODE)"
        echo "请检查错误日志，解决问题后重新运行脚本。"
        exit 1
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
        echo "⚠️  下一个设备编号将超出范围(>99)，批量刷写即将结束。"
        read -p "按 Enter 继续最后一次刷写，或输入任意字符退出: " FINAL_CHOICE
        if [[ -n "$FINAL_CHOICE" ]]; then
            break
        fi
    fi
done

echo
echo "📊 批量刷写统计："
if [ -f "$LOG_FILE" ]; then
    TOTAL_COUNT=$(grep -c "刷写状态:" "$LOG_FILE")
    SUCCESS_COUNT=$(grep -c "✅ 刷写成功" "$LOG_FILE")
    FAILED_COUNT=$(grep -c "❌ 刷写失败" "$LOG_FILE")
    
    echo "   - 总计刷写: $TOTAL_COUNT 次"
    echo "   - 成功刷写: $SUCCESS_COUNT 次"
    echo "   - 失败刷写: $FAILED_COUNT 次"
    echo "   - 详细记录: $LOG_FILE"
else
    echo "   - 未找到刷写记录"
fi

echo "所有批量任务已完成。程序退出。"
exit 0
