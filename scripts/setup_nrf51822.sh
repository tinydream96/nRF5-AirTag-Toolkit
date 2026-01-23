#!/bin/bash

# nRF51822 固件刷写环境设置脚本 (macOS)
# 检查SDK 12.3.0、工具链、硬件连接

echo "=== nRF51822 & heystack-nrf5x 固件刷写环境检查 ==="

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

if [ -d "heystack-nrf5x/nrf51822" ]; then
    echo "✅ nRF51822 项目目录已存在"
else
    echo "❌ nRF51822 项目目录不存在"
fi

if [ -f "heystack-nrf5x/nrf51822/armgcc/Makefile" ]; then
    echo "✅ nRF51822 Makefile 已存在"
else
    echo "❌ nRF51822 Makefile 未找到"
fi

if [ -f "heystack-nrf5x/nrf51822/armgcc/openocd.cfg" ]; then
    echo "✅ nRF51822 OpenOCD 配置文件已存在"
else
    echo "❌ nRF51822 OpenOCD 配置文件未找到"
fi

# 检查密钥文件
echo -e "\n检查密钥文件..."
KEYFILE_COUNT=$(find config/ -name "*_keyfile" 2>/dev/null | wc -l)
if [ $KEYFILE_COUNT -gt 0 ]; then
    echo "✅ 找到 $KEYFILE_COUNT 个密钥文件"
    echo "   可用的密钥文件:"
    find config/ -name "*_keyfile" 2>/dev/null | head -5 | while read file; do
        echo "   - $(basename $file)"
    done
    if [ $KEYFILE_COUNT -gt 5 ]; then
        echo "   ... 还有 $((KEYFILE_COUNT - 5)) 个文件"
    fi
else
    echo "❌ 未找到密钥文件"
    echo "   请先运行: ./scripts/generate_device_keys.sh [设备名]"
fi

# 检查 nRF5 SDK 12.3.0 (nRF51822专用)
echo -e "\n检查 nRF5 SDK 12.3.0 (nRF51822专用)..."
if [ -d "nrf-sdk/nRF5_SDK_12.3.0_d7731ad" ]; then
    echo "✅ nRF5 SDK 12.3.0 已安装"
    
    # 检查关键组件
    if [ -f "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/softdevice/s130/hex/s130_nrf51_2.0.1_softdevice.hex" ]; then
        echo "✅ S130 SoftDevice 已找到"
    else
        echo "⚠️  S130 SoftDevice 未找到"
    fi
    
    if [ -d "nrf-sdk/nRF5_SDK_12.3.0_d7731ad/components/toolchain/gcc" ]; then
        echo "✅ GCC 工具链配置已找到"
    else
        echo "⚠️  GCC 工具链配置未找到"
    fi
    
    SDK_READY=true
else
    echo "⚠️  nRF5 SDK 12.3.0 未安装"
    echo "请从以下链接下载 nRF5_SDK_12.3.0_d7731ad.zip:"
    echo "https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK/Download#infotabs"
    echo "然后解压到 nrf-sdk/ 目录"
    SDK_READY=false
fi

# 检查 ARM GCC 工具链版本
echo -e "\n检查 ARM GCC 工具链版本..."
if which arm-none-eabi-gcc > /dev/null 2>&1; then
    GCC_VERSION=$(arm-none-eabi-gcc --version | head -n1)
    echo "✅ $GCC_VERSION"
    
    # nRF51822 推荐使用较老版本的GCC
    if arm-none-eabi-gcc --version | grep -q "6.3.1\|7.3.1\|8.3.1"; then
        echo "✅ GCC 版本兼容 nRF51822"
    else
        echo "⚠️  当前 GCC 版本可能不是最佳选择"
        echo "   nRF51822 推荐使用 GCC 6.3.1, 7.3.1 或 8.3.1"
    fi
else
    echo "❌ ARM GCC 工具链未安装"
    echo "   运行: brew install --cask gcc-arm-embedded"
fi

# 如果 SDK 已准备好，提供编译选项
if [ "$SDK_READY" = true ]; then
    echo -e "\n=== 环境准备完成！==="
    echo "现在您可以编译和刷写 nRF51822 固件了。"
    echo -e "\n常用编译命令："
    echo "cd heystack-nrf5x/nrf51822/armgcc"
    echo ""
    echo "# 基本编译和刷写："
    echo "make stflash-nrf51822_xxac-patched HAS_DCDC=0 HAS_BATTERY=0 KEY_ROTATION_INTERVAL=300 MAX_KEYS=200 ADVERTISING_INTERVAL=2000 ADV_KEYS_FILE=./[设备名]_keyfile"
    echo ""
    echo "# 带调试功能的编译："
    echo "make stflash-nrf51822_xxac-patched HAS_DEBUG=1 HAS_DCDC=0 HAS_BATTERY=0 KEY_ROTATION_INTERVAL=300 MAX_KEYS=200 ADVERTISING_INTERVAL=2000 ADV_KEYS_FILE=./[设备名]_keyfile"
    echo ""
    echo "# 清理编译文件："
    echo "make clean"
    echo ""
    echo "# 仅编译不刷写："
    echo "make nrf51822_xxac"
else
    echo -e "\n=== 等待 SDK 安装 ==="
    echo "请先完成 nRF5 SDK 12.3.0 的下载和安装，然后重新运行此脚本。"
fi

echo -e "\n=== nRF51822 硬件连接提醒 ==="
echo "确保 ST-Link V2 与 nRF51822 正确连接："
echo "ST-Link V2    ->  nRF51822"
echo "3.3V          ->  VDD/VCC"
echo "GND           ->  GND/VSS"
echo "SWDIO         ->  SWDIO"
echo "SWCLK         ->  SWCLK"
echo ""
echo "⚠️  nRF51822 注意事项："
echo "- 使用 3.3V 供电，不要使用 5V"
echo "- 确保连接稳定，nRF51822 对电源质量要求较高"
echo "- 如果刷写失败，尝试降低 SWD 时钟频率"
echo "- nRF51822 不支持 DCDC 模式，请设置 HAS_DCDC=0"
echo "- nRF51822 电量检测功能有限，建议设置 HAS_BATTERY=0"

echo -e "\n=== 故障排除 ==="
echo "如果遇到问题："
echo "1. 检查硬件连接是否正确"
echo "2. 确认使用正确的 SDK 版本 (12.3.0)"
echo "3. 验证工具链版本兼容性"
echo "4. 检查密钥文件是否存在且格式正确"
echo "5. 尝试使用较低的 SWD 时钟频率"
echo ""
echo "获取帮助："
echo "- 查看项目文档: docs/"
echo "- 运行环境验证: ./scripts/one_click_verify.sh"
echo "- 生成设备密钥: ./scripts/generate_device_keys.sh [设备名]"