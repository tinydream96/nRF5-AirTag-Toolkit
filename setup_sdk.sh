#!/bin/bash

echo "=== nRF5 SDK 15.3.0 自动下载和配置 ==="
echo ""

# 创建目录
mkdir -p nrf-sdk
cd nrf-sdk

# 检查是否已存在
if [ -d "nRF5_SDK_15.3.0_59ac345" ]; then
    echo "✅ SDK 已存在，跳过下载"
else
    echo "📦 开始下载 nRF5 SDK 15.3.0 (约400MB)..."
    echo "请稍等，这可能需要几分钟..."
    
    # 尝试下载
    if command -v wget >/dev/null 2>&1; then
        wget -O nRF5_SDK_15.3.0_59ac345.zip 'https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/sdks/nrf5/binaries/nrf5_sdk_15.3.0_59ac345.zip'
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o nRF5_SDK_15.3.0_59ac345.zip 'https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/sdks/nrf5/binaries/nrf5_sdk_15.3.0_59ac345.zip'
    else
        echo "❌ 未找到 wget 或 curl，请手动下载"
        exit 1
    fi
    
    # 解压
    echo "📂 解压SDK..."
    unzip -q nRF5_SDK_15.3.0_59ac345.zip
    
    # 清理
    rm nRF5_SDK_15.3.0_59ac345.zip
    
    echo "✅ SDK 下载和解压完成"
fi

cd ..

# 配置工具链
echo "🔧 配置工具链..."
MAKEFILE_PATH="nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/toolchain/gcc/Makefile.posix"

if [ -f "$MAKEFILE_PATH" ]; then
    # 备份原文件
    cp "$MAKEFILE_PATH" "$MAKEFILE_PATH.backup"
    
    # 检测工具链路径
    if [ -d "/opt/homebrew/bin" ]; then
        TOOLCHAIN_PATH="/opt/homebrew/bin/"
    elif [ -d "/usr/local/bin" ]; then
        TOOLCHAIN_PATH="/usr/local/bin/"
    else
        echo "⚠️ 未找到标准工具链路径，请手动配置"
        TOOLCHAIN_PATH="/usr/local/bin/"
    fi
    
    # 修改配置
    cat > "$MAKEFILE_PATH" << MAKEFILE_EOF
GNU_INSTALL_ROOT ?= $TOOLCHAIN_PATH
GNU_VERSION ?= 14.3.1
GNU_PREFIX ?= arm-none-eabi
MAKEFILE_EOF
    
    echo "✅ 工具链配置完成: $TOOLCHAIN_PATH"
else
    echo "❌ 未找到 Makefile.posix"
fi

# 验证安装
echo ""
echo "🧪 验证安装..."
if [ -f "nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/toolchain/gcc/Makefile.posix" ]; then
    echo "✅ SDK 安装成功"
    echo "✅ 工具链配置完成"
    echo ""
    echo "🚀 现在可以运行:"
    echo "   ./scripts/compile_and_flash_2s.sh"
else
    echo "❌ SDK 安装失败"
fi
