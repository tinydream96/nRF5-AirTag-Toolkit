#!/bin/bash
# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录 (即项目根目录)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- 日志文件配置 ---
LOG_FILE="$PROJECT_ROOT/device_flash_log_dynamic_52832.txt"

# --- 日志记录函数 ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (Dynamic Key) - nRF52832" >> "$LOG_FILE"
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
FIRST_RUN=true

while true; do
    clear
    
    # ==============================================================================
    # 步骤 1: 用户交互
    # ==============================================================================
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 动态密钥固件刷写 (nRF52832) ---"
        echo "    注意: 此模式下无需 Keyfile，种子已编译在固件中。"
        echo "    (输入 'q' 退出)"
        
        # --- SoftDevice 询问 ---
        read -p "是否需要刷写 SoftDevice (首次刷写必选)? (y/N): " FLASH_SD_CHOICE
        if [[ "$FLASH_SD_CHOICE" == "y" || "$FLASH_SD_CHOICE" == "Y" ]]; then
            FLASH_TARGETS="flash_softdevice flash"
            echo "✅ 将刷写: SoftDevice (S132) + Application"
        else
            FLASH_TARGETS="flash"
            echo "✅ 将刷写: 仅 Application"
        fi
        
        # --- DCDC 询问 ---
        read -p "是否启用 DCDC? (y/N): " DCDC_CHOICE
        if [[ "$DCDC_CHOICE" == "y" || "$DCDC_CHOICE" == "Y" ]]; then
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
        echo "   准备下一次刷写 (nRF52832)"
        echo "----------------------------------------"
        read -p "按 Enter 继续刷写下一台设备，或输入 'q' 退出: " NEXT_CHOICE
        if [[ "$NEXT_CHOICE" == "q" || "$NEXT_CHOICE" == "quit" ]]; then
            break
        fi
    fi
    
    # 编译命令 (不再传递 KEY_FILE)
    FLASH_CMD="make -C heystack-nrf5x/nrf52832/armgcc $FLASH_TARGETS HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900"
    
    # ==============================================================================
    # 步骤 2: 检查连接 (带 J-Link 救砖逻辑)
    # ==============================================================================
    echo
    echo "--- 步骤 2: 正在检查 J-Link 连接... ---"
    
    while true; do
        IDS=$(nrfjprog -i)
        if [ -z "$IDS" ]; then
            echo "❌ 未检测到 J-Link 调试器。"
            echo "   请检查 USB 连接。"
            read -p "   (r)重试, (i)忽略并强制刷写, (q)退出: " RETRY_OP
            if [[ "$RETRY_OP" == "q" ]]; then exit 0; fi
            if [[ "$RETRY_OP" == "i" ]]; then break; fi
            continue
        fi

        echo "正在尝试读取芯片信息 (nrfjprog)..."
        nrfjprog -f nrf52 --readregs > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "✅ 设备连接成功 (ID: $IDS)。"
            break
        fi
        
        echo "⚠️  nrfjprog 读取失败。尝试 Recover (解锁)..."
        nrfjprog -f nrf52 --recover > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "✅ 芯片 Recover 成功。"
            break
        fi
        
        echo "⚠️  nrfjprog Recover 失败。尝试 J-Link 手动解锁..."
        
        # J-Link 手动解锁脚本
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
        
        # 再次尝试连接
        nrfjprog -f nrf52 --readregs > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "✅ J-Link 手动解锁成功！"
            break
        else
            echo "❌ 无法连接芯片。可能原因：电源未接、接线错误、或芯片损坏。"
            read -p "   (r)重试, (i)忽略并强制刷写, (q)退出: " RETRY_OP
            if [[ "$RETRY_OP" == "q" ]]; then exit 0; fi
            if [[ "$RETRY_OP" == "i" ]]; then 
                echo "⚠️  已选择强制刷写 (Force Flash)..."
                break
            fi
        fi
    done
    
    # ==============================================================================
    # 步骤 3: 编译并刷写
    # ==============================================================================
    echo
    echo "--- 步骤 3: 正在编译并刷写 ---"
    
    log_flash_record "Dynamic_Device" "$FLASH_CMD" "开始刷写"
    
    # 直接执行 Make flash
    echo "执行: $FLASH_CMD"
    eval $FLASH_CMD
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 刷写成功！🎉🎉🎉"
        log_flash_record "Dynamic_Device" "$FLASH_CMD" "✅ 刷写成功"
    else
        echo "❌ 刷写失败 (退出码: $EXIT_CODE)。"
        log_flash_record "Dynamic_Device" "$FLASH_CMD" "❌ 刷写失败"
        exit 1
    fi
    
    echo "--------------------------------------------------------"
done
