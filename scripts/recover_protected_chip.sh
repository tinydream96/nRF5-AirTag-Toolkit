#!/bin/bash

# nRF52810-AirTag-Toolkit 芯片保护恢复脚本
# 一键修复被保护的 nRF52xxx 芯片
# 支持 ST-Link 和 J-Link 两种调试器

set -e  # 遇到错误立即退出

SCRIPT_NAME="芯片保护恢复脚本"
LOG_FILE="chip_recovery_$(date +%Y%m%d_%H%M%S).log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
CHIP_TYPE="nrf52"  # 默认芯片类型
DEBUGGER_TYPE=""   # 自动检测
OPENOCD_CONFIG=""  # OpenOCD 配置文件路径
BACKUP_DIR="backup_configs"

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    log "${RED}❌ $1${NC}"
}

log_header() {
    log ""
    log "${PURPLE}=== $1 ===${NC}"
}

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}$SCRIPT_NAME${NC}

用法: $0 [选项]

选项:
  -t, --chip-type TYPE     指定芯片类型 (nrf51, nrf52, nrf52810, nrf52832)
  -d, --debugger TYPE      指定调试器类型 (stlink, jlink, auto)
  -c, --config FILE        指定 OpenOCD 配置文件路径
  -h, --help              显示此帮助信息

示例:
  $0                       # 自动检测并恢复
  $0 -t nrf52810          # 指定 nRF52810 芯片
  $0 -d jlink             # 强制使用 J-Link
  $0 -c custom.cfg        # 使用自定义配置文件

支持的恢复方法:
  1. nrfjprog --recover (推荐，需要 J-Link)
  2. OpenOCD mass_erase (ST-Link 兼容)
  3. 手动配置切换和重试

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--chip-type)
                CHIP_TYPE="$2"
                shift 2
                ;;
            -d|--debugger)
                DEBUGGER_TYPE="$2"
                shift 2
                ;;
            -c|--config)
                OPENOCD_CONFIG="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查必需工具
check_required_tools() {
    log_header "检查必需工具"
    
    local missing_tools=()
    
    # 检查基础工具
    if ! command -v openocd >/dev/null 2>&1; then
        missing_tools+=("openocd")
    else
        log_success "OpenOCD: $(which openocd)"
    fi
    
    # 检查 nrfjprog (J-Link 恢复必需)
    if ! command -v nrfjprog >/dev/null 2>&1; then
        log_warning "nrfjprog 未安装 - J-Link 恢复功能将不可用"
        log_info "安装命令: brew install --cask nordic-nrf-command-line-tools"
    else
        log_success "nrfjprog: $(which nrfjprog)"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必需工具: ${missing_tools[*]}"
        log_info "请运行: ./scripts/one_click_install.sh"
        exit 1
    fi
}

# 检测调试器类型
detect_debugger() {
    if [ "$DEBUGGER_TYPE" != "" ] && [ "$DEBUGGER_TYPE" != "auto" ]; then
        log_info "使用指定的调试器类型: $DEBUGGER_TYPE"
        return
    fi
    
    log_header "自动检测调试器"
    
    # 检测 ST-Link
    if system_profiler SPUSBDataType 2>/dev/null | grep -i "stlink\|stm32" >/dev/null; then
        log_success "检测到 ST-Link 调试器"
        DEBUGGER_TYPE="stlink"
        return
    fi
    
    # 检测 J-Link
    if system_profiler SPUSBDataType 2>/dev/null | grep -i "j-link\|segger" >/dev/null; then
        log_success "检测到 J-Link 调试器"
        DEBUGGER_TYPE="jlink"
        return
    fi
    
    # 检测其他可能的调试器
    if lsusb 2>/dev/null | grep -i "segger\|stm" >/dev/null; then
        log_info "检测到可能的调试器设备"
    fi
    
    log_warning "未能自动检测调试器类型"
    log_info "将尝试使用默认配置 (ST-Link)"
    DEBUGGER_TYPE="stlink"
}

# 查找 OpenOCD 配置文件
find_openocd_config() {
    if [ "$OPENOCD_CONFIG" != "" ] && [ -f "$OPENOCD_CONFIG" ]; then
        log_success "使用指定的配置文件: $OPENOCD_CONFIG"
        return
    fi
    
    log_header "查找 OpenOCD 配置文件"
    
    # 可能的配置文件位置
    local config_paths=(
        "heystack-nrf5x/nrf52810/armgcc/openocd.cfg"
        "heystack-nrf5x/nrf52832/armgcc/openocd.cfg"
        "heystack-nrf5x/nrf51822/armgcc/openocd.cfg"
        "config/openocd.cfg"
        "openocd.cfg"
    )
    
    for config_path in "${config_paths[@]}"; do
        if [ -f "$config_path" ]; then
            OPENOCD_CONFIG="$config_path"
            log_success "找到配置文件: $config_path"
            return
        fi
    done
    
    log_warning "未找到现有配置文件，将创建临时配置"
    create_temp_config
}

# 创建临时 OpenOCD 配置
create_temp_config() {
    log_info "创建临时 OpenOCD 配置文件"
    
    OPENOCD_CONFIG="tmp_rovodev_recovery_openocd.cfg"
    
    case $DEBUGGER_TYPE in
        "jlink")
            cat > "$OPENOCD_CONFIG" << EOF
# 临时 J-Link 配置文件 (芯片恢复用)
source [find interface/jlink.cfg]
source [find target/${CHIP_TYPE}.cfg]

transport select swd
adapter speed 1000

# 初始化
init
EOF
            ;;
        "stlink"|*)
            cat > "$OPENOCD_CONFIG" << EOF
# 临时 ST-Link 配置文件 (芯片恢复用)
source [find interface/stlink.cfg]
source [find target/${CHIP_TYPE}.cfg]

transport select hla_swd
adapter speed 1000

# 初始化
init
EOF
            ;;
    esac
    
    log_success "临时配置文件已创建: $OPENOCD_CONFIG"
}

# 备份现有配置
backup_existing_config() {
    if [ -f "$OPENOCD_CONFIG" ] && [[ ! "$OPENOCD_CONFIG" =~ ^tmp_rovodev_ ]]; then
        log_header "备份现有配置"
        
        mkdir -p "$BACKUP_DIR"
        local backup_file="$BACKUP_DIR/openocd_backup_$(date +%Y%m%d_%H%M%S).cfg"
        
        cp "$OPENOCD_CONFIG" "$backup_file"
        log_success "配置已备份到: $backup_file"
    fi
}

# 方法1: 使用 nrfjprog 恢复 (推荐)
recover_with_nrfjprog() {
    log_header "方法1: 使用 nrfjprog 恢复芯片"
    
    if ! command -v nrfjprog >/dev/null 2>&1; then
        log_error "nrfjprog 未安装，跳过此方法"
        return 1
    fi
    
    log_info "尝试使用 nrfjprog 恢复保护的芯片..."
    
    # 确定芯片系列参数
    local chip_family=""
    case $CHIP_TYPE in
        "nrf51"|"nrf51822")
            chip_family="nrf51"
            ;;
        "nrf52"|"nrf52810"|"nrf52832")
            chip_family="nrf52"
            ;;
        *)
            chip_family="nrf52"  # 默认
            ;;
    esac
    
    log_info "芯片系列: $chip_family"
    
    # 尝试恢复
    if nrfjprog --recover -f "$chip_family" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "nrfjprog 恢复成功！"
        
        # 验证恢复结果
        if nrfjprog --readcode -f "$chip_family" >/dev/null 2>&1; then
            log_success "芯片恢复验证成功"
            return 0
        else
            log_warning "恢复后验证失败，可能需要进一步处理"
            return 1
        fi
    else
        log_error "nrfjprog 恢复失败"
        return 1
    fi
}

# 方法2: 使用 OpenOCD mass_erase
recover_with_openocd() {
    log_header "方法2: 使用 OpenOCD mass_erase"
    
    log_info "尝试使用 OpenOCD 进行芯片擦除..."
    
    # 构建 OpenOCD 命令
    local openocd_cmd="openocd -f \"$OPENOCD_CONFIG\""
    local recovery_commands=""
    
    case $CHIP_TYPE in
        "nrf51"|"nrf51822")
            recovery_commands="init; halt; nrf51 mass_erase; reset; exit"
            ;;
        "nrf52"|"nrf52810"|"nrf52832")
            recovery_commands="init; halt; nrf5 mass_erase; reset; exit"
            ;;
        *)
            recovery_commands="init; halt; nrf5 mass_erase; reset; exit"
            ;;
    esac
    
    log_info "执行命令: $openocd_cmd -c \"$recovery_commands\""
    
    if eval "$openocd_cmd -c \"$recovery_commands\"" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "OpenOCD mass_erase 执行完成"
        
        # 简单验证 - 尝试连接
        if eval "$openocd_cmd -c \"init; targets; exit\"" >/dev/null 2>&1; then
            log_success "芯片连接验证成功"
            return 0
        else
            log_warning "连接验证失败，可能需要进一步处理"
            return 1
        fi
    else
        log_error "OpenOCD mass_erase 失败"
        return 1
    fi
}

# 方法3: 切换调试器配置重试
recover_with_config_switch() {
    log_header "方法3: 切换调试器配置重试"
    
    local original_debugger="$DEBUGGER_TYPE"
    local alternative_debugger=""
    
    case $original_debugger in
        "stlink")
            alternative_debugger="jlink"
            ;;
        "jlink")
            alternative_debugger="stlink"
            ;;
        *)
            log_info "尝试 J-Link 配置"
            alternative_debugger="jlink"
            ;;
    esac
    
    log_info "当前调试器: $original_debugger"
    log_info "尝试切换到: $alternative_debugger"
    
    # 备份当前配置
    local temp_backup="tmp_rovodev_config_backup.cfg"
    if [ -f "$OPENOCD_CONFIG" ]; then
        cp "$OPENOCD_CONFIG" "$temp_backup"
    fi
    
    # 创建替代配置
    DEBUGGER_TYPE="$alternative_debugger"
    create_temp_config
    
    # 尝试恢复
    local recovery_success=false
    if recover_with_openocd; then
        recovery_success=true
    fi
    
    # 恢复原始配置
    if [ -f "$temp_backup" ]; then
        mv "$temp_backup" "$OPENOCD_CONFIG"
    fi
    DEBUGGER_TYPE="$original_debugger"
    
    if [ "$recovery_success" = true ]; then
        log_success "使用替代调试器配置恢复成功"
        return 0
    else
        log_error "替代配置也无法恢复芯片"
        return 1
    fi
}

# 验证芯片状态
verify_chip_status() {
    log_header "验证芯片状态"
    
    # 方法1: 使用 nrfjprog 验证
    if command -v nrfjprog >/dev/null 2>&1; then
        local chip_family=""
        case $CHIP_TYPE in
            "nrf51"|"nrf51822") chip_family="nrf51" ;;
            *) chip_family="nrf52" ;;
        esac
        
        if nrfjprog --readcode -f "$chip_family" >/dev/null 2>&1; then
            log_success "nrfjprog 验证: 芯片可正常访问"
        else
            log_warning "nrfjprog 验证: 芯片仍可能存在保护"
        fi
    fi
    
    # 方法2: 使用 OpenOCD 验证
    if eval "openocd -f \"$OPENOCD_CONFIG\" -c \"init; targets; exit\"" >/dev/null 2>&1; then
        log_success "OpenOCD 验证: 芯片连接正常"
    else
        log_warning "OpenOCD 验证: 芯片连接可能仍有问题"
    fi
}

# 清理临时文件
cleanup() {
    log_header "清理临时文件"
    
    # 清理临时配置文件
    if [[ "$OPENOCD_CONFIG" =~ ^tmp_rovodev_ ]] && [ -f "$OPENOCD_CONFIG" ]; then
        rm -f "$OPENOCD_CONFIG"
        log_success "已删除临时配置文件: $OPENOCD_CONFIG"
    fi
    
    # 清理其他临时文件
    rm -f tmp_rovodev_*.cfg
    rm -f tmp_rovodev_*.log
    
    log_info "临时文件清理完成"
}

# 显示恢复后的建议
show_next_steps() {
    log_header "恢复完成 - 后续步骤"
    
    log ""
    log "${GREEN}🎉 芯片保护恢复流程已完成！${NC}"
    log ""
    log "${CYAN}📋 建议的后续步骤:${NC}"
    log ""
    log "1. ${YELLOW}验证芯片状态:${NC}"
    log "   openocd -f \"$OPENOCD_CONFIG\" -c \"init; targets; exit\""
    log ""
    log "2. ${YELLOW}编译并刷写固件:${NC}"
    log "   cd heystack-nrf5x/nrf52810/armgcc"
    log "   make stflash-nrf52810_xxaa-patched [参数...]"
    log ""
    log "3. ${YELLOW}或使用便捷脚本:${NC}"
    log "   ./scripts/compile_and_flash_2s.sh"
    log ""
    log "4. ${YELLOW}如果问题仍然存在:${NC}"
    log "   - 检查硬件连接"
    log "   - 尝试不同的调试器"
    log "   - 查看日志文件: $LOG_FILE"
    log ""
    log "${CYAN}📞 获取帮助:${NC}"
    log "   - 查看文档: docs/04-硬件连接与刷写.md"
    log "   - 运行环境检查: ./scripts/one_click_verify.sh"
    log ""
}

# 主函数
main() {
    log_header "$SCRIPT_NAME 启动"
    log_info "日志文件: $LOG_FILE"
    log_info "开始时间: $(date)"
    
    # 解析参数
    parse_arguments "$@"
    
    # 检查工具
    check_required_tools
    
    # 检测调试器
    detect_debugger
    
    # 查找配置文件
    find_openocd_config
    
    # 备份配置
    backup_existing_config
    
    log_info "芯片类型: $CHIP_TYPE"
    log_info "调试器类型: $DEBUGGER_TYPE"
    log_info "配置文件: $OPENOCD_CONFIG"
    
    # 尝试恢复方法
    local recovery_success=false
    
    # 方法1: nrfjprog (推荐)
    if recover_with_nrfjprog; then
        recovery_success=true
    # 方法2: OpenOCD mass_erase
    elif recover_with_openocd; then
        recovery_success=true
    # 方法3: 切换配置重试
    elif recover_with_config_switch; then
        recovery_success=true
    fi
    
    # 验证结果
    verify_chip_status
    
    # 显示结果
    if [ "$recovery_success" = true ]; then
        show_next_steps
    else
        log_header "恢复失败"
        log_error "所有恢复方法都失败了"
        log_info "可能的原因:"
        log_info "  - 硬件连接问题"
        log_info "  - 芯片硬件损坏"
        log_info "  - 调试器不兼容"
        log_info "  - 需要专业设备恢复"
        log ""
        log_info "建议:"
        log_info "  1. 检查所有硬件连接"
        log_info "  2. 尝试不同的调试器"
        log_info "  3. 查看详细日志: $LOG_FILE"
        log_info "  4. 寻求技术支持"
    fi
    
    # 清理
    cleanup
    
    log_info "脚本执行完成: $(date)"
}

# 捕获退出信号，确保清理
trap cleanup EXIT

# 执行主函数
main "$@"