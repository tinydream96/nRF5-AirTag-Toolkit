#!/bin/bash

# 设备密钥列表和管理脚本
# 用法: ./list_device_keys.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# 列出所有设备密钥
list_device_keys() {
    echo "🔑 设备密钥文件列表"
    echo "===================="
    echo ""
    
    local config_dir="$PROJECT_ROOT/config"
    local found_devices=0
    
    if [ ! -d "$config_dir" ]; then
        print_warning "config 目录不存在"
        return 0
    fi
    
    # 查找所有密钥文件
    for keyfile in "$config_dir"/*_keyfile; do
        if [ -f "$keyfile" ]; then
            local basename=$(basename "$keyfile")
            local device_name=${basename%_keyfile}
            local file_size=$(ls -lh "$keyfile" | awk '{print $5}')
            local keys_file="$config_dir/${device_name}.keys"
            local devices_file="$config_dir/${device_name}_devices.json"
            
            echo "📱 设备: $device_name"
            echo "  📄 密钥文件: $basename ($file_size)"
            
            if [ -f "$keys_file" ]; then
                local key_count=$(grep -c "Private key:" "$keys_file" 2>/dev/null || echo "未知")
                echo "  🔑 密钥数量: $key_count"
            fi
            
            if [ -f "$devices_file" ]; then
                echo "  📋 配置文件: ${device_name}_devices.json"
            fi
            
            echo "  📅 修改时间: $(stat -c %y "$keyfile" 2>/dev/null || stat -f %Sm "$keyfile" 2>/dev/null || echo "未知")"
            echo ""
            
            found_devices=$((found_devices + 1))
        fi
    done
    
    if [ $found_devices -eq 0 ]; then
        print_warning "未找到任何设备密钥文件"
        echo ""
        echo "💡 提示:"
        echo "  使用以下命令生成设备密钥:"
        echo "  ./scripts/generate_device_keys.sh [设备名称] [密钥数量]"
    else
        print_success "找到 $found_devices 个设备的密钥文件"
        echo ""
        echo "🚀 使用密钥:"
        echo "  编译和刷写: ./scripts/compile_and_flash_device.sh [设备名称]"
        echo "  生成新密钥: ./scripts/generate_device_keys.sh [设备名称] [密钥数量]"
    fi
}

# 主函数
main() {
    list_device_keys
}

# 运行主函数
main "$@"