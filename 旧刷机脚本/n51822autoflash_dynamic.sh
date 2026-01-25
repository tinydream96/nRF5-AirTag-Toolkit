#!/bin/bash
# --- 自动路径配置 ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_dynamic_51822.txt"

# --- 日志记录函数 ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (Dynamic Key) - nRF51822" >> "$LOG_FILE"
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

FIRST_RUN=true

# counter for interval increment
CURRENT_INTERVAL=2000

while true; do
    clear
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 动态密钥固件刷写 (nRF51822 QFAB/xxab) ---"
        echo "    注意: 此模式下无需 Keyfile，种子已编译在固件中。"
        echo "    默认使用 ST-Link (OpenOCD)"
        
        # --- SoftDevice 询问 (默认 Y) ---
        read -p "是否需要刷写 SoftDevice (首次需选 y)? [Y/n]: " FLASH_SD_CHOICE
        FLASH_SD_CHOICE=${FLASH_SD_CHOICE:-Y}
        if [[ "$FLASH_SD_CHOICE" =~ ^[Yy]$ ]]; then
            NEED_ERASE=true
            echo "✅ 将执行: 全片擦除 + 刷写 SoftDevice + Application"
        else
            NEED_ERASE=false
            echo "✅ 将执行: 仅刷写 Application (Sector Erase)"
        fi
        
        # --- DCDC 询问 (默认 N) ---
        read -p "是否启用 DCDC? [y/N]: " DCDC_CHOICE
        DCDC_CHOICE=${DCDC_CHOICE:-N}
        if [[ "$DCDC_CHOICE" =~ ^[Yy]$ ]]; then
            HAS_DCDC_VAL="1"
            echo "✅ DCDC: 启用"
        else
            HAS_DCDC_VAL="0"
            echo "✅ DCDC: 禁用"
        fi

        FIRST_RUN=false
        sleep 1
    else
        echo "----------------------------------------"
        echo "   准备下一次刷写 (nRF51822)"
        echo "----------------------------------------"
        # 增加间隔
        CURRENT_INTERVAL=$((CURRENT_INTERVAL + 10))
        
        read -p "按 Enter 继续刷写下一台设备 (广播间隔: $CURRENT_INTERVAL)，或输入 'q' 退出: " NEXT_CHOICE
        if [[ "$NEXT_CHOICE" == "q" || "$NEXT_CHOICE" == "quit" ]]; then
            break
        fi
    fi
    
    FLASH_CMD="make -C heystack-nrf5x/nrf51822/armgcc stflash-nrf51822_xxab HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 DYNAMIC_KEYS=1 ADVERTISING_INTERVAL=$CURRENT_INTERVAL"
    
    echo
    echo "========================================"
    echo "       本次刷写参数预览"
    echo "========================================"
    echo "  - 模式: Dynamic Keys (无限密钥)"
    echo "  - 芯片: nRF51822 (QFAB)"
    echo "  - 轮换间隔: 900 秒 (15分钟)"
    echo "  - 广播间隔: $CURRENT_INTERVAL ms (约 $((CURRENT_INTERVAL / 1000)).$(( (CURRENT_INTERVAL % 1000) / 100 )) 秒)"
    echo "  - 启用 DCDC: $([ "$HAS_DCDC_VAL" == "1" ] && echo "是" || echo "否")"
    echo "========================================"
    echo
    
    read -p "确认参数无误？按 Enter 开始刷写..."
    
    echo "--- 步骤 2: 正在编译并刷写 (ST-Link) ---"
    
    # 清理并编译
    echo "正在清理..."
    make -C heystack-nrf5x/nrf51822/armgcc clean > /dev/null
    
    echo "正在编译和刷写..."
    echo "执行: $FLASH_CMD"
    
    # 注意: Makefile 里的 openocd 调用可能写死了 nrf51 mass_erase
    # 我们的 stflash 目标会自动全片擦除 (init; halt; nrf51 mass_erase; ...)
    # 如果用户只想刷 APP，这就有点浪费。
    # 但为了简单起见，且 dynamic mode 下通常不怕数据丢失（种子在代码里），全刷最安全。
    
    eval $FLASH_CMD
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 刷写成功！🎉🎉🎉"
        log_flash_record "Dynamic_Device_51822" "$FLASH_CMD" "✅ 刷写成功"
    else
        echo "❌ 刷写失败 (退出码: $EXIT_CODE)。"
        log_flash_record "Dynamic_Device_51822" "$FLASH_CMD" "❌ 刷写失败"
    fi
    
    echo "--------------------------------------------------------"
done
