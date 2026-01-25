#!/bin/bash
# --- 自动路径配置 ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_jlink_51822.txt"

# --- 日志记录函数 (省略部分细节，保持与 stlink 脚本一致) ---
log_flash_record() {
    local device_name="$1"
    local flash_cmd="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "========================================" >> "$LOG_FILE"
        echo "设备刷写记录日志 (J-Link) - nRF51822" >> "$LOG_FILE"
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
    
    if [ "$FIRST_RUN" = true ]; then
        echo "--- 步骤 1: 请选择要刷写的设备配置 (nRF51822 J-Link 静态密钥模式) ---"
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
        read -p "是否启用 DCDC (如果不确定，请选 n)? [y/N]: " DCDC_CHOICE
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
    
    # 构建 Make 命令 (仅用于编译)
    FLASH_CMD="make -C heystack-nrf5x/nrf51822/armgcc [J-LINK] $FLASH_TARGETS HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} ADV_KEYS_FILE=../../../config/${KEY_FILE_NAME}"
    
    echo
    echo "========================================"
    echo "       本次刷写参数预览"
    echo "========================================"
    echo "  - 模式: Static Keys (静态密钥)"
    echo "  - 芯片: nRF51822 (QFAB)"
    echo "  - 设备: ${DEVICE_PREFIX}${DEVICE_NUMBER}"
    echo "  - 密钥: 200个 (MAX_KEYS)"
    echo "  - 轮换间隔: 900 秒"
    echo "  - 广播间隔: $ADVERTISING_INTERVAL ms (约 $((ADVERTISING_INTERVAL / 1000)).$(( (ADVERTISING_INTERVAL % 1000) / 100 )) 秒)"
    echo "  - 启用 DCDC: $([ "$HAS_DCDC_VAL" == "1" ] && echo "是" || echo "否")"
    echo "========================================"
    echo
    
    read -p "确认参数无误？按 Enter 开始刷写..."
    
    # 步骤 2: 检查连接 (Loop until connected)
    echo
    echo "--- 步骤 2: 正在等待设备连接 (全自动模式) ---"
    echo "   >> 请连接 J-Link 和 目标芯片 <<"
    
    while true; do
        # 2.1 检查 J-Link 是否连接到电脑
        IDS=$(nrfjprog -i)
        if [ -z "$IDS" ]; then
            echo "Waiting for J-Link... (未检测到调试器)"
            sleep 1
            continue
        fi

        echo "正在检查芯片连接 (J-Link ID: $IDS)..."
        
        # 2.2 尝试连接芯片 (策略: Auto -> 100kHz -> Recover)
        
        # 尝试 1: 自动速度 (Auto) - 不加 clock 参数
        if nrfjprog -f nrf51 --readregs >/dev/null 2>&1; then
            echo "✅ 芯片连接成功 (Auto Speed)!"
            break
        fi
        
        # 尝试 2: 降速到 100kHz (解决线材差的问题)
        echo "⚠️  默认速度连接失败，正在尝试低速 (100kHz)..."
        if nrfjprog -f nrf51 --readregs --clock 100 >/dev/null 2>&1; then
            echo "✅ 芯片连接成功 (100kHz)!"
            break
        fi
        
        # 尝试 3: 如果都读不到，尝试 Recover (显示错误输出以便诊断)
        echo "⚠️  无法读取寄存器。输出连接错误信息:"
        nrfjprog -f nrf51 --readregs --clock 100 
        
        echo "🔧 正在尝试自动 Recover (解锁)..."
        if nrfjprog -f nrf51 --recover >/dev/null 2>&1; then
             echo "✅ 解锁成功。"
             break
        fi
        
        # 2.4 失败循环
        echo "❌ 连接失败。请检查: 1.芯片供电 2.SWD线序"
        echo "   (将在 2 秒后自动重试...)"
        sleep 2
    done
    
    echo "🔗 连接建立，准备开始刷写..."
    sleep 1

    # 步骤 3: 编译与刷写
    echo
    echo "--- 步骤 3: 编译与刷写 ---"
    
    # 0. 清理旧构建 (确保 ADVERTISING_INTERVAL 生效)
    echo "🧹 清理..."
    make -C heystack-nrf5x/nrf51822/armgcc clean > /dev/null
    
    # 1. 编译
    echo "🔨 编译固件..."
    # 移除 flash 目标，只构建 bin
    make -C heystack-nrf5x/nrf51822/armgcc nrf51822_xxab HAS_DCDC=$HAS_DCDC_VAL HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=${ADVERTISING_INTERVAL} > /dev/null
    
    if [ $? -ne 0 ]; then
        echo "❌ 编译失败。"
        exit 1
    fi
    
    # 2. Patch
    echo "🔑 注入密钥..."
    BUILD_DIR="$PROJECT_ROOT/heystack-nrf5x/nrf51822/armgcc/_build"
    ORIG_HEX="$BUILD_DIR/nrf51822_xxab.hex"
    ORIG_BIN="$BUILD_DIR/nrf51822_xxab.bin"
    PATCHED_BIN="$BUILD_DIR/nrf51822_xxab_patched.bin"
    PATCHED_HEX="$BUILD_DIR/nrf51822_xxab_patched.hex"
    
    arm-none-eabi-objcopy -I ihex -O binary "$ORIG_HEX" "$ORIG_BIN"
    cp "$ORIG_BIN" "$PATCHED_BIN"
    
    KEY_OFFSET=$(grep -oba "OFFLINEFINDINGPUBLICKEYHERE!" "$ORIG_BIN" | cut -d ':' -f 1)
    if [ -z "$KEY_OFFSET" ]; then
        echo "❌ 错误: 找不到密钥占位符！"
        exit 1
    fi
    
    # 注入 (skip=1 跳过 keyfile 的第一个字节)
    xxd -p -c 100000 "$KEY_FILE_PATH" | xxd -r -p | dd of="$PATCHED_BIN" skip=1 bs=1 seek=$KEY_OFFSET conv=notrunc 2>/dev/null
    
    # 转回 HEX (S130 App base: 0x1B000)
    arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x1B000 "$PATCHED_BIN" "$PATCHED_HEX"
    
    # 3. 刷写 (nrfjprog)
    echo "🔥 正在刷写 (nrfjprog)..."
    SD_HEX="$PROJECT_ROOT/nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex"
    
    if [[ "$FLASH_TARGETS" == *"flash_softdevice"* ]]; then
        echo "   (擦除全片 + SoftDevice)"
        nrfjprog -f nrf51 --eraseall
        nrfjprog -f nrf51 --program "$SD_HEX" --verify
    fi
    
    nrfjprog -f nrf51 --program "$PATCHED_HEX" --sectorerase --verify
    nrfjprog -f nrf51 --reset
    
    if [ $? -eq 0 ]; then
        echo "🎉🎉🎉 刷写成功！🎉🎉🎉"
        log_flash_record "${DEVICE_PREFIX}${DEVICE_NUMBER}" "$FLASH_CMD" "✅ 刷写成功"
    else
        echo "❌ 刷写失败。"
        log_flash_record "${DEVICE_PREFIX}${DEVICE_NUMBER}" "$FLASH_CMD" "❌ 刷写失败"
        EXIT_CODE=1
    fi
    
    echo "--------------------------------------------------------"
    read -p "按 Enter 继续，或输入 'q' 退出: " CONT
    if [[ "$CONT" == "q" ]]; then break; fi
done
