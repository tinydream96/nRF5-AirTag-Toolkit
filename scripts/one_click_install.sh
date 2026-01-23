#!/bin/bash

# nRF52810-AirTag-Toolkit 一键安装脚本
# 自动安装所有必需的开发工具和依赖

set -e  # 遇到错误立即退出

PROJECT_NAME="nRF52810-AirTag-Toolkit"
LOG_FILE="install_log_$(date +%Y%m%d_%H%M%S).txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# 检查系统
check_system() {
    log_info "检查系统环境..."
    
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "此脚本仅支持 macOS 系统"
        exit 1
    fi
    
    # 检查系统版本
    macos_version=$(sw_vers -productVersion)
    log_info "macOS 版本: $macos_version"
    
    # 检查架构
    arch=$(uname -m)
    log_info "系统架构: $arch"
    
    if [[ "$arch" == "arm64" ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
        log_info "检测到 Apple Silicon Mac"
    else
        HOMEBREW_PREFIX="/usr/local"
        log_info "检测到 Intel Mac"
    fi
}

# 安装 Homebrew
install_homebrew() {
    log_info "检查 Homebrew..."
    
    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew 已安装: $(brew --version | head -1)"
        return 0
    fi
    
    log_info "安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # 添加到 PATH
    if [[ "$arch" == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    
    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew 安装成功"
    else
        log_error "Homebrew 安装失败"
        exit 1
    fi
}

# 安装开发工具
install_dev_tools() {
    log_info "安装开发工具..."
    
    # 更新 Homebrew
    log_info "更新 Homebrew..."
    brew update
    
    # 安装 ARM 工具链
    log_info "安装 ARM GCC 工具链..."
    if ! brew list --cask gcc-arm-embedded >/dev/null 2>&1; then
        brew install --cask gcc-arm-embedded
        log_success "ARM GCC 工具链安装完成"
    else
        log_warning "ARM GCC 工具链已安装"
    fi
    
    # 安装 OpenOCD
    log_info "安装 OpenOCD..."
    if ! brew list openocd >/dev/null 2>&1; then
        brew install openocd
        log_success "OpenOCD 安装完成"
    else
        log_warning "OpenOCD 已安装"
    fi
    
    # 安装 libusb
    log_info "安装 libusb..."
    if ! brew list libusb >/dev/null 2>&1; then
        brew install libusb
        log_success "libusb 安装完成"
    else
        log_warning "libusb 已安装"
    fi
    
    # 安装 Nordic 命令行工具
    log_info "安装 Nordic 命令行工具..."
    if ! brew list --cask nordic-nrf-command-line-tools >/dev/null 2>&1; then
        brew install --cask nordic-nrf-command-line-tools
        log_success "Nordic 命令行工具安装完成"
    else
        log_warning "Nordic 命令行工具已安装"
    fi
    
    # 安装 Git 和 Python
    log_info "安装 Git 和 Python..."
    if ! brew list git >/dev/null 2>&1; then
        brew install git
    fi
    if ! brew list python3 >/dev/null 2>&1; then
        brew install python3
    fi
    log_success "Git 和 Python 安装完成"
}

# 安装 Python 包
install_python_packages() {
    log_info "安装 Python 包..."
    
    # 安装 intelhex
    if ! python3 -c "import intelhex" >/dev/null 2>&1; then
        log_info "安装 intelhex..."
        pip3 install intelhex
        log_success "intelhex 安装完成"
    else
        log_warning "intelhex 已安装"
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    local all_good=true
    
    # 检查 ARM GCC
    if command -v arm-none-eabi-gcc >/dev/null 2>&1; then
        version=$(arm-none-eabi-gcc --version | head -1)
        log_success "ARM GCC: $version"
    else
        log_error "ARM GCC 未找到"
        all_good=false
    fi
    
    # 检查 OpenOCD
    if command -v openocd >/dev/null 2>&1; then
        version=$(openocd --version 2>&1 | head -1)
        log_success "OpenOCD: $version"
    else
        log_error "OpenOCD 未找到"
        all_good=false
    fi
    
    # 检查 mergehex
    if command -v mergehex >/dev/null 2>&1; then
        version=$(mergehex --version 2>&1 | head -1)
        log_success "mergehex: $version"
    else
        log_error "mergehex 未找到"
        all_good=false
    fi
    
    # 检查 nrfjprog
    if command -v nrfjprog >/dev/null 2>&1; then
        version=$(nrfjprog --version 2>&1 | head -1)
        log_success "nrfjprog: $version"
    else
        log_error "nrfjprog 未找到"
        all_good=false
    fi
    
    # 检查 Python 包
    if python3 -c "import intelhex" >/dev/null 2>&1; then
        log_success "intelhex: Python 包已安装"
    else
        log_error "intelhex Python 包未找到"
        all_good=false
    fi
    
    # 检查其他工具
    for tool in git make python3 xxd; do
        if command -v $tool >/dev/null 2>&1; then
            log_success "$tool: 已安装"
        else
            log_error "$tool: 未找到"
            all_good=false
        fi
    done
    
    if $all_good; then
        log_success "所有工具安装验证通过！"
        return 0
    else
        log_error "部分工具安装失败，请检查错误信息"
        return 1
    fi
}

# 下载 nRF5 SDK 提示
sdk_download_reminder() {
    log_info "nRF5 SDK 下载提醒..."
    
    if [ ! -d "nrf-sdk/nRF5_SDK_15.3.0_59ac345" ]; then
        log_warning "nRF5 SDK 15.3.0 未找到"
        log_info "请手动下载 nRF5 SDK 15.3.0:"
        log_info "1. 访问: https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK"
        log_info "2. 下载: nRF5_SDK_15.3.0_59ac345.zip"
        log_info "3. 解压到: nrf-sdk/ 目录"
        log_info "4. 最终路径应为: nrf-sdk/nRF5_SDK_15.3.0_59ac345/"
    else
        log_success "nRF5 SDK 15.3.0 已存在"
    fi
}

# 创建便捷别名
create_aliases() {
    log_info "创建便捷别名..."
    
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bashrc"
    fi
    
    if [[ -n "$shell_rc" ]]; then
        cat >> "$shell_rc" << 'EOF'

# nRF52810-AirTag-Toolkit 别名
alias nrf-check='./scripts/setup_nrf52810.sh'
alias nrf-flash='./scripts/one_click_flash.sh'
alias nrf-compile='./scripts/compile_and_flash_2s.sh'
EOF
        log_success "别名已添加到 $shell_rc"
        log_info "重新加载终端或运行 'source $shell_rc' 生效"
    fi
}

# 主函数
main() {
    log_info "=== $PROJECT_NAME 一键安装脚本 ==="
    log_info "开始时间: $(date)"
    log_info "日志文件: $LOG_FILE"
    
    # 检查系统
    check_system
    
    # 安装 Homebrew
    install_homebrew
    
    # 安装开发工具
    install_dev_tools
    
    # 安装 Python 包
    install_python_packages
    
    # 验证安装
    if verify_installation; then
        log_success "✅ 所有工具安装完成！"
    else
        log_error "❌ 安装过程中出现错误，请检查日志"
        exit 1
    fi
    
    # SDK 下载提醒
    sdk_download_reminder
    
    # 创建别名
    create_aliases
    
    log_success "🎉 安装完成！"
    log_info "下一步:"
    log_info "1. 下载 nRF5 SDK (如果尚未下载)"
    log_info "2. 运行 './scripts/setup_nrf52810.sh' 检查环境"
    log_info "3. 连接硬件后运行 './scripts/one_click_flash.sh'"
    
    log_info "结束时间: $(date)"
}

# 执行主函数
main "$@"