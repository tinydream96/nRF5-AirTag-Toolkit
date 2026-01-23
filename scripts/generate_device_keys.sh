#!/bin/bash

# 多设备密钥生成和管理脚本
# 用法: ./generate_device_keys.sh [设备名称] [密钥数量]

set -e

# 默认参数
DEFAULT_DEVICE_NAME=""
DEFAULT_KEY_COUNT=200
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
    echo "🔑 多设备密钥生成工具"
    echo ""
    echo "用法:"
    echo "  $0 [设备名称] [密钥数量]"
    echo ""
    echo "参数:"
    echo "  设备名称    - 6位字符的设备标识符 (如: DEV001, TAG123)"
    echo "  密钥数量    - 生成的密钥数量 (默认: $DEFAULT_KEY_COUNT, 最大: 500)"
    echo ""
    echo "示例:"
    echo "  $0 DEV001 200    # 为设备 DEV001 生成 200 个密钥"
    echo "  $0 TAG123        # 为设备 TAG123 生成默认数量密钥"
    echo "  $0               # 交互式生成"
    echo ""
    echo "生成的文件:"
    echo "  config/[设备名]_keyfile       - 二进制密钥文件"
    echo "  config/[设备名].keys          - 文本格式密钥"
    echo "  config/[设备名]_devices.json  - 设备配置文件"
    echo ""
}

# 验证设备名称格式
validate_device_name() {
    local device_name="$1"
    
    if [[ ! "$device_name" =~ ^[A-Z0-9]{6}$ ]]; then
        print_error "设备名称必须是6位大写字母和数字组合 (如: DEV001, TAG123)"
        return 1
    fi
    
    return 0
}

# 验证密钥数量
validate_key_count() {
    local key_count="$1"
    
    if ! [[ "$key_count" =~ ^[0-9]+$ ]] || [ "$key_count" -lt 1 ] || [ "$key_count" -gt 500 ]; then
        print_error "密钥数量必须是 1-500 之间的数字"
        return 1
    fi
    
    return 0
}

# 交互式获取设备名称
get_device_name_interactive() {
    while true; do
        echo "" >&2
        print_info "请输入设备名称 (6位大写字母和数字组合):" >&2
        echo "建议格式: DEV001, TAG123, NRF001 等" >&2
        read -p "设备名称: " device_name
        
        if [ -z "$device_name" ]; then
            print_warning "设备名称不能为空" >&2
            continue
        fi
        
        # 转换为大写
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
        echo "" >&2
        print_info "请输入要生成的密钥数量 (1-500):" >&2
        echo "推荐值: 200 (适合大多数应用场景)" >&2
        read -p "密钥数量 [$DEFAULT_KEY_COUNT]: " key_count
        
        # 如果为空，使用默认值
        if [ -z "$key_count" ]; then
            key_count=$DEFAULT_KEY_COUNT
        fi
        
        if validate_key_count "$key_count"; then
            echo "$key_count"
            return 0
        fi
    done
}

# 检查文件是否存在并询问是否覆盖
check_existing_files() {
    local device_name="$1"
    local files_exist=false
    
    if [ -f "$PROJECT_ROOT/config/${device_name}_keyfile" ] || 
       [ -f "$PROJECT_ROOT/config/${device_name}.keys" ] || 
       [ -f "$PROJECT_ROOT/config/${device_name}_devices.json" ]; then
        files_exist=true
    fi
    
    if [ "$files_exist" = true ]; then
        echo ""
        print_warning "检测到设备 $device_name 的密钥文件已存在:"
        [ -f "$PROJECT_ROOT/config/${device_name}_keyfile" ] && echo "  - ${device_name}_keyfile"
        [ -f "$PROJECT_ROOT/config/${device_name}.keys" ] && echo "  - ${device_name}.keys"
        [ -f "$PROJECT_ROOT/config/${device_name}_devices.json" ] && echo "  - ${device_name}_devices.json"
        
        echo ""
        read -p "是否覆盖现有文件? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    fi
}

# 生成密钥
generate_keys() {
    local device_name="$1"
    local key_count="$2"
    
    print_info "开始为设备 $device_name 生成 $key_count 个密钥..."
    
    # 确保 config 目录存在
    mkdir -p "$PROJECT_ROOT/config"
    
    # 切换到工具目录
    cd "$PROJECT_ROOT/heystack-nrf5x/tools"
    
    # 检查 generate_keys.py 是否存在
    if [ ! -f "generate_keys.py" ]; then
        print_error "未找到 generate_keys.py 脚本"
        print_info "请确保在正确的项目目录中运行此脚本"
        exit 1
    fi
    
    # 检查 Python 依赖
    if ! python3 -c "import cryptography" 2>/dev/null; then
        print_error "缺少 Python cryptography 库"
        print_info "请运行: pip3 install cryptography"
        exit 1
    fi
    
    # 生成密钥
    print_info "正在生成密钥..."
    if python3 generate_keys.py -n "$key_count" -p "$device_name" -o keys/ --thisisnotforstalking i_agree; then
        print_success "密钥生成完成"
    else
        print_error "密钥生成失败"
        exit 1
    fi
    
    # 移动文件到 config 目录
    if [ -d "keys" ]; then
        print_info "移动生成的文件到 config 目录..."
        
        # 移动文件
        mv "keys/${device_name}_keyfile" "$PROJECT_ROOT/config/"
        mv "keys/${device_name}.keys" "$PROJECT_ROOT/config/"
        mv "keys/${device_name}_devices.json" "$PROJECT_ROOT/config/"
        
        # 清理临时目录
        rm -rf "keys"
        
        print_success "文件已移动到 config 目录"
    else
        print_error "未找到生成的输出目录"
        exit 1
    fi
}

# 显示生成结果
show_results() {
    local device_name="$1"
    local key_count="$2"
    
    echo ""
    print_success "🎉 设备 $device_name 的密钥生成完成!"
    echo ""
    echo "📁 生成的文件:"
    echo "  📄 config/${device_name}_keyfile       - 二进制密钥文件 (用于刷写)"
    echo "  📄 config/${device_name}.keys          - 文本格式密钥 (用于查看)"
    echo "  📄 config/${device_name}_devices.json  - 设备配置文件 (用于 AirTag 应用)"
    echo ""
    echo "📊 密钥统计:"
    echo "  🔑 密钥数量: $key_count"
    echo "  📏 文件大小: $(ls -lh "$PROJECT_ROOT/config/${device_name}_keyfile" | awk '{print $5}')"
    echo ""
    echo "🚀 下一步操作:"
    echo "  1. 编译和刷写固件:"
    echo "     ./scripts/compile_and_flash_device.sh $device_name"
    echo ""
    echo "  2. 或者手动刷写:"
    echo "     cd heystack-nrf5x/nrf52810/armgcc"
    echo "     cp ../../../config/${device_name}_keyfile ./"
    echo "     make stflash-nrf52810_xxaa-patched ADV_KEYS_FILE=./${device_name}_keyfile"
    echo ""
    echo "💡 提示:"
    echo "  - 请妥善保管密钥文件，每个设备的密钥都是唯一的"
    echo "  - 建议将密钥文件备份到安全位置"
    echo "  - 可以使用 ./scripts/list_device_keys.sh 查看所有设备密钥"
}

# 主函数
main() {
    echo "🔑 nRF52810 多设备密钥生成工具"
    echo "=================================="
    
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
        if ! validate_key_count "$key_count"; then
            show_usage
            exit 1
        fi
    else
        key_count=$(get_key_count_interactive)
    fi
    
    # 检查现有文件
    check_existing_files "$device_name"
    
    # 生成密钥
    generate_keys "$device_name" "$key_count"
    
    # 显示结果
    show_results "$device_name" "$key_count"
}

# 运行主函数
main "$@"