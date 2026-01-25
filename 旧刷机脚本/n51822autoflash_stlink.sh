#!/bin/bash
# --- 自动路径配置 ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_stlink_51822.txt"

# --- 日志记录函数 ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (ST-Link) - nRF51822" >> "$LOG_FILE"
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

DEVICE_PREFIX=""
DEVICE_NUMBER=""
FIRST_RUN=true

while true; do
    clear
    
    # 步骤 1: 用户交互
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 请选择要刷写的设备配置 (nRF51822 ST-Link 静态密钥模式) ---"
        echo "    (输入 'q' 退出)"
        
        while true; do
            read -p "请输入设备名称前缀 (如: BFX, TAG 等): " DEVICE_PREFIX
            if [[ "$DEVICE_PREFIX" == "q" ]]; then exit 0; fi
            if [[ ! "$DEVICE_PREFIX" =~ ^[A-Za-z]{2,5}$ ]]; then echo "❌ 输入无效"; continue; fi
            DEVICE_PREFIX=$(echo "$DEVICE_PREFIX" | tr '[:lower:]' '[:upper:]')
            break
        done
        
        while true; do
            read -p "请输入起始设备编号 (1-99): " DEVICE_NUMBER
            if [[ "$DEVICE_NUMBER" == "q" ]]; then exit 0; fi
            if [[ ! "$DEVICE_NUMBER" =~ ^[0-9]+$ ]]; then echo "❌ 输入无效"; continue; fi
            break
        done
        
        # 默认 Y
        read -p "是否需要刷写 SoftDevice (首次需选 y)? [Y/n]: " FLASH_SD_CHOICE
        FLASH_SD_CHOICE=${FLASH_SD_CHOICE:-Y}
        if [[ "$FLASH_SD_CHOICE" =~ ^[Yy]$ ]]; then
            FLASH_TARGETS="flash_softdevice flash"
            echo "✅ 将刷写: SoftDevice (S130) + Application"
        else
            FLASH_TARGETS="flash"
            echo "✅ 将刷写: 仅 Application"
        fi
        
        # 默认 N
        read -p "是否启用 DCDC? [y/N]: " DCDC_CHOICE
        DCDC_CHOICE=${DCDC_CHOICE:-N}
        HAS_DCDC_VAL=$([[ "$DCDC_CHOICE" =~ ^[Yy]$ ]] && echo "1" || echo "0")
        echo "✅ DCDC: $([ "$HAS_DCDC_VAL" == "1" ] && echo "启用" || echo "禁用")"

        FIRST_RUN=false
        sleep 1
    else
        echo "--- 继续批量刷写下一个设备 ---"
        DEVICE_NUMBER=$((DEVICE_NUMBER + 1))
        echo "✅ 自动递增到下一个设备编号: $DEVICE_NUMBER"
        sleep 1
    fi
    
    ADVERTISING_INTERVAL=$((2000 + DEVICE_NUMBER * 10))
    KEY_FILE_NAME=$(printf "${DEVICE_PREFIX}%03d_keyfile" $DEVICE_NUMBER)
    KEY_FILE_PATH="$PROJECT_ROOT/config/${KEY_FILE_NAME}"
    
    if [ ! -f "$KEY_FILE_PATH" ]; then
        echo "⚠️  警告: 密钥文件不存在: $KEY_FILE_PATH"
        read -p "是否要继续？(y/N): " CONT
        if [[ "$CONT" != "y" ]]; then continue; fi
    fi
    
    FLASH_CMD="make -C heystack-nrf5x/nrf51822/armgcc stflash-nrf51822_xxab-patched HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    
    echo
    echo "========================================"
    echo "       本次刷写参数预览"
    echo "========================================"
    echo "  - 模式: Static Keys (静态密钥)"
    echo "  - 芯片: nRF51822 (QFAB)"
    echo "  - 设备: ${DEVICE_PREFIX}${DEVICE_NUMBER}"
    echo "  - 密钥: 200个 (MAX_KEYS)"
    echo "  - 轮换间隔: 900 秒"
    echo "  - 广播间隔: $ADVERTISING_INTERVAL (约 $((ADVERTISING_INTERVAL * 625 / 1000)) ms)"
    echo "  - 启用 DCDC: $([ "$HAS_DCDC_VAL" == "1" ] && echo "是" || echo "否")"
    echo "========================================"
    echo
    
    read -p "确认参数无误？按 Enter 开始刷写..."
    
    echo "--- 步骤 2: 正在等待设备连接 (全自动模式) ---"
    echo "   >> 请连接 ST-Link 和 目标芯片 <<"
    
    while true; do
        # 方法: 使用 OpenOCD 尝试仅初始化 (init) 然后退出
        # 如果 ST-Link 没插，OpenOCD 会报错 "Error: open failed" 或 "No J-Link device found" (类似)
        # 如果 Chip 没插，OpenOCD 会报错 "Target not examined"
        
        OUTPUT=$(openocd -f interface/stlink.cfg -f target/nrf51.cfg -c "init; exit" 2>&1)
        OCD_EXIT=$?
        
        if [ $OCD_EXIT -eq 0 ]; then
             echo "✅ 检测到设备 (OpenOCD Init Success)"
             break
        fi
        
        # 分析错误类型
        # 1. 检查 ST-Link 是否在线
        if echo "$OUTPUT" | grep -q "Error: open failed"; then
             echo "Waiting for ST-Link... (未检测到调试器)"
        elif echo "$OUTPUT" | grep -q "unable to open fdi device"; then
            echo "Waiting for ST-Link... (未检测到调试器)"
        # 2. 检查 Chip 是否在线 (Target not examined)
        else
            echo "ST-Link 在线，但无法连接芯片 (Target not examined)..."
            echo "   -> 正在尝试自动解锁 (Mass Erase)..."
            
            # 尝试解锁
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
    
    echo "🔗 连接建立，准备开始刷写..."
    sleep 1
    
    # 清理
    make -C heystack-nrf5x/nrf51822/armgcc clean > /dev/null
    
    echo "正在执行: $FLASH_CMD"
    eval $FLASH_CMD
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🎉🎉🎉 刷写成功！🎉🎉🎉"
        log_flash_record "${DEVICE_PREFIX}${DEVICE_NUMBER}" "$FLASH_CMD" "✅ 刷写成功"
    else
        echo "❌ 刷写失败 (退出码: $EXIT_CODE)。"
        log_flash_record "${DEVICE_PREFIX}${DEVICE_NUMBER}" "$FLASH_CMD" "❌ 刷写失败"
        # 失败不退出，只是记录，然后让用户决定是重试还是下一个
        # 但我们希望全自动? 
        # 用户通常会按 q 退出。
    fi
    
    # 自动继续逻辑：无需按 Enter，但为了给用户看结果，还是需要按一下，或者延时自动继续？
    # 用户之前的 JLink 脚本是手动按 Enter 继续。
    # 用户现在的要求是 "不需要使用键盘确认... 自动执行"。
    # 这可能指的是连接建立自动执行。刷完后的确认可能还是需要的，否则怎么换下一个设备？
    # 除非是流水线模式，在此暂保留按键确认进入下一个设备。
    
    echo "--------------------------------------------------------"
    read -p "按 Enter 继续刷写下一台 (或输入 'q' 退出): " CONT
    if [[ "$CONT" == "q" ]]; then break; fi
done
