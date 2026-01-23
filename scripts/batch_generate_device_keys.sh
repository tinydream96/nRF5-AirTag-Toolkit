#!/bin/bash

# ==============================================================================
# 脚本名称: batch_generate_device_keys.sh
# 功能:     批量生成多个设备的密钥文件，并自动添加结尾标记
# 用法:     ./batch_generate_device_keys.sh [前缀] [数量] [每个设备密钥数量]
# 示例:     ./batch_generate_device_keys.sh MED 20 200
#          会生成 MED001 到 MED020 共20个设备，每个设备200个密钥
# ==============================================================================

set -e

# 默认参数
DEFAULT_KEY_COUNT_PER_DEVICE=200
MAX_DEVICES=100
MAX_KEYS_PER_DEVICE=500
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 结尾标记配置
readonly MARKER_HEX="2d6e20454e444f464b455953454e444f464b455953454e444f464b455953210a"
readonly MARKER_STRING="\x2d\x6e\x20ENDOFKEYSENDOFKEYSENDOFKEYS!\x0a"

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
    echo "🔑 批量设备密钥生成工具"
    echo ""
    echo "用法:"
    echo "  $0 [前缀] [设备数量] [每个设备密钥数量]"
    echo ""
    echo "参数:"
    echo "  前缀              - 3位字符的设备前缀 (如: MED, DEV, TAG)"
    echo "  设备数量          - 要生成的设备数量 (1-$MAX_DEVICES)"
    echo "  每个设备密钥数量  - 每个设备的密钥数量 (默认: $DEFAULT_KEY_COUNT_PER_DEVICE, 最大: $MAX_KEYS_PER_DEVICE)"
    echo ""
    echo "示例:"
    echo "  $0 MED 20 200     # 生成 MED001-MED020，每个设备200个密钥"
    echo "  $0 DEV 5          # 生成 DEV001-DEV005，每个设备默认数量密钥"
    echo "  $0                # 交互式生成"
    echo ""
    echo "生成的文件 (每个设备):"
    echo "  config/[设备名]_keyfile       - 二进制密钥文件 (带结尾标记)"
    echo "  config/[设备名].keys          - 文本格式密钥"
    echo "  config/[设备名]_devices.json  - 设备配置文件"
    echo ""
    echo "特性:"
    echo "  ✅ 自动为所有密钥文件添加结尾标记"
    echo "  ✅ 支持批量生成多个设备"
    echo "  ✅ 自动编号 (001, 002, 003...)"
    echo "  ✅ 完整的错误检查和验证"
    echo ""
}

# 验证前缀格式
validate_prefix() {
    local prefix="$1"
    
    if [[ ! "$prefix" =~ ^[A-Z]{3}$ ]]; then
        print_error "前缀必须是3位大写字母 (如: MED, DEV, TAG)"
        return 1
    fi
    
    return 0
}

# 验证设备数量
validate_device_count() {
    local device_count="$1"
    
    if ! [[ "$device_count" =~ ^[0-9]+$ ]] || [ "$device_count" -lt 1 ] || [ "$device_count" -gt $MAX_DEVICES ]; then
        print_error "设备数量必须是 1-$MAX_DEVICES 之间的数字"
        return 1
    fi
    
    return 0
}

# 验证每个设备的密钥数量
validate_key_count() {
    local key_count="$1"
    
    if ! [[ "$key_count" =~ ^[0-9]+$ ]] || [ "$key_count" -lt 1 ] || [ "$key_count" -gt $MAX_KEYS_PER_DEVICE ]; then
        print_error "每个设备的密钥数量必须是 1-$MAX_KEYS_PER_DEVICE 之间的数字"
        return 1
    fi
    
    return 0
}

# 交互式获取前缀
get_prefix_interactive() {
    while true; do
        echo "" >&2
        print_info "请输入设备前缀 (3位大写字母):" >&2
        echo "建议格式: MED, DEV, TAG, NRF 等" >&2
        read -p "设备前缀: " prefix
        
        if [ -z "$prefix" ]; then
            print_warning "设备前缀不能为空" >&2
            continue
        fi
        
        # 转换为大写
        prefix=$(echo "$prefix" | tr '[:lower:]' '[:upper:]')
        
        if validate_prefix "$prefix"; then
            echo "$prefix"
            return 0
        fi
    done
}

# 交互式获取设备数量
get_device_count_interactive() {
    while true; do
        echo "" >&2
        print_info "请输入要生成的设备数量 (1-$MAX_DEVICES):" >&2
        echo "例如: 输入 20 将生成 001-020 共20个设备" >&2
        read -p "设备数量: " device_count
        
        if [ -z "$device_count" ]; then
            print_warning "设备数量不能为空" >&2
            continue
        fi
        
        if validate_device_count "$device_count"; then
            echo "$device_count"
            return 0
        fi
    done
}

# 交互式获取每个设备的密钥数量
get_key_count_interactive() {
    while true; do
        echo "" >&2
        print_info "请输入每个设备的密钥数量 (1-$MAX_KEYS_PER_DEVICE):" >&2
        echo "推荐值: $DEFAULT_KEY_COUNT_PER_DEVICE (适合大多数应用场景)" >&2
        read -p "每个设备密钥数量 [$DEFAULT_KEY_COUNT_PER_DEVICE]: " key_count
        
        # 如果为空，使用默认值
        if [ -z "$key_count" ]; then
            key_count=$DEFAULT_KEY_COUNT_PER_DEVICE
        fi
        
        if validate_key_count "$key_count"; then
            echo "$key_count"
            return 0
        fi
    done
}

# 检查是否有现有文件会被覆盖
check_existing_files() {
    local prefix="$1"
    local device_count="$2"
    local existing_files=()
    
    for i in $(seq 1 $device_count); do
        local device_name=$(printf "%s%03d" "$prefix" "$i")
        
        if [ -f "$PROJECT_ROOT/config/${device_name}_keyfile" ] || 
           [ -f "$PROJECT_ROOT/config/${device_name}.keys" ] || 
           [ -f "$PROJECT_ROOT/config/${device_name}_devices.json" ]; then
            existing_files+=("$device_name")
        fi
    done
    
    if [ ${#existing_files[@]} -gt 0 ]; then
        echo ""
        print_warning "检测到以下设备的密钥文件已存在:"
        for device in "${existing_files[@]}"; do
            echo "  - $device"
        done
        
        echo ""
        read -p "是否覆盖现有文件? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    fi
}

# 为单个密钥文件添加结尾标记
add_marker_to_file() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    if ! xxd -p -c 100000 "$file_path" | grep -q "$MARKER_HEX"; then
        printf "%b" "$MARKER_STRING" >> "$file_path"
        print_success "  ✅ 已为 $filename 添加结尾标记"
    else
        print_info "  ℹ️  $filename 已包含结尾标记"
    fi
}

# 生成单个设备的密钥
generate_single_device_keys() {
    local device_name="$1"
    local key_count="$2"
    
    print_info "正在为设备 $device_name 生成 $key_count 个密钥..."
    
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
    if python3 generate_keys.py -n "$key_count" -p "$device_name" -o keys/ --thisisnotforstalking i_agree >/dev/null 2>&1; then
        # 移动文件到 config 目录
        if [ -d "keys" ]; then
            mv "keys/${device_name}_keyfile" "$PROJECT_ROOT/config/"
            mv "keys/${device_name}.keys" "$PROJECT_ROOT/config/"
            mv "keys/${device_name}_devices.json" "$PROJECT_ROOT/config/"
            
            # 清理临时目录
            rm -rf "keys"
            
            # 添加结尾标记
            add_marker_to_file "$PROJECT_ROOT/config/${device_name}_keyfile"
            
            print_success "  ✅ 设备 $device_name 密钥生成完成"
        else
            print_error "未找到生成的输出目录"
            exit 1
        fi
    else
        print_error "设备 $device_name 密钥生成失败"
        exit 1
    fi
}

# 批量生成密钥
batch_generate_keys() {
    local prefix="$1"
    local device_count="$2"
    local key_count="$3"
    
    print_info "开始批量生成密钥..."
    echo ""
    print_info "配置信息:"
    echo "  📝 设备前缀: $prefix"
    echo "  🔢 设备数量: $device_count"
    echo "  🔑 每设备密钥数: $key_count"
    echo "  📁 输出目录: config/"
    echo ""
    
    local start_time=$(date +%s)
    local success_count=0
    local failed_devices=()
    
    for i in $(seq 1 $device_count); do
        local device_name=$(printf "%s%03d" "$prefix" "$i")
        echo "[$i/$device_count] 处理设备: $device_name"
        
        if generate_single_device_keys "$device_name" "$key_count"; then
            ((success_count++))
        else
            failed_devices+=("$device_name")
        fi
        
        # 显示进度
        local progress=$((i * 100 / device_count))
        echo "  📊 总进度: $progress% ($i/$device_count)"
        echo ""
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 显示最终结果
    echo "=================================="
    print_success "🎉 批量生成完成!"
    echo ""
    echo "📊 生成统计:"
    echo "  ✅ 成功: $success_count/$device_count 个设备"
    echo "  ⏱️  用时: ${duration}秒"
    echo "  🔑 总密钥数: $((success_count * key_count))"
    
    if [ ${#failed_devices[@]} -gt 0 ]; then
        echo "  ❌ 失败设备: ${failed_devices[*]}"
    fi
    
    echo ""
    echo "📁 生成的文件位于: $PROJECT_ROOT/config/"
    echo ""
    echo "🚀 下一步操作:"
    echo "  1. 查看所有设备密钥:"
    echo "     ./scripts/list_device_keys.sh"
    echo ""
    echo "  2. 编译和刷写特定设备:"
    echo "     ./scripts/compile_and_flash_device.sh [设备名]"
    echo ""
    echo "  3. 批量刷写 (如果有多个设备):"
    echo "     for device in ${prefix}001 ${prefix}002 ${prefix}003; do"
    echo "       ./scripts/compile_and_flash_device.sh \$device"
    echo "     done"
    echo ""
    echo "💡 提示:"
    echo "  - 所有密钥文件已自动添加结尾标记"
    echo "  - 请妥善保管密钥文件，每个设备的密钥都是唯一的"
    echo "  - 建议将密钥文件备份到安全位置"
}

# 主函数
main() {
    echo "🔑 nRF52810 批量设备密钥生成工具"
    echo "===================================="
    
    # 检查参数
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # 获取前缀
    if [ -n "$1" ]; then
        prefix=$(echo "$1" | tr '[:lower:]' '[:upper:]')
        if ! validate_prefix "$prefix"; then
            show_usage
            exit 1
        fi
    else
        prefix=$(get_prefix_interactive)
    fi
    
    # 获取设备数量
    if [ -n "$2" ]; then
        device_count="$2"
        if ! validate_device_count "$device_count"; then
            show_usage
            exit 1
        fi
    else
        device_count=$(get_device_count_interactive)
    fi
    
    # 获取每个设备的密钥数量
    if [ -n "$3" ]; then
        key_count="$3"
        if ! validate_key_count "$key_count"; then
            show_usage
            exit 1
        fi
    else
        key_count=$(get_key_count_interactive)
    fi
    
    # 显示即将生成的设备列表
    echo ""
    print_info "即将生成以下设备的密钥:"
    for i in $(seq 1 $device_count); do
        local device_name=$(printf "%s%03d" "$prefix" "$i")
        echo "  $i. $device_name"
    done
    echo ""
    
    # 最终确认
    read -p "确认开始批量生成? (Y/n): " final_confirm
    if [[ "$final_confirm" =~ ^[Nn]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    # 检查现有文件
    check_existing_files "$prefix" "$device_count"
    
    # 批量生成密钥
    batch_generate_keys "$prefix" "$device_count" "$key_count"
}

# 运行主函数
main "$@"