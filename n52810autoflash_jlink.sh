#!/bin/bash
# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录 (即项目根目录)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- 日志文件配置 ---
LOG_FILE="$PROJECT_ROOT/device_flash_log_jlink.txt" # <<< MODIFIED: 使用新的日志文件名

# --- 日志记录函数 (无修改) ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (J-Link)" >> "$LOG_FILE"
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
    # 步骤 1: 用户交互，选择设备配置 (无逻辑修改)
    # ==============================================================================
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 请选择要刷写的设备配置 (J-Link模式) ---"
        echo "    (输入 'q' 或 'quit' 可以随时退出程序)"
        
        while true; do
            read -p "请输入设备名称前缀 (如: EPD, MED, GPS 等): " DEVICE_PREFIX
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
    # <<< MODIFIED: 替换 OpenOCD 相关命令为 J-Link 命令
    # JLinkExe 会自动找到连接的 J-Link 调试器。
    # -device: 目标芯片型号
    # -if: 调试接口 (SWD)
    # -speed: 接口速度
    # -autoconnect: 自动连接
    # -NoGui: 强制在命令行模式下运行
    # -exit: 执行完毕后自动退出
    # <<< FIXED: 使用管道传递 exit 命令退出，因为新版 JLinkExe 不支持 -exit 参数
    JLINK_CHECK_CMD='echo "exit" | JLinkExe -device nRF52810_xxAA -if SWD -speed 4000 -autoconnect 1 -NoGui 1'
    
    DIR_TO_DELETE="$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/_build"

    # <<< MODIFIED: 修改 Makefile 目标为 J-Link 的刷写目标
    # 
    # !!! 关键修改点 !!!
    # 将 "stflash-nrf52810_xxaa-patched" 修改为适用于 J-Link 的目标。
    # 这个目标通常是 "flash" 或 "flash_jlink"。
    # 请打开 heystack-nrf5x/nrf52810/armgcc/Makefile 文件，确认正确的刷写目标名称。
    #
    # <<< MODIFIED: 增加是否刷写 SoftDevice 的询问
    if [ "$FIRST_RUN" = true ]; then
        read -p "是否需要刷写 SoftDevice (首次刷写空芯片必须选 y)? (y/N): " FLASH_SD_CHOICE
        if [[ "$FLASH_SD_CHOICE" == "y" || "$FLASH_SD_CHOICE" == "Y" ]]; then
            FLASH_TARGETS="flash_softdevice flash"
            echo "✅ 将刷写: SoftDevice + Application"
        else
            FLASH_TARGETS="flash"
            echo "✅ 将刷写: 仅 Application"
        fi
        
        # 增加是否启用 DCDC 的询问 (很多简易开发板不带 DCDC 电感，必须禁用)
        read -p "是否启用 DCDC (如果不确定，请选 n)? (y/N): " DCDC_CHOICE
        if [[ "$DCDC_CHOICE" == "y" || "$DCDC_CHOICE" == "Y" ]]; then
            HAS_DCDC_VAL="1"
            echo "✅ DCDC: 启用"
        else
            HAS_DCDC_VAL="0"
            echo "✅ DCDC: 禁用 (安全模式)"
        fi
        FIRST_RUN=false
    fi

    # ... (Keep existing logic)

    FLASH_CMD="make -C heystack-nrf5x/nrf52810/armgcc $FLASH_TARGETS HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    # >>> MODIFIED END
    
    # ==============================================================================
    # 后续步骤 (设备连接、清理、烧录)
    # ==============================================================================
    
   #
    # 步骤 2: 循环检查 J-Link 连接
    #
    echo
    echo "--- 步骤 2: 正在循环检查 J-Link 设备连接... ---"
    
    while true; do
        echo "正在尝试连接设备..."
        # 执行 J-Link 命令并捕获其输出和退出码
        OUTPUT=$(eval $JLINK_CHECK_CMD 2>&1)
        EXIT_CODE=$? # <<< NEW: 捕获上一条命令的退出码

        # <<< MODIFIED: 更严格的检查逻辑
        # 1. 检查退出码是否不为 0 (最可靠的失败标志)
        # 2. 或者，检查输出中是否包含已知的错误关键字
        if [ $EXIT_CODE -ne 0 ] || echo "$OUTPUT" | grep -iq "ERROR\|Cannot connect\|Failed to connect\|Could not find core"; then
            echo "❌ 连接失败 (退出码: $EXIT_CODE)。"
            
            # 尝试从输出中提取错误信息行
            ERROR_LINE=$(echo "$OUTPUT" | grep -i "ERROR\|Cannot\|Failed\|Could not find")
            if [ -n "$ERROR_LINE" ]; then
                 echo "   错误信息: $ERROR_LINE"
            fi

            echo "   请确保 J-Link 已连接并且目标设备已上电。将在 2 秒后重试..."
            sleep 2
        else
            echo "✅ 设备连接成功，无错误。"
            break
        fi
    done
    # >>> MODIFIED END
    
    #
    # 步骤 3: 清理构建目录 (无修改)
    #
    echo
    echo "--- 步骤 3: 正在清理构建目录 ---"
    echo "目标目录: $DIR_TO_DELETE"
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
    
    #
    # 步骤 4: 等待并执行烧录命令 (无逻辑修改)
    #
    echo "✅ 清理完成，等待 2 秒后开始烧录..."
    sleep 2
    echo
    echo "--- 步骤 4: 正在执行烧录 (J-Link) ---"
    echo "--------------------------------------------------------"
    echo "执行: $FLASH_CMD"
    
    DEVICE_FULL_NAME="${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "开始刷写"
    
    eval $FLASH_CMD
    EXIT_CODE=$?
    echo "--------------------------------------------------------"
    
    #
    # 步骤 5: 报告本轮结果并记录日志 (无逻辑修改)
    #
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} 操作成功完成！🎉🎉🎉"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "✅ 刷写成功"
        echo "📝 成功记录已保存到日志文件"
    else
        echo "❌ 错误: 设备 ${DEVICE_PREFIX}${DEVICE_NUMBER} 烧录过程中发生错误 (退出码: $EXIT_CODE)。"
        log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "❌ 刷写失败 (退出码: $EXIT_CODE)"
        echo "📝 错误记录已保存到日志文件"
        echo "请检查错误日志，解决问题后重新运行脚本。"
        exit 1
    fi
    
    #
    # 步骤 6: 询问是否继续 (无逻辑修改)
    #
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