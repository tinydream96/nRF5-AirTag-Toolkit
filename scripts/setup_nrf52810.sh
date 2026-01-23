#!/bin/bash

# nRF52810 固件刷写环境设置脚本 (macOS)

echo "=== nRF52810 & heystack-nrf5x 固件刷写环境检查 ==="

# 检查工具链
echo "检查开发工具..."
echo "✅ ARM GCC: $(which arm-none-eabi-gcc)"
echo "✅ OpenOCD: $(which openocd)"
echo "✅ Make: $(which make)"
echo "✅ Git: $(which git)"
echo "✅ Python3: $(which python3)"
echo "✅ xxd: $(which xxd)"

# 检查 Nordic 工具
if which mergehex > /dev/null 2>&1; then
    echo "✅ mergehex: $(which mergehex)"
else
    echo "❌ mergehex 未安装 - 运行: brew install --cask nordic-nrf-command-line-tools"
fi

if which nrfjprog > /dev/null 2>&1; then
    echo "✅ nrfjprog: $(which nrfjprog)"
else
    echo "❌ nrfjprog 未安装 - 运行: brew install --cask nordic-nrf-command-line-tools"
fi

# 检查 Python 工具
if python3 -c "import intelhex" > /dev/null 2>&1; then
    echo "✅ intelhex: Python 包已安装"
else
    echo "❌ intelhex 未安装 - 运行: pip3 install intelhex"
fi

# 检查项目结构
echo -e "\n检查项目结构..."
if [ -d "heystack-nrf5x" ]; then
    echo "✅ heystack-nrf5x 项目已存在"
else
    echo "❌ heystack-nrf5x 项目不存在"
fi

if [ -f "heystack-nrf5x/nrf52810/armgcc/R0VVSW_keyfile" ]; then
    echo "✅ 密钥文件已复制"
else
    echo "❌ 密钥文件未找到"
fi

if [ -f "heystack-nrf5x/nrf52810/armgcc/openocd.cfg" ]; then
    echo "✅ OpenOCD 配置文件已创建"
else
    echo "❌ OpenOCD 配置文件未找到"
fi

# 检查 SDK
echo -e "\n检查 nRF5 SDK..."
if [ -d "nrf-sdk/nRF5_SDK_15.3.0_59ac345" ]; then
    echo "✅ nRF5 SDK 已安装"
    SDK_READY=true
else
    echo "⚠️  nRF5 SDK 未安装"
    echo "请从以下链接下载 nRF5_SDK_15.3.0_59ac345.zip:"
    echo "https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK"
    echo "然后解压到 nrf-sdk/ 目录"
    SDK_READY=false
fi

# 如果 SDK 已准备好，提供编译选项
if [ "$SDK_READY" = true ]; then
    echo -e "\n=== 环境准备完成！==="
    echo "现在您可以编译和刷写固件了。"
    echo -e "\n常用编译命令："
    echo "cd heystack-nrf5x/nrf52810/armgcc"
    echo ""
    echo "# 基本编译和刷写（广播间隔2秒）："
    echo "make stflash-nrf52810_xxaa-patched HAS_DCDC=0 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=300 MAX_KEYS=200 ADVERTISING_INTERVAL=2000 ADV_KEYS_FILE=./R0VVSW_keyfile"
    echo ""
    echo "# 带调试功能的编译（广播间隔2秒）："
    echo "make stflash-nrf52810_xxaa-patched HAS_DEBUG=1 HAS_DCDC=0 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=300 MAX_KEYS=200 ADVERTISING_INTERVAL=2000 ADV_KEYS_FILE=./R0VVSW_keyfile"
    echo ""
    echo "# 查看调试日志："
    echo "make rtt-monitor"
else
    echo -e "\n=== 等待 SDK 安装 ==="
    echo "请先完成 nRF5 SDK 的下载和安装，然后重新运行此脚本。"
fi

echo -e "\n=== 硬件连接提醒 ==="
echo "确保 ST-Link V2 与 nRF52810 正确连接："
echo "ST-Link V2    ->  nRF52810"
echo "3.3V          ->  VDD/VCC"
echo "GND           ->  GND/VSS"
echo "SWDIO         ->  SWDIO (P0.18)"
echo "SWCLK         ->  SWCLK (P0.16)"