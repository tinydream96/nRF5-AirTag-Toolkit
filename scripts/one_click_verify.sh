#!/bin/bash

# nRF52810-AirTag-Toolkit 一键检验脚本
# 验证开发环境和项目完整性

set -e  # 遇到错误立即退出

PROJECT_NAME="nRF52810-AirTag-Toolkit"
LOG_FILE="verify_log_$(date +%Y%m%d_%H%M%S).txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 检查结果统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[✅ PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_error() {
    log "${RED}[❌ FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

log_warning() {
    log "${YELLOW}[⚠️  WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_header() {
    log ""
    log "${PURPLE}=== $1 ===${NC}"
}

# 检查函数
check_command() {
    local cmd="$1"
    local name="$2"
    ((TOTAL_CHECKS++))
    
    if command -v "$cmd" >/dev/null 2>&1; then
        local version=$(eval "$cmd --version 2>/dev/null | head -n1" || echo "版本未知")
        log_success "$name 已安装: $version"
        return 0
    else
        log_error "$name 未安装"
        return 1
    fi
}

check_file() {
    local file="$1"
    local name="$2"
    ((TOTAL_CHECKS++))
    
    if [ -f "$file" ]; then
        log_success "$name 存在: $file"
        return 0
    else
        log_error "$name 不存在: $file"
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local name="$2"
    ((TOTAL_CHECKS++))
    
    if [ -d "$dir" ]; then
        log_success "$name 存在: $dir"
        return 0
    else
        log_error "$name 不存在: $dir"
        return 1
    fi
}

check_optional_file() {
    local file="$1"
    local name="$2"
    ((TOTAL_CHECKS++))
    
    if [ -f "$file" ]; then
        log_success "$name 存在: $file"
        return 0
    else
        log_warning "$name 不存在 (可选): $file"
        return 1
    fi
}

# 显示欢迎信息
show_welcome() {
    log ""
    log "${CYAN}╭─────────────────────────────────────────────────────────────╮${NC}"
    log "${CYAN}│                                                             │${NC}"
    log "${CYAN}│           🔍 nRF52810-AirTag-Toolkit 一键检验工具            │${NC}"
    log "${CYAN}│                                                             │${NC}"
    log "${CYAN}│  验证开发环境和项目完整性，确保一切就绪！                    │${NC}"
    log "${CYAN}│                                                             │${NC}"
    log "${CYAN}╰─────────────────────────────────────────────────────────────╯${NC}"
    log ""
    log_info "开始系统检验..."
    log_info "日志文件: $LOG_FILE"
}

# 检查系统信息
check_system() {
    log_header "系统信息检查"
    
    log_info "操作系统: $(uname -s)"
    log_info "系统版本: $(sw_vers -productVersion 2>/dev/null || echo '未知')"
    log_info "处理器架构: $(uname -m)"
    log_info "当前用户: $(whoami)"
    log_info "当前目录: $(pwd)"
}

# 检查必需工具
check_required_tools() {
    log_header "必需工具检查"
    
    check_command "brew" "Homebrew"
    check_command "arm-none-eabi-gcc" "ARM GCC 工具链"
    check_command "openocd" "OpenOCD 调试器"
    check_command "git" "Git 版本控制"
    check_command "python3" "Python 3"
    check_command "make" "Make 构建工具"
}

# 检查可选工具
check_optional_tools() {
    log_header "可选工具检查"
    
    check_command "nrfjprog" "nRF Command Line Tools" || log_warning "nRF Command Line Tools 未安装 (可选)"
    ((TOTAL_CHECKS++))
    
    # 检查 Python 包
    if python3 -c "import intelhex" 2>/dev/null; then
        log_success "Python intelhex 包已安装"
        ((PASSED_CHECKS++))
    else
        log_warning "Python intelhex 包未安装 (可选)"
        ((WARNING_CHECKS++))
    fi
    ((TOTAL_CHECKS++))
}

# 检查项目文件结构
check_project_structure() {
    log_header "项目文件结构检查"
    
    # 检查文档目录
    check_directory "docs" "文档目录"
    check_file "docs/README.md" "文档导航"
    check_file "docs/getting-started/environment.md" "环境安装指南"
    check_file "docs/manuals/web-studio.md" "Web Studio 指南"
    
    # 检查脚本目录
    check_directory "scripts" "脚本目录" || check_file "setup_nrf52810.sh" "环境检查脚本"
    check_file "scripts/setup_nrf52810.sh" "环境检查脚本" || check_file "setup_nrf52810.sh" "环境检查脚本"
    check_file "scripts/compile_and_flash_2s.sh" "编译刷写脚本" || check_file "compile_and_flash_2s.sh" "编译刷写脚本"
    
    # 检查项目源码
    check_directory "heystack-nrf5x" "项目源码目录"
    check_file "heystack-nrf5x/main.c" "主程序文件"
    check_file "heystack-nrf5x/nrf52810/armgcc/Makefile" "编译配置文件"
}

# 检查密钥和配置文件
check_keys_and_config() {
    log_header "密钥和配置文件检查"
    
    # 检查密钥文件
    check_file "R0VVSW_keyfile" "密钥文件 (根目录)" || \
    check_file "config/R0VVSW_keyfile" "密钥文件 (config目录)" || \
    check_file "heystack-nrf5x/nrf52810/armgcc/R0VVSW_keyfile" "密钥文件 (armgcc目录)"
    
    # 检查配置文件
    check_optional_file "openocd.cfg" "OpenOCD 配置文件 (根目录)"
    check_optional_file "config/openocd.cfg" "OpenOCD 配置文件 (config目录)"
    check_optional_file "heystack-nrf5x/nrf52810/armgcc/openocd.cfg" "OpenOCD 配置文件 (armgcc目录)"
}

# 检查 SDK
check_sdk() {
    log_header "nRF5 SDK 检查"
    
    if check_directory "nrf-sdk" "nRF SDK 目录"; then
        if check_directory "nrf-sdk/nRF5_SDK_15.3.0_59ac345" "nRF5 SDK 15.3.0"; then
            check_file "nrf-sdk/nRF5_SDK_15.3.0_59ac345/components/softdevice/s112/hex/s112_nrf52_7.2.0_softdevice.hex" "SoftDevice S112"
        fi
    else
        log_error "nRF5 SDK 未安装，请下载并解压到 nrf-sdk/ 目录"
        log_info "下载地址: https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK"
    fi
}

# 检查已编译固件
check_firmware() {
    log_header "已编译固件检查"
    
    if check_directory "firmware/_build" "固件目录" || check_directory "heystack-nrf5x/nrf52810/armgcc/_build" "固件目录"; then
        check_optional_file "firmware/_build/nrf52810_xxaa_s112_patched.bin" "最终固件 (firmware目录)"
        check_optional_file "heystack-nrf5x/nrf52810/armgcc/_build/nrf52810_xxaa_s112_patched.bin" "最终固件 (armgcc目录)"
    else
        log_warning "未找到已编译固件，需要重新编译"
    fi
}

# 检查硬件连接 (可选)
check_hardware() {
    log_header "硬件连接检查 (可选)"
    
    ((TOTAL_CHECKS++))
    if lsusb 2>/dev/null | grep -i "st-link\|stm" >/dev/null; then
        log_success "检测到 ST-Link 调试器"
        ((PASSED_CHECKS++))
    elif system_profiler SPUSBDataType 2>/dev/null | grep -i "st-link\|stm" >/dev/null; then
        log_success "检测到 ST-Link 调试器"
        ((PASSED_CHECKS++))
    else
        log_warning "未检测到 ST-Link 调试器 (如果未连接硬件，这是正常的)"
        ((WARNING_CHECKS++))
    fi
}

# 显示检查结果
show_results() {
    log_header "检查结果汇总"
    
    log ""
    log "${CYAN}📊 检查统计:${NC}"
    log "   总检查项: $TOTAL_CHECKS"
    log "   ${GREEN}✅ 通过: $PASSED_CHECKS${NC}"
    log "   ${RED}❌ 失败: $FAILED_CHECKS${NC}"
    log "   ${YELLOW}⚠️  警告: $WARNING_CHECKS${NC}"
    log ""
    
    local success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        log "${GREEN}🎉 恭喜！所有必需项检查通过！${NC}"
        log "${GREEN}✅ 开发环境已就绪，可以开始开发！${NC}"
        
        if [ $WARNING_CHECKS -gt 0 ]; then
            log ""
            log "${YELLOW}💡 建议处理以下警告项以获得更好的开发体验:${NC}"
            log "   - 安装可选工具可提升开发效率"
            log "   - 连接硬件以进行完整测试"
        fi
        
    elif [ $FAILED_CHECKS -le 2 ]; then
        log "${YELLOW}⚠️  环境基本就绪，但有少量问题需要解决${NC}"
        log "${YELLOW}💡 建议查看失败项并按文档说明进行修复${NC}"
        
    else
        log "${RED}❌ 环境存在较多问题，需要进行配置${NC}"
        log "${RED}💡 建议运行一键安装脚本: ./scripts/one_click_install.sh${NC}"
    fi
    
    log ""
    log "${CYAN}📈 环境完整度: $success_rate%${NC}"
}

# 提供下一步建议
show_next_steps() {
    log_header "下一步建议"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        log "${GREEN}🚀 您可以开始以下操作:${NC}"
        log ""
        log "1. ${BLUE}编译和刷写固件:${NC}"
        log "   ./scripts/compile_and_flash_2s.sh"
        log ""
        log "2. ${BLUE}查看 Web Studio TODO:${NC}"
        log "   cat docs/manuals/web-studio.md"
        log ""
        log "3. ${BLUE}阅读完整文档:${NC}"
        log "   cat docs/README.md"
        
    else
        log "${YELLOW}🔧 建议的修复步骤:${NC}"
        log ""
        log "1. ${BLUE}安装缺失工具:${NC}"
        log "   ./scripts/one_click_install.sh"
        log ""
        log "2. ${BLUE}下载 nRF5 SDK (如果缺失):${NC}"
        log "   访问: https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK"
        log "   解压到: nrf-sdk/ 目录"
        log ""
        log "3. ${BLUE}重新运行检验:${NC}"
        log "   ./scripts/one_click_verify.sh"
    fi
    
    log ""
    log "${PURPLE}📚 获取帮助:${NC}"
    log "   - 查看文档: docs/README.md"
    log "   - Web Studio: docs/manuals/web-studio.md"
    log "   - 故障排除: docs/hardware/connection.md"
}

# 主函数
main() {
    show_welcome
    
    check_system
    check_required_tools
    check_optional_tools
    check_project_structure
    check_keys_and_config
    check_sdk
    check_firmware
    check_hardware
    
    show_results
    show_next_steps
    
    log ""
    log "${CYAN}📝 完整日志已保存到: $LOG_FILE${NC}"
    log "${CYAN}🕒 检验完成时间: $(date)${NC}"
    
    # 返回适当的退出码
    if [ $FAILED_CHECKS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"