#!/bin/bash

# 系统测试脚本

set -e

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

echo "🧪 nRF52810 Web控制台系统测试"
echo "============================="
echo ""

# 测试1: 检查文件结构
print_info "测试1: 检查文件结构..."
required_files=(
    "web/index.html"
    "web/styles.css"
    "web/script_improved.js"
    "web/script_management.js"
    "web/backend/app.py"
    "scripts"
    "config"
)

for file in "${required_files[@]}"; do
    if [ -e "$file" ]; then
        print_success "  $file 存在"
    else
        print_error "  $file 不存在"
    fi
done

# 测试2: 检查Python环境
print_info "测试2: 检查Python环境..."
if command -v python3 >/dev/null 2>&1; then
    python_version=$(python3 --version 2>&1)
    print_success "  Python版本: $python_version"
else
    print_error "  Python3 未安装"
fi

# 测试3: 检查Python依赖
print_info "测试3: 检查Python依赖..."
required_packages=("flask" "flask_cors")
for package in "${required_packages[@]}"; do
    if python3 -c "import ${package//-/_}" 2>/dev/null; then
        print_success "  $package 已安装"
    else
        print_error "  $package 未安装"
    fi
done

# 测试4: 检查后端服务导入
print_info "测试4: 检查后端服务..."
if python3 -c "
import sys
sys.path.append('web/backend')
from app import app
print('后端服务导入成功')
" 2>/dev/null; then
    print_success "  后端服务可以正常导入"
else
    print_error "  后端服务导入失败"
fi

# 测试5: 检查脚本目录
print_info "测试5: 检查脚本目录..."
if [ -d "scripts" ]; then
    script_count=$(find scripts -name "*.sh" | wc -l)
    print_success "  找到 $script_count 个脚本文件"
    
    # 列出一些重要脚本
    important_scripts=("auto_flash.sh" "generate_device_keys.sh" "add_marker_interactive.sh")
    for script in "${important_scripts[@]}"; do
        if [ -f "scripts/$script" ]; then
            print_success "    $script 存在"
        else
            print_warning "    $script 不存在"
        fi
    done
else
    print_error "  scripts目录不存在"
fi

echo ""
print_info "🎯 使用建议:"
echo "1. 运行 ./start_backend.sh 启动后端服务"
echo "2. 运行 ./start_frontend.sh 启动前端服务"
echo "3. 访问 http://localhost:8080 使用Web界面"
echo ""
print_info "📖 详细说明请查看 QUICK_START.md"