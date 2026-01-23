#!/bin/bash

# ==============================================================================
# 脚本名称: add_marker_interactive.sh (v4 - 支持批处理)
# 功能:     交互式地选择单个或批量处理密钥文件，并为其添加标准结尾标记。
# ==============================================================================

# -- 配置 --
readonly MARKER_HEX="2d6e20454e444f464b455953454e444f464b455953454e444f464b455953210a"
readonly MARKER_STRING="\x2d\x6e\x20ENDOFKEYSENDOFKEYSENDOFKEYS!\x0a"

# -- 颜色定义 --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 可重用函数：处理单个文件 ---
process_single_file() {
    local file_path="$1"
    local filename
    filename=$(basename "$file_path")
    
    echo -e "${BLUE}🔎 正在检查文件: ${YELLOW}$filename${NC}"
    if ! xxd -p -c 100000 "$file_path" | grep -q "$MARKER_HEX"; then
        echo -e "${YELLOW}   -> ⚠️ 标记不存在，正在添加...${NC}"
        printf "%b" "$MARKER_STRING" >> "$file_path"
        echo -e "${GREEN}   -> ✅ 成功！结尾标记已添加。${NC}"
    else
        echo -e "${GREEN}   -> 👍 文件已包含结尾标记，无需操作。${NC}"
    fi
}


# -- 主逻辑 --
echo -e "${BLUE}▶️  开始执行脚本...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

# --- 1. 查找、排序并列出密钥文件 ---
echo -e "${BLUE}🔎 正在查找并排序 '$CONFIG_DIR' 目录下的密钥文件...${NC}"

keyfiles=()
while IFS= read -r line; do
    keyfiles+=("$line")
done < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name "*_keyfile" 2>/dev/null | sort)

if [ ${#keyfiles[@]} -eq 0 ]; then
    echo -e "${RED}❌ 错误: 在 '$CONFIG_DIR' 目录中未找到任何以 '_keyfile' 结尾的文件。${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 找到以下密钥文件 (已排序):${NC}"
for i in "${!keyfiles[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "$(basename "${keyfiles[$i]}")"
done
echo ""

# --- 2. 提示用户选择 (支持编号、名称或前缀) ---
SELECTED_FILE_PATH=""
matching_files=()
process_mode=""
while true; do
    read -p "请输入文件编号、完整设备名称、或批处理前缀: " choice

    # 情况一: 检查输入是否为有效编号
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#keyfiles[@]} ]; then
        SELECTED_FILE_PATH="${keyfiles[$choice-1]}"
        process_mode="single"
        break
    fi

    # 情况二: 检查是否为有效设备名称 (不区分大小写)
    device_name_input=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
    potential_file_path="$CONFIG_DIR/${device_name_input}_keyfile"
    if [ -f "$potential_file_path" ]; then
        SELECTED_FILE_PATH="$potential_file_path"
        process_mode="single"
        break
    fi

    # 情况三: 检查是否为批处理前缀
    prefix=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
    for file in "${keyfiles[@]}"; do
        # 检查文件名是否以指定前缀开头
        if [[ "$(basename "$file")" == "${prefix}"* ]]; then
            matching_files+=("$file")
        fi
    done

    if [ ${#matching_files[@]} -gt 0 ]; then
        process_mode="batch"
        break
    fi

    echo -e "${RED}输入无效，未找到匹配的编号、名称或前缀。${NC}"
done

# --- 3. 根据选择的模式执行操作 ---
if [[ "$process_mode" == "single" ]]; then
    echo -e "\n${BLUE}▶️  您已选择【单个文件】模式...${NC}"
    process_single_file "$SELECTED_FILE_PATH"

elif [[ "$process_mode" == "batch" ]]; then
    echo -e "\n${BLUE}▶️  您已选择【批处理】模式。将处理以下 ${#matching_files[@]} 个文件:${NC}"
    for file in "${matching_files[@]}"; do
        echo -e "  - ${YELLOW}$(basename "$file")${NC}"
    done
    echo ""
    read -p "是否确认继续? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
    
    echo "" 
    for file in "${matching_files[@]}"; do
        process_single_file "$file"
    done
fi

echo -e "\n${BLUE}⏹️  脚本执行完毕。${NC}"