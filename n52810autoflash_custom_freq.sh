#!/bin/bash
# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录 (即项目根目录)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- 日志文件配置 ---
LOG_FILE="$PROJECT_ROOT/device_flash_log.txt"

# --- 日志记录函数 ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 如果日志文件不存在，创建并添加头部信息
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志" >> "$LOG_FILE"
        echo "日志创建时间: $timestamp" >> "$LOG_FILE"
        echo "========================================" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
    
    # 记录刷写信息
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
FREQUENCY_OFFSET=""  # 新增：频率偏移量变量
FIRST_RUN=true

# ==============================================================================
# 开始无限循环，用于批量处理多个设备
# ==============================================================================
while true; do
    # 清理屏幕，为新一轮操作提供干净的界面
    clear
    
    # ==============================================================================
    # 步骤 1: 用户交互，选择设备配置
    # ==============================================================================
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 请选择要刷写的设备配置 ---"
        echo "    (输入 'q' 或 'quit' 可以随时退出程序)"
        
        # 获取设备名称前缀 (仅首次运行)
        while true; do
            read -p "请输入设备名称前缀 (如: EPD, MED, GPS 等): " DEVICE_PREFIX
            
            # 检查是否输入退出指令
            if [[ "$DEVICE_PREFIX" == "q" || "$DEVICE_PREFIX" == "quit" ]]; then
                echo "用户选择退出程序。再见！"
                exit 0
            fi
            
            # 检查输入是否为有效的字母前缀 (2-5个字符)
            if ! [[ "$DEVICE_PREFIX" =~ ^[A-Za-z]{2,5}$ ]]; then
                echo "❌ 输入无效，请输入2-5个字母作为设备前缀。"
                continue
            fi
            
            # 转换为大写
            DEVICE_PREFIX=$(echo "$DEVICE_PREFIX" | tr '[:lower:]' '[:upper:]')
            break
        done
        
        # 获取起始设备编号 (仅首次运行)
        while true; do
            read -p "请输入起始设备编号 (1-99): " DEVICE_NUMBER
            
            # 检查是否输入退出指令
            if [[ "$DEVICE_NUMBER" == "q" || "$DEVICE_NUMBER" == "quit" ]]; then
                echo "用户选择退出程序。再见！"
                exit 0
            fi
            
            # 检查输入是否为纯数字
            if ! [[ "$DEVICE_NUMBER" =~ ^[0-9]+$ ]]; then
                echo "❌ 输入无效，请输入一个数字。"
                continue
            fi
            
            # 检查数字是否在 1-99 范围内
            if [ "$DEVICE_NUMBER" -lt 1 ] || [ "$DEVICE_NUMBER" -gt 99 ]; then
                echo "❌ 编号超出范围，请输入 1 到 99 之间的数字。"
                continue
            fi
            
            # 输入有效，跳出循环
            break
        done
        
        # 新增：获取频率偏移量 (仅首次运行)
        echo ""
        echo "--- 频率配置说明 ---"
        echo "默认频率计算公式: 2000 + 设备编号 * 10"
        echo "例如设备编号为 10，默认频率为: 2000 + 10 * 10 = 2100"
        echo "您可以设置一个偏移量来调整基础频率。"
        echo "示例：偏移量 1000，则频率变为: 3000 + 设备编号 * 10"
        echo ""
        
        while true; do
            read -p "请输入频率偏移量 (0-5000，默认0，直接按回车使用默认): " FREQUENCY_OFFSET
            
            # 检查是否输入退出指令
            if [[ "$FREQUENCY_OFFSET" == "q" || "$FREQUENCY_OFFSET" == "quit" ]]; then
                echo "用户选择退出程序。再见！"
                exit 0
            fi
            
            # 如果用户直接按回车，使用默认值0
            if [[ -z "$FREQUENCY_OFFSET" ]]; then
                FREQUENCY_OFFSET=0
                echo "✅ 使用默认频率偏移量: 0"
                break
            fi
            
            # 检查输入是否为纯数字
            if ! [[ "$FREQUENCY_OFFSET" =~ ^[0-9]+$ ]]; then
                echo "❌ 输入无效，请输入一个数字（0-5000）。"
                continue
            fi
            
            # 检查数字是否在合理范围内
            if [ "$FREQUENCY_OFFSET" -lt 0 ] || [ "$FREQUENCY_OFFSET" -gt 5000 ]; then
                echo "❌ 偏移量超出范围，请输入 0 到 5000 之间的数字。"
                continue
            fi
            
            echo "✅ 频率偏移量设置为: $FREQUENCY_OFFSET"
            break
        done
        
        FIRST_RUN=false
        
        # 显示日志文件位置
        echo "📝 刷写记录将保存到: $LOG_FILE"
        sleep 1
    else
        # 非首次运行，自动递增设备编号
        echo "--- 继续批量刷写下一个设备 ---"
        DEVICE_NUMBER=$((DEVICE_NUMBER + 1))
        
        # 检查编号是否超出范围
        if [ "$DEVICE_NUMBER" -gt 99 ]; then
            echo "⚠️  设备编号已达到最大值 99，无法继续递增。"
            echo "如需继续，请重新运行脚本。"
            break
        fi
        
        echo "✅ 自动递增到下一个设备编号: $DEVICE_NUMBER"
        sleep 1
    fi
    
    # --- 根据用户输入生成动态配置 (使用自定义频率偏移量) ---
    ADVERTISING_INTERVAL=$(((2000 + FREQUENCY_OFFSET) + DEVICE_NUMBER * 10))
    KEY_FILE_NAME=$(printf "${DEVICE_PREFIX}%03d_keyfile" $DEVICE_NUMBER)
    
    # 检查密钥文件是否存在
    KEY_FILE_PATH="$PROJECT_ROOT/config/${KEY_FILE_NAME}"
    if [ ! -f "$KEY_FILE_PATH" ]; then
        echo "⚠️  警告: 密钥文件不存在: $KEY_FILE_PATH"
        echo "请确认该文件存在，或者检查设备前缀和编号是否正确。"
        read -p "是否要继续？(y/N): " CONTINUE_WITHOUT_FILE
        if [[ "$CONTINUE_WITHOUT_FILE" != "y" && "$CONTINUE_WITHOUT_FILE" != "Y" ]]; then
            continue  # 返回重新输入
        fi
    else
        echo "✅ 找到密钥文件: $KEY_FILE_PATH"
    fi
    
    echo "--------------------------------------------------------"
    echo "✅ 本轮配置:"
    echo "   - 设备前缀: $DEVICE_PREFIX"
    echo "   - 设备编号: $DEVICE_NUMBER"
    echo "   - 完整设备名: ${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    echo "   - 频率偏移量: $FREQUENCY_OFFSET"
    echo "   - 广播间隔: $ADVERTISING_INTERVAL (计算: (2000+$FREQUENCY_OFFSET) + $DEVICE_NUMBER*10)"
    echo "   - 密钥文件: $KEY_FILE_NAME"
    echo "--------------------------------------------------------"
    sleep 1
    
    # --- 命令和目录配置 ---
    OPNOCD_CHECK_DIR="$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc"
    OPNOCD_CMD='openocd -f openocd.cfg -c "init; exit"'
    DIR_TO_DELETE="$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/_build"
    FLASH_CMD="make -C heystack-nrf5x/nrf52810/armgcc stflash-nrf52810_xxaa-patched HAS_DCDC=1 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    
    # ==============================================================================
    # 后续步骤 (设备连接、清理、烧录)
    # ==============================================================================
    
    #
    # 步骤 2: 循环检查 OpenOCD 连接
    #
    echo
    echo "--- 步骤 2: 正在循环检查设备连接... ---"
    cd "$OPNOCD_CHECK_DIR" || exit 1 # 如果目录切换失败，则严重错误退出
    
    while true; do
        echo "正在尝试连接设备..."
        OUTPUT=$(eval $OPNOCD_CMD 2>&1)
        if echo "$OUTPUT" | grep -iq "Error"; then
            ERROR_LINE=$(echo "$OUTPUT" | grep -i "Error")
            echo "检测到错误: $ERROR_LINE"
            echo "将在 2 秒后重试..."
            sleep 2
        else
            echo "✅ 设备连接成功，无错误。"
            break
        fi
    done
    
    # 切换回项目根目录
    echo
    echo "切换回项目根目录: $PROJECT_ROOT"
    cd "$PROJECT_ROOT" || exit 1
    
    #
    # 步骤 3: 清理构建目录
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
    # 步骤 4: 等待并执行烧录命令
    #
    echo "✅ 清理完成，等待 2 秒后开始烧录..."
    sleep 2
    echo
    echo "--- 步骤 4: 正在执行烧录 (stflash) ---"
    echo "--------------------------------------------------------"
    echo "执行: $FLASH_CMD"
    
    # 记录开始刷写
    DEVICE_FULL_NAME="${DEVICE_PREFIX}$(printf "%03d" $DEVICE_NUMBER)"
    log_flash_record "$DEVICE_FULL_NAME" "$FLASH_CMD" "开始刷写"
    
    eval $FLASH_CMD
    EXIT_CODE=$?
    echo "--------------------------------------------------------"
    
    #
    # 步骤 5: 报告本轮结果并记录日志
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
        exit 1 # 发生错误则终止整个脚本
    fi
    
    #
    # 步骤 6: 询问是否继续 (简化为自动继续)
    #
    echo
    echo "🚀 准备刷写下一个设备..."
    NEXT_DEVICE_NUM=$((DEVICE_NUMBER + 1))
    NEXT_ADVERTISING_INTERVAL=$(((2000 + FREQUENCY_OFFSET) + NEXT_DEVICE_NUM * 10))
    echo "   下一个设备将是: ${DEVICE_PREFIX}$(printf "%03d" $NEXT_DEVICE_NUM)"
    echo "   下一个设备频率: $NEXT_ADVERTISING_INTERVAL"
    read -p "按 Enter 继续，或输入 'q' 退出: " CONTINUE_CHOICE
    
    # 如果用户输入 'q'、'Q' 或 'quit'，则退出循环
    if [[ "$CONTINUE_CHOICE" == "q" || "$CONTINUE_CHOICE" == "Q" || "$CONTINUE_CHOICE" == "quit" ]]; then
        break
    fi
    
    # 检查下一个编号是否会超出范围
    if [ $((DEVICE_NUMBER + 1)) -gt 99 ]; then
        echo "⚠️  下一个设备编号将超出范围(>99)，批量刷写即将结束。"
        read -p "按 Enter 继续最后一次刷写，或输入任意字符退出: " FINAL_CHOICE
        if [[ -n "$FINAL_CHOICE" ]]; then
            break
        fi
    fi
done # 主循环结束

echo
echo "📊 批量刷写统计："
if [ -f "$LOG_FILE" ]; then
    TOTAL_COUNT=$(grep -c "刷写状态:" "$LOG_FILE")
    SUCCESS_COUNT=$(grep -c "✅ 刷写成功" "$LOG_FILE")
    FAILED_COUNT=$(grep -c "❌ 刷写失败" "$LOG_FILE")
    
    echo "   - 总计刷写: $TOTAL_COUNT 次"
    echo "   - 成功刷写: $SUCCESS_COUNT 次"
    echo "   - 失败刷写: $FAILED_COUNT 次"
    echo "   - 使用的频率偏移量: $FREQUENCY_OFFSET"
    echo "   - 详细记录: $LOG_FILE"
else
    echo "   - 未找到刷写记录"
fi

echo "所有批量任务已完成。程序退出。"
exit 0