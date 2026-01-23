#!/bin/bash

# 多设备编译和刷写脚本
# 用法: ./compile_and_flash_device.sh [设备名称] [可选参数]

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
    echo "🚀 多设备编译和刷写工具"
    echo ""
    echo "用法:"
    echo "  $0 [设备名称] [选项]"
    echo ""
    echo "参数:"
    echo "  设备名称    - 6位字符的设备标识符 (如: DEV001, TAG123)"
    echo ""
    echo "选项:"
    echo "  --debug     - 启用调试模式"
    echo "  --dcdc      - 启用 DC/DC 转换器 (更省电)"
    echo "  --no-battery - 禁用电池监测"
    echo "  --interval N - 设置广播间隔 (毫秒，默认: 2000)"
    echo "  --rotation N - 设置密钥轮换间隔 (秒，默认: 300)"
    echo "  --max-keys N - 设置最大密钥数量 (默认: 200)"
    echo ""
    echo "示例:"
    echo "  $0 DEV001                    # 使用默认参数刷写设备 DEV001"
    echo "  $0 TAG123 --debug           # 启用调试模式刷写设备 TAG123"
    echo "  $0 NRF001 --dcdc --interval 1000  # 启用 DC/DC，1秒广播间隔"
    echo ""
    echo "可用设备列表:"
    if [ -d "$PROJECT_ROOT/config" ]; then
        for keyfile in "$PROJECT_ROOT/config"/*_keyfile; do
            if [ -f "$keyfile" ]; then
                device_name=$(basename "$keyfile" _keyfile)
                echo "  - $device_name"
            fi
        done
    else
        echo "  (未找到任何设备密钥文件)"
    fi
    echo ""
}

# 验证设备名称
validate_device_name() {
    local device_name="$1"
    
    if [[ ! "$device_name" =~ ^[A-Z0-9]{6}$ ]]; then
        print_error "设备名称必须是6位大写字母和数字组合 (如: DEV001, TAG123)"
        return 1
    fi
    
    return 0
}

# 检查设备密钥文件是否存在
check_device_keyfile() {
    local device_name="$1"
    local keyfile_path="$PROJECT_ROOT/config/${device_name}_keyfile"
    
    if [ ! -f "$keyfile_path" ]; then
        print_error "设备 $device_name 的密钥文件不存在: $keyfile_path"
        print_info "请先运行: ./scripts/generate_device_keys.sh $device_name"
        return 1
    fi
    
    return 0
}

# 检查编译环境
check_build_environment() {
    # 检查 SDK
    if [ ! -d "$PROJECT_ROOT/nrf-sdk/nRF5_SDK_15.3.0_59ac345" ]; then
        print_error "nRF5 SDK 未找到"
        print_info "请参考文档安装 nRF5 SDK 15.3.0"
        return 1
    fi
    
    # 检查项目目录
    if [ ! -f "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/Makefile" ]; then
        print_error "项目 Makefile 未找到"
        print_info "请确保在正确的项目目录中运行此脚本"
        return 1
    fi
    
    # 检查工具链
    if ! which arm-none-eabi-gcc > /dev/null 2>&1; then
        print_error "ARM 工具链未找到"
        print_info "请运行: brew install --cask gcc-arm-embedded"
        return 1
    fi
    
    return 0
}

# 解析命令行参数
parse_arguments() {
    # 默认参数
    DEVICE_NAME=""
    HAS_DEBUG=0
    HAS_DCDC=0
    HAS_BATTERY=1
    ADVERTISING_INTERVAL=2000
    KEY_ROTATION_INTERVAL=300
    MAX_KEYS=200
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                HAS_DEBUG=1
                shift
                ;;
            --dcdc)
                HAS_DCDC=1
                shift
                ;;
            --no-battery)
                HAS_BATTERY=0
                shift
                ;;
            --interval)
                ADVERTISING_INTERVAL="$2"
                shift 2
                ;;
            --rotation)
                KEY_ROTATION_INTERVAL="$2"
                shift 2
                ;;
            --max-keys)
                MAX_KEYS="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "未知选项: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$DEVICE_NAME" ]; then
                    DEVICE_NAME=$(echo "$1" | tr '[:lower:]' '[:upper:]')
                else
                    print_error "多余的参数: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 如果没有提供设备名称，交互式获取
    if [ -z "$DEVICE_NAME" ]; then
        echo ""
        print_info "可用的设备:"
        if [ -d "$PROJECT_ROOT/config" ]; then
            for keyfile in "$PROJECT_ROOT/config"/*_keyfile; do
                if [ -f "$keyfile" ]; then
                    device_name=$(basename "$keyfile" _keyfile)
                    echo "  - $device_name"
                fi
            done
        fi
        echo ""
        read -p "请输入设备名称: " DEVICE_NAME
        DEVICE_NAME=$(echo "$DEVICE_NAME" | tr '[:lower:]' '[:upper:]')
    fi
    
    # 验证设备名称
    if ! validate_device_name "$DEVICE_NAME"; then
        exit 1
    fi
}

# 复制密钥文件到编译目录
copy_keyfile() {
    local device_name="$1"
    local src_keyfile="$PROJECT_ROOT/config/${device_name}_keyfile"
    local dst_keyfile="$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc/${device_name}_keyfile"
    
    print_info "复制密钥文件到编译目录..."
    cp "$src_keyfile" "$dst_keyfile"
    print_success "密钥文件已复制: ${device_name}_keyfile"
}

# 显示编译参数
show_build_parameters() {
    echo ""
    print_info "📋 编译参数:"
    echo "  🔧 设备名称: $DEVICE_NAME"
    echo "  🔑 密钥文件: ${DEVICE_NAME}_keyfile"
    echo "  🐛 调试模式: $([ $HAS_DEBUG -eq 1 ] && echo "启用" || echo "禁用")"
    echo "  ⚡ DC/DC转换器: $([ $HAS_DCDC -eq 1 ] && echo "启用" || echo "禁用")"
    echo "  🔋 电池监测: $([ $HAS_BATTERY -eq 1 ] && echo "启用" || echo "禁用")"
    echo "  📡 广播间隔: ${ADVERTISING_INTERVAL}ms"
    echo "  🔄 密钥轮换间隔: ${KEY_ROTATION_INTERVAL}s"
    echo "  🔢 最大密钥数量: $MAX_KEYS"
    echo ""
}

# 执行编译和刷写
compile_and_flash() {
    local device_name="$1"
    
    print_info "🚀 开始编译和刷写..."
    
    # 切换到编译目录
    cd "$PROJECT_ROOT/heystack-nrf5x/nrf52810/armgcc"
    
    # 构建目标名称
    local target="nrf52810_xxaa"
    if [ $HAS_DCDC -eq 1 ]; then
        target="nrf52810_xxaa-dcdc"
    fi
    
    # 执行编译和刷写
    print_info "正在编译固件..."
    if make stflash-${target}-patched \
        HAS_DEBUG=$HAS_DEBUG \
        HAS_DCDC=$HAS_DCDC \
        HAS_BATTERY=$HAS_BATTERY \
        KEY_ROTATION_INTERVAL=$KEY_ROTATION_INTERVAL \
        MAX_KEYS=$MAX_KEYS \
        ADVERTISING_INTERVAL=$ADVERTISING_INTERVAL \
        ADV_KEYS_FILE=./${device_name}_keyfile; then
        
        print_success "🎉 设备 $device_name 编译和刷写成功!"
    else
        print_error "编译或刷写失败"
        return 1
    fi
}

# 显示后续操作提示
show_next_steps() {
    local device_name="$1"
    
    echo ""
    print_success "🎉 设备 $device_name 刷写完成!"
    echo ""
    echo "📱 后续操作:"
    echo "  1. 设备应该开始广播 AirTag 信号"
    echo "  2. 可以在 iPhone 的"查找"应用中添加此设备"
    echo ""
    if [ $HAS_DEBUG -eq 1 ]; then
        echo "🔍 调试信息:"
        echo "  查看调试日志: make rtt-monitor"
        echo "  或使用: minicom -c on -D /dev/cu.usbmodem*"
        echo ""
    fi
    echo "🔧 设备管理:"
    echo "  查看所有设备: ./scripts/list_device_keys.sh"
    echo "  生成新设备: ./scripts/generate_device_keys.sh [设备名]"
    echo "  备份设备密钥: ./scripts/backup_device_keys.sh"
    echo ""
    echo "⚠️  重要提醒:"
    echo "  - 请妥善保管设备密钥文件"
    echo "  - 每个设备的密钥都是唯一的，不可互换"
    echo "  - 建议定期备份密钥文件"
}

# 主函数
main() {
    echo "🚀 nRF52810 多设备编译和刷写工具"
    echo "===================================="
    
    # 解析参数
    parse_arguments "$@"
    
    # 检查设备密钥文件
    if ! check_device_keyfile "$DEVICE_NAME"; then
        exit 1
    fi
    
    # 检查编译环境
    if ! check_build_environment; then
        exit 1
    fi
    
    # 显示编译参数
    show_build_parameters
    
    # 询问确认
    read -p "是否继续编译和刷写? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    # 复制密钥文件
    copy_keyfile "$DEVICE_NAME"
    
    # 执行编译和刷写
    if compile_and_flash "$DEVICE_NAME"; then
        show_next_steps "$DEVICE_NAME"
    else
        exit 1
    fi
}

# 运行主函数
main "$@"