#!/bin/bash

# 自动化刷写脚本
# 功能：选择密钥 -> 解除芯片保护 -> 刷写固件

set -e

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

echo "🚀 nRF52810 自动化刷写工具"
echo "=========================="
echo ""

# 检查必要的文件和工具
check_requirements() {
    print_info "检查环境..."
    
    # 检查 generate_keys.py
    if [ ! -f "$PROJECT_ROOT/heystack-nrf5x/tools/generate_keys.py" ]; then
        print_error "未找到 generate_keys.py 脚本"
        exit 1
    fi
    
    # 检查 Python
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python3 未安装"
        exit 1
    fi
    
    # 检查 cryptography 库
    if ! python3 -c "import cryptography" 2>/dev/null; then
        print_error "缺少 Python cryptography 库"
        print_info "请运行: pip3 install cryptography"
        exit 1
    fi
    
    # 检查脚本文件
    if [ ! -f "$PROJECT_ROOT/scripts/quick_chip_recovery.sh" ]; then
        print_error "未找到芯片恢复脚本"
        exit 1
    fi
    
    if [ ! -f "$PROJECT_ROOT/scripts/compile_and_flash_2s.sh" ]; then
        print_error "未找到刷写脚本"
        exit 1
    fi
    
    print_success "环境检查完成"
}

# 列出现有密钥
list_existing_keys() {
    echo ""
    print_info "现有密钥文件:"
    local count=0
    
    if [ -d "$PROJECT_ROOT/config" ]; then
        for keyfile in "$PROJECT_ROOT/config"/*_keyfile; do
            if [ -f "$keyfile" ]; then
                local device_name=$(basename "$keyfile" _keyfile)
                local file_size=$(ls -lh "$keyfile" | awk '{print $5}')
                # 获取密钥数量
                local key_count=$(python3 -c "
with open('$keyfile', 'rb') as f:
    data = f.read()
    print(data[0] if len(data) > 0 else 0)
" 2>/dev/null || echo "?")
                echo "  📱 $device_name (密钥数量: $key_count, 大小: $file_size)"
                ((count++))
            fi
        done
    fi
    
    if [ $count -eq 0 ]; then
        echo "  (未找到任何密钥文件)"
    fi
    echo ""
}

# 生成新密钥
generate_new_keys() {
    local key_count="${1:-200}"
    
    print_info "生成 $key_count 个密钥..."
    
    # 确保 config 目录存在
    mkdir -p "$PROJECT_ROOT/config"
    
    # 切换到工具目录
    cd "$PROJECT_ROOT/heystack-nrf5x/tools"
    
    # 清理旧的输出目录
    rm -rf keys/
    
    # 生成密钥
    print_info "正在生成密钥 (这可能需要一些时间)..."
    if python3 generate_keys.py -n "$key_count" --thisisnotforstalking i_agree; then
        print_success "密钥生成完成"
    else
        print_error "密钥生成失败"
        return 1
    fi
    
    # 检查输出目录
    if [ ! -d "keys" ]; then
        print_error "未找到输出目录"
        return 1
    fi
    
    # 查找生成的文件
    local keyfile=$(find keys/ -name "*_keyfile" | head -1)
    local keysfile=$(find keys/ -name "*.keys" | head -1)
    local devicesfile=$(find keys/ -name "*_devices.json" | head -1)
    
    if [ -z "$keyfile" ]; then
        print_error "未找到生成的密钥文件"
        return 1
    fi
    
    # 提取生成的设备名称（前缀）
    local generated_device_name=$(basename "$keyfile" _keyfile)
    
    print_info "自动生成的设备名称: $generated_device_name"
    
    # 复制文件到 config 目录，保持原始文件名
    print_info "复制密钥文件到 config 目录..."
    
    cp "$keyfile" "$PROJECT_ROOT/config/"
    
    # 检查并添加密钥文件结尾标记
    local copied_keyfile="$PROJECT_ROOT/config/$(basename "$keyfile")"
    if ! xxd -p -c 100000 "$copied_keyfile" | grep -q "2d6e20454e444f464b455953454e444f464b455953454e444f464b455953210a"; then
        print_info "添加密钥文件结尾标记..."
        printf "\x2d\x6e\x20ENDOFKEYSENDOFKEYSENDOFKEYS!\x0a" >> "$copied_keyfile"
        print_success "密钥文件结尾标记已添加"
    fi
    
    if [ -f "$keysfile" ]; then
        cp "$keysfile" "$PROJECT_ROOT/config/"
    fi
    if [ -f "$devicesfile" ]; then
        cp "$devicesfile" "$PROJECT_ROOT/config/"
    fi
    
    # 清理临时文件
    rm -rf keys/
    
    # 切换回项目根目录
    cd "$PROJECT_ROOT"
    
    print_success "密钥文件已复制到 config/${generated_device_name}_keyfile"
    
    # 显示密钥信息
    local final_key_count=$(python3 -c "
with open('$PROJECT_ROOT/config/${generated_device_name}_keyfile', 'rb') as f:
    data = f.read()
    print(data[0] if len(data) > 0 else 0)
" 2>/dev/null || echo "?")
    
    print_success "设备 $generated_device_name 密钥生成完成 (密钥数量: $final_key_count)"
    
    # 返回生成的设备名称
    echo "$generated_device_name"
    return 0
}

# 选择或生成密钥
select_or_generate_keys() {
    list_existing_keys
    
    echo "请选择操作:"
    echo "  1) 使用现有密钥"
    echo "  2) 生成新密钥"
    echo "  3) 退出"
    echo ""
    
    read -p "请选择 (1-3): " choice
    
    case $choice in
        1)
            if [ ! -d "$PROJECT_ROOT/config" ] || [ -z "$(ls -A "$PROJECT_ROOT/config"/*_keyfile 2>/dev/null)" ]; then
                print_warning "没有找到现有密钥，请先生成新密钥"
                return 1
            fi
            
            echo ""
            echo "可用的密钥文件:"
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
                SELECTED_DEVICE="$selected_device"
                print_success "已选择设备: $SELECTED_DEVICE"
                return 0
            else
                print_error "设备 $selected_device 不存在"
                return 1
            fi
            ;;
        2)
            echo ""
            read -p "请输入密钥数量 (默认 200): " key_count
            key_count=${key_count:-200}
            
            if ! [[ "$key_count" =~ ^[0-9]+$ ]] || [ "$key_count" -lt 1 ] || [ "$key_count" -gt 500 ]; then
                print_error "密钥数量必须是 1-500 之间的数字"
                return 1
            fi
            
            # 生成新密钥并获取自动生成的设备名称
            local generated_device=$(generate_new_keys "$key_count")
            if [ $? -eq 0 ] && [ -n "$generated_device" ]; then
                SELECTED_DEVICE="$generated_device"
                return 0
            else
                return 1
            fi
            ;;
        3)
            print_info "退出"
            exit 0
            ;;
        *)
            print_error "无效选择"
            return 1
            ;;
    esac
}

# 解除芯片保护
recover_chip() {
    print_info "开始解除芯片保护..."
    echo ""
    
    if "$PROJECT_ROOT/scripts/quick_chip_recovery.sh"; then
        print_success "芯片保护解除成功"
        return 0
    else
        print_error "芯片保护解除失败"
        echo ""
        print_info "请检查:"
        echo "  1. 硬件连接是否正确"
        echo "  2. 调试器是否正常工作"
        echo "  3. 是否安装了必要的工具 (nrfjprog, openocd)"
        return 1
    fi
}

# 刷写固件
flash_firmware() {
    local device_name="$1"
    
    print_info "开始刷写固件..."
    echo ""
    
    # 切换到项目根目录，然后调用刷写脚本
    cd "$PROJECT_ROOT"
    if "$PROJECT_ROOT/scripts/compile_and_flash_2s.sh" "$device_name"; then
        print_success "固件刷写成功"
        return 0
    else
        print_error "固件刷写失败"
        return 1
    fi
}

# 主流程
main() {
    # 检查环境
    check_requirements
    
    # 选择或生成密钥
    while true; do
        if select_or_generate_keys; then
            break
        fi
        echo ""
        print_warning "请重新选择"
        echo ""
    done
    
    echo ""
    print_info "准备刷写设备: $SELECTED_DEVICE"
    echo ""
    
    # 确认继续
    read -p "是否继续执行芯片恢复和固件刷写? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    echo ""
    echo "🔄 开始自动化流程..."
    echo "==================="
    
    # 步骤1: 解除芯片保护
    echo ""
    echo "📍 步骤 1/2: 解除芯片保护"
    if ! recover_chip; then
        print_error "自动化流程失败: 芯片保护解除失败"
        exit 1
    fi
    
    # 步骤2: 刷写固件
    echo ""
    echo "📍 步骤 2/2: 刷写固件"
    if ! flash_firmware "$SELECTED_DEVICE"; then
        print_error "自动化流程失败: 固件刷写失败"
        exit 1
    fi
    
    # 完成
    echo ""
    echo "🎉 自动化刷写完成!"
    echo "=================="
    print_success "设备 $SELECTED_DEVICE 已成功刷写"
    echo ""
    echo "📱 后续步骤:"
    echo "  1. 设备应该开始广播 AirTag 信号"
    echo "  2. 可以在 iPhone 的"查找"应用中添加此设备"
    echo "  3. 密钥文件已保存在 config/${SELECTED_DEVICE}_keyfile"
    echo ""
    print_warning "请妥善保管密钥文件，每个设备的密钥都是唯一的！"
}

# 运行主函数
main "$@"