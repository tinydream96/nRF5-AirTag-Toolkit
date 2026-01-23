#!/bin/bash

# nRF52810 芯片保护快速恢复脚本
# 简化版本，专注于最常用的恢复方法

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== nRF52810 芯片保护快速恢复 ===${NC}"
echo "此脚本将尝试恢复被保护的 nRF52xxx 芯片"
echo ""

# 检查必需工具
echo -e "${YELLOW}检查工具...${NC}"
if ! command -v nrfjprog >/dev/null 2>&1; then
    echo -e "${RED}❌ nrfjprog 未安装${NC}"
    echo "请安装: brew install --cask nordic-nrf-command-line-tools"
    exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
    echo -e "${RED}❌ openocd 未安装${NC}"
    echo "请安装: brew install openocd"
    exit 1
fi

echo -e "${GREEN}✅ 工具检查完成${NC}"
echo ""

# 检测芯片类型
CHIP_TYPE="nrf52"
if [ "$1" = "nrf51" ]; then
    CHIP_TYPE="nrf51"
    echo -e "${BLUE}使用芯片类型: nRF51${NC}"
else
    echo -e "${BLUE}使用芯片类型: nRF52 (默认)${NC}"
fi

echo ""
echo -e "${YELLOW}开始恢复流程...${NC}"
echo ""

# 方法1: nrfjprog 恢复 (推荐)
echo -e "${BLUE}[方法1] 使用 nrfjprog 恢复...${NC}"
if nrfjprog --recover -f $CHIP_TYPE; then
    echo -e "${GREEN}✅ nrfjprog 恢复成功！${NC}"
    
    # 验证恢复
    if nrfjprog --readcode -f $CHIP_TYPE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 芯片验证成功，恢复完成！${NC}"
        echo ""
        echo -e "${CYAN}后续步骤:${NC}"
        echo "1. 运行编译刷写脚本: ./scripts/compile_and_flash_2s.sh"
        echo "2. 或手动编译: cd heystack-nrf5x/nrf52810/armgcc && make stflash-nrf52810_xxaa-patched [参数]"
        exit 0
    else
        echo -e "${YELLOW}⚠️ 恢复后验证失败，尝试其他方法...${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ nrfjprog 恢复失败，尝试其他方法...${NC}"
fi

echo ""

# 方法2: OpenOCD mass_erase
echo -e "${BLUE}[方法2] 使用 OpenOCD mass_erase...${NC}"

# 查找配置文件
CONFIG_FILE=""
if [ -f "heystack-nrf5x/nrf52810/armgcc/openocd.cfg" ]; then
    CONFIG_FILE="heystack-nrf5x/nrf52810/armgcc/openocd.cfg"
elif [ -f "config/openocd.cfg" ]; then
    CONFIG_FILE="config/openocd.cfg"
else
    # 创建临时配置
    CONFIG_FILE="tmp_rovodev_recovery.cfg"
    cat > $CONFIG_FILE << EOF
# 临时恢复配置
source [find interface/stlink.cfg]
source [find target/nrf52.cfg]
transport select hla_swd
adapter speed 1000
init
EOF
    echo -e "${BLUE}创建临时配置文件: $CONFIG_FILE${NC}"
fi

echo "使用配置文件: $CONFIG_FILE"

# 执行 mass_erase
if [ "$CHIP_TYPE" = "nrf51" ]; then
    ERASE_CMD="init; halt; nrf51 mass_erase; reset; exit"
else
    ERASE_CMD="init; halt; nrf5 mass_erase; reset; exit"
fi

if openocd -f "$CONFIG_FILE" -c "$ERASE_CMD"; then
    echo -e "${GREEN}✅ OpenOCD mass_erase 成功！${NC}"
    
    # 验证连接
    if openocd -f "$CONFIG_FILE" -c "init; targets; exit" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 芯片连接验证成功，恢复完成！${NC}"
        
        # 清理临时文件
        if [[ "$CONFIG_FILE" =~ ^tmp_rovodev_ ]]; then
            rm -f "$CONFIG_FILE"
        fi
        
        echo ""
        echo -e "${CYAN}后续步骤:${NC}"
        echo "1. 运行编译刷写脚本: ./scripts/compile_and_flash_2s.sh"
        echo "2. 或手动编译: cd heystack-nrf5x/nrf52810/armgcc && make stflash-nrf52810_xxaa-patched [参数]"
        exit 0
    else
        echo -e "${YELLOW}⚠️ 连接验证失败${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ OpenOCD mass_erase 失败${NC}"
fi

# 清理临时文件
if [[ "$CONFIG_FILE" =~ ^tmp_rovodev_ ]]; then
    rm -f "$CONFIG_FILE"
fi

echo ""
echo -e "${RED}❌ 所有自动恢复方法都失败了${NC}"
echo ""
echo -e "${YELLOW}手动恢复建议:${NC}"
echo "1. 检查硬件连接 (3.3V, GND, SWDIO, SWCLK)"
echo "2. 尝试使用 J-Link 调试器"
echo "3. 检查芯片是否损坏"
echo "4. 查看详细文档: docs/04-硬件连接与刷写.md"
echo ""
echo -e "${CYAN}手动命令参考:${NC}"
echo "nrfjprog --recover -f $CHIP_TYPE"
echo "nrfjprog --eraseall -f $CHIP_TYPE"
echo ""

exit 1