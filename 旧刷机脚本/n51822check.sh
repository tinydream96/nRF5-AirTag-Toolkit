#!/bin/bash

# --- 自动路径配置 (无需修改) ---
# 获取脚本文件所在的真实目录，无论从哪里运行此脚本
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# 定义相对于项目根目录的目标子目录
RELATIVE_TARGET_DIR="heystack-nrf5x/nrf51822/armgcc"

# 组合成最终的目标目录绝对路径
TARGET_DIR="$SCRIPT_DIR/$RELATIVE_TARGET_DIR"
# ------------------------------------

# 定义要运行的命令 (无需修改)
COMMAND='openocd -f openocd.cfg -c "init; exit"'

# 检查目标目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
  echo "❌ 错误: 目标目录不存在: $TARGET_DIR"
  echo "请确保此脚本保存在项目的根目录下，并且子目录 '$RELATIVE_TARGET_DIR' 存在。"
  exit 1
fi

# 切换到目标目录
echo "✅ 脚本位置: $SCRIPT_DIR"
echo "✅ 切换到工作目录: $TARGET_DIR"
cd "$TARGET_DIR" || exit

# --- 循环重试逻辑 (和之前一样) ---
while true; do
  echo "--- 正在尝试运行 OpenOCD ---"
  
  OUTPUT=$(eval $COMMAND 2>&1 | tee /dev/tty)

  if echo "$OUTPUT" | grep -iq "Error"; then
    echo "检测到错误，将在 2 秒后重试..."
    sleep 2
  else
    echo "🎉 命令成功执行，脚本退出。"
    break
  fi
done
