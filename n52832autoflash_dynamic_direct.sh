#!/bin/bash
# --- 自动路径配置 (无需修改) ---
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_FILE="$PROJECT_ROOT/device_flash_log_dynamic_direct.txt"

# --- 配置 ---
# 请根据实际情况调整这些路径
SD_HEX="$PROJECT_ROOT/nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s132/hex/s132_nrf52_6.1.1_softdevice.hex"
APP_HEX="$PROJECT_ROOT/heystack-nrf5x/nrf52832/armgcc/_build/nrf52832_xxaa.hex"

log_flash_record() {
    local status="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $status" >> "$LOG_FILE"
}

echo "--- nRF52832 动态固件刷写 (Direct J-Link Mode) ---"
echo "此模式直接使用 JLinkExe 刷写，可解决 nrfjprog 报错的问题。"

while true; do
    echo
    echo "----------------------------------------"
    read -p "按 Enter 开始刷写 (输入 q 退出): " CHOICE
    if [[ "$CHOICE" == "q" ]]; then break; fi

    # 1. 编译
    echo "🔨 正在编译..."
    # 只编译二进制，不调用 flash 目标
    make -C heystack-nrf5x/nrf52832/armgcc nrf52832_xxaa HAS_DCDC=0 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900
    if [ $? -ne 0 ]; then
        echo "❌ 编译失败！"
        continue
    fi

    # 2. 生成 J-Link 脚本
    SCRIPT="flash_cmd.jlink"
    echo "📝 生成 J-Link 脚本..."
    echo "device nRF52832_xxAA" > $SCRIPT
    echo "si SWD" >> $SCRIPT
    echo "speed 4000" >> $SCRIPT
    echo "connect" >> $SCRIPT
    echo "r" >> $SCRIPT
    echo "h" >> $SCRIPT
    
    # 询问是否刷写 SoftDevice (通常只需要刷一次)
    read -p "是否刷写 SoftDevice (首次必须)? (y/N): " FLASH_SD
    if [[ "$FLASH_SD" == "y" ]]; then
        echo "w4 4001e504 2" >> $SCRIPT  # NVMC.CONFIG = Erase
        echo "w4 4001e50c 1" >> $SCRIPT  # EraseAll
        echo "sleep 100" >> $SCRIPT
        echo "w4 4001e504 0" >> $SCRIPT  # NVMC.CONFIG = ReadOnly
        echo "r" >> $SCRIPT
        echo "loadfile $SD_HEX" >> $SCRIPT
    fi

    echo "loadfile $APP_HEX" >> $SCRIPT
    echo "r" >> $SCRIPT
    echo "g" >> $SCRIPT
    echo "exit" >> $SCRIPT

    # 3. 执行刷写
    echo "🔥 正在刷写 (JLinkExe)..."
    JLinkExe -CommandFile $SCRIPT
    
    if [ $? -eq 0 ]; then
        echo "✅ JLinkExe 执行完毕 (请检查上方是否有 Error)"
        log_flash_record "Success"
    else
        echo "❌ JLinkExe 执行失败"
        log_flash_record "Fail"
    fi
    
    rm -f $SCRIPT
done
