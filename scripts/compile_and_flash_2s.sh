#!/bin/bash

# nRF52810 固件编译和刷写脚本 - 3秒广播间隔版本
# 用法: ./compile_and_flash_2s.sh [设备名称]

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# 列出现有密钥
list_existing_keys() {
    if [ -d "$PROJECT_ROOT/config" ] && [ -n "$(ls -A "$PROJECT_ROOT/config"/*_keyfile 2>/dev/null)" ]; then
        print_info "现有密钥文件:"
        echo ""
        
        for keyfile in "$PROJECT_ROOT/config"/*_keyfile; do
            if [ -f "$keyfile" ]; then
                local device_name=$(basename "$keyfile" _keyfile)
                local file_size=$(ls -lh "$keyfile" | awk '{print $5}')
                # 获取密钥数量
                local key_count=$(python3 -c "
with open('$keyfile', 'rb') as f:
    data = f.read()
    print((len(data) - 32) // 28)
" 2>/dev/null || echo "未知")
                echo "  📱 $device_name (密钥数量: $key_count, 大小: $file_size)"
            fi
        done
        echo ""
    else
        echo "  (未找到任何密钥文件)"
        echo ""
    fi
}

# 选择密钥设备
select_device() {
    # 如果命令行提供了设备名称，直接使用
    if [ -n "$1" ]; then
        local device_name="$1"
        device_name=$(echo "$device_name" | tr '[:lower:]' '[:upper:]')
        
        if [ -f "$PROJECT_ROOT/config/${device_name}_keyfile" ]; then
            DEVICE_NAME="$device_name"
            print_success "使用指定设备: $DEVICE_NAME"
            return 0
        else
            print_error "指定的设备 $device_name 不存在"
            print_info "将显示可用设备列表..."
            echo ""
        fi
    fi
    
    # 显示可用密钥
    list_existing_keys
    
    # 检查是否有可用密钥
    if [ ! -d "$PROJECT_ROOT/config" ] || [ -z "$(ls -A "$PROJECT_ROOT/config"/*_keyfile 2>/dev/null)" ]; then
        print_error "没有找到任何密钥文件"
        echo ""
        print_info "请先生成密钥文件，可以使用以下方法:"
        echo "  1. 运行 ./scripts/auto_flash.sh 自动生成"
        echo "  2. 手动生成:"
        echo "     cd heystack-nrf5x/tools"
        echo "     python3 generate_keys.py -n 200 --thisisnotforstalking i_agree"
        echo "     然后将生成的文件复制到 config/ 目录"
        return 1
    fi
    
    echo "可用的设备:"
    for keyfile in "$PROJECT_ROOT/config"/*_keyfile; do
        if [ -f "$keyfile" ]; then
            local device_name=$(basename "$keyfile" _keyfile)
            echo "  - $device_name"
        fi
    done
    echo ""
    
    read -p "请输入要使用的设备名称: " selected_device
    selected_device=$(echo "$selected_device" | tr '[:lower:]' '[:upper:]')
    
    if [ -f "$PROJECT_ROOT/config/${selected_device}_keyfile" ]; then
        DEVICE_NAME="$selected_device"
        print_success "已选择设备: $DEVICE_NAME"
        return 0
    else
        print_error "设备 $selected_device 不存在"
        return 1
    fi
}

echo "🚀 nRF52810 固件编译和刷写 (2秒广播间隔)"
echo "============================================="
echo ""

# 选择设备
while true; do
    if select_device "$1"; then
        break
    fi
    echo ""
    print_warning "请重新选择设备"
    echo ""
done

KEYFILE_NAME="${DEVICE_NAME}_keyfile"

echo ""
print_info "编译配置:"
echo "📱 目标设备: $DEVICE_NAME"
echo "🔑 密钥文件: $KEYFILE_NAME"

# 检查是否在正确的目录
if [ ! -f "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/Makefile" ]; then
    print_error "请在包含 heystack-nrf5x 项目的目录中运行此脚本"
    exit 1
fi

# 检查 SDK 是否存在
if [ ! -d "$PROJECT_ROOT/nrf-sdk/nRF5_SDK_15.3.0_59ac345" ]; then
    print_error "nRF5 SDK 未找到，请先下载并解压到 nrf-sdk/ 目录"
    exit 1
fi

# 检查密钥文件是否存在并复制到编译目录
if [ -f "$PROJECT_ROOT/config/$KEYFILE_NAME" ]; then
    print_info "找到密钥文件: config/$KEYFILE_NAME"
    # 复制密钥文件到编译目录
    print_info "复制密钥文件到编译目录..."
    cp "$PROJECT_ROOT/config/$KEYFILE_NAME" "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/"
    print_success "密钥文件复制完成"
elif [ -f "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/$KEYFILE_NAME" ]; then
    print_info "使用编译目录中的密钥文件: $KEYFILE_NAME"
else
    print_error "密钥文件 $KEYFILE_NAME 未找到"
    print_info "请确保密钥文件存在于以下位置之一:"
    echo "   - config/$KEYFILE_NAME"
    echo "   - heystack-nrf5x/nrf52810/armgcc/$KEYFILE_NAME"
    exit 1
fi

# 切换到编译目录
cd "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc"

echo ""
print_info "当前目录: $(pwd)"
print_info "开始编译固件..."

# 编译参数说明
echo ""
print_info "编译参数:"
echo "   - HAS_DCDC=0          : 使用 LDO 稳压器"
echo "   - HAS_BATTERY=1       : 启用电量报告"
echo "   - KEY_ROTATION_INTERVAL=300 : 密钥轮换间隔 5分钟"
echo "   - MAX_KEYS=200        : 最大密钥数量 200"
echo "   - ADVERTISING_INTERVAL=3000 : 蓝牙广播间隔 3秒"
echo "   - ADV_KEYS_FILE=./$KEYFILE_NAME : 密钥文件"

echo ""
print_info "执行编译和刷写命令..."

# 执行编译和刷写
make stflash-nrf52810_xxaa-patched HAS_DCDC=0 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=900 MAX_KEYS=200 ADVERTISING_INTERVAL=3000 ADV_KEYS_FILE=./$KEYFILE_NAME


# 检查编译结果
if [ $? -eq 0 ]; then
    echo ""
    print_success "固件编译和刷写成功完成！"
    echo "📡 蓝牙广播间隔已设置为 3 秒"
    echo "📱 设备: $DEVICE_NAME"
    echo ""
    print_info "后续操作:"
    echo "🔍 查看调试日志:"
    echo "   make rtt-monitor"
    echo ""
    echo "🔄 重新编译带调试功能的版本:"
    echo "   make stflash-nrf52810_xxaa-patched HAS_DEBUG=1 HAS_DCDC=0 HAS_BATTERY=1 KEY_ROTATION_INTERVAL=300 MAX_KEYS=200 ADVERTISING_INTERVAL=2000 ADV_KEYS_FILE=./$KEYFILE_NAME"
    echo ""
    print_warning "请妥善保管密钥文件 config/${KEYFILE_NAME}，每个设备的密钥都是唯一的！"
else
    echo ""
    print_error "编译或刷写失败，请检查错误信息"
    echo ""
    print_info "常见问题排查:"
    echo "   1. 确保 ST-Link V2 正确连接到 nRF52810"
    echo "   2. 检查硬件连接是否正确"
    echo "   3. 确保没有其他程序占用调试器"
    echo "   4. 检查工具链是否正确安装"
    echo "   5. 确保密钥文件格式正确"
    exit 1
fi