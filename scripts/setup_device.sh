#!/bin/bash

# 设备完整设置脚本 - 生成密钥、编译和刷写一体化
# 用法: ./setup_device.sh [设备名称] [密钥数量]

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

# 显示使用说明
show_usage() {
    echo "🚀 nRF52810 设备完整设置工具"
    echo "============================="
    echo ""
    echo "用法:"
    echo "  $0 [设备名称] [密钥数量]"
    echo ""
    echo "参数:"
    echo "  设备名称    设备的唯一标识符 (默认: 交互式输入)"
    echo "  密钥数量    生成的密钥数量 (默认: 200)"
    echo ""
    echo "示例:"
    echo "  $0 DEVICE01 150     # 为设备 DEVICE01 生成 150 个密钥"
    echo "  $0 MYAIRTAG         # 为设备 MYAIRTAG 生成 200 个密钥"
    echo "  $0                  # 交互式输入设备信息"
    echo ""
    echo "功能:"
    echo "  1. 生成设备专用密钥文件"
    echo "  2. 编译固件"
    echo "  3. 刷写到设备"
    echo "  4. 验证刷写结果"
}

# 验证设备名称
validate_device_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Z0-9_]{3,20}$ ]]; then
        print_error "设备名称格式错误"
        print_info "设备名称要求:"
        print_info "- 长度: 3-20 个字符"
        print_info "- 只能包含: 大写字母、数字、下划线"
        print_info "- 示例: DEVICE01, MY_AIRTAG, TEST123"
        return 1
    fi
    return 0
}

# 交互式获取设备名称
get_device_name_interactive() {
    while true; do
        echo ""
        read -p "🏷️  请输入设备名称 (3-20个字符，大写字母/数字/下划线): " device_name
        
        if [ -z "$device_name" ]; then
            print_warning "设备名称不能为空"
            continue
        fi
        
        device_name=$(echo "$device_name" | tr '[:lower:]' '[:upper:]')
        
        if validate_device_name "$device_name"; then
            echo "$device_name"
            return 0
        fi
    done
}

# 交互式获取密钥数量
get_key_count_interactive() {
    while true; do
        echo ""
        read -p "🔑 请输入密钥数量 (1-250, 默认200): " key_count
        
        if [ -z "$key_count" ]; then
            key_count=200
        fi
        
        if [[ "$key_count" =~ ^[0-9]+$ ]] && [ "$key_count" -ge 1 ] && [ "$key_count" -le 250 ]; then
            echo "$key_count"
            return 0
        else
            print_warning "密钥数量必须是 1-250 之间的数字"
        fi
    done
}

# 检查现有文件
check_existing_files() {
    local device_name="$1"
    local keyfile="$PROJECT_ROOT/config/${device_name}_keyfile"
    
    if [ -f "$keyfile" ]; then
        echo ""
        print_warning "设备 $device_name 的密钥文件已存在"
        read -p "是否覆盖现有文件? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    fi
}

# 主函数
main() {
    echo "🚀 nRF52810 设备完整设置工具"
    echo "============================="
    
    # 检查参数
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # 获取设备名称
    if [ -n "$1" ]; then
        device_name=$(echo "$1" | tr '[:lower:]' '[:upper:]')
        if ! validate_device_name "$device_name"; then
            show_usage
            exit 1
        fi
    else
        device_name=$(get_device_name_interactive)
    fi
    
    # 获取密钥数量
    if [ -n "$2" ]; then
        key_count="$2"
        if ! [[ "$key_count" =~ ^[0-9]+$ ]] || [ "$key_count" -lt 1 ] || [ "$key_count" -gt 250 ]; then
            print_error "密钥数量必须是 1-250 之间的数字"
            show_usage
            exit 1
        fi
    else
        key_count=$(get_key_count_interactive)
    fi
    
    # 检查现有文件
    check_existing_files "$device_name"
    
    echo ""
    print_info "开始设置设备: $device_name (密钥数量: $key_count)"
    echo ""
    
    # 步骤1: 生成密钥
    print_info "步骤 1/3: 生成设备密钥..."
    if ! "$SCRIPT_DIR/generate_device_keys.sh" "$device_name" "$key_count"; then
        print_error "密钥生成失败"
        exit 1
    fi
    
    # 步骤2: 复制密钥文件到编译目录
    print_info "步骤 2/3: 准备编译环境..."
    keyfile_src="$PROJECT_ROOT/config/${device_name}_keyfile"
    keyfile_dst="$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/${device_name}_keyfile"
    
    if [ -f "$keyfile_src" ]; then
        cp "$keyfile_src" "$keyfile_dst"
        print_success "密钥文件已复制到编译目录"
    else
        print_error "密钥文件未找到: $keyfile_src"
        exit 1
    fi
    
    # 步骤3: 编译和刷写
    print_info "步骤 3/3: 编译和刷写固件..."
    if ! "$SCRIPT_DIR/compile_and_flash_device.sh" "$device_name"; then
        print_error "编译和刷写失败"
        exit 1
    fi
    
    # 完成
    echo ""
    print_success "🎉 设备 $device_name 设置完成!"
    echo ""
    echo "📋 设置摘要:"
    echo "  📱 设备名称: $device_name"
    echo "  🔑 密钥数量: $key_count"
    echo "  📄 密钥文件: config/${device_name}_keyfile"
    echo "  📋 配置文件: config/${device_name}_devices.json"
    echo ""
    echo "💡 后续操作:"
    echo "  - 查看所有设备: ./scripts/list_device_keys.sh"
    echo "  - 重新刷写: ./scripts/compile_and_flash_device.sh $device_name"
    echo "  - 快速刷写: ./scripts/compile_and_flash_2s.sh $device_name"
}

# 运行主函数
main "$@"