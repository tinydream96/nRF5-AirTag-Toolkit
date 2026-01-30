# ⚡ 常用命令速查表 (Cheat Sheet)

本文档汇总了开发过程中最常用的诊断与操作命令。

## 🔌 1. 硬件连接检查

### 检查 USB 设备 (macOS)

确认电脑是否识别到调试器硬件。

```bash
# 列出所有 USB 设备，过滤 ST-Link 或 J-Link
system_profiler SPUSBDataType | grep -iE "st-link|stm|segger|j-link"
```

### 检查 J-Link 连接

如果使用 J-Link，使用此命令查看连接状态。

```bash
# 列出已连接的 J-Link 序列号
nrfjprog --ids

# 尝试读取特定的内存地址来确认芯片连接 (适用于 nRF52)
nrfjprog -f nrf52 --memrd 0x10000000 --n 4
```

### 检查 ST-Link (OpenOCD)

如果使用 ST-Link，尝试连接 OpenOCD 守护进程。

```bash
# 尝试连接 nRF52 芯片并立即退出 (用于测试)
openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; exit"
```

> **成功标志**: 输出中包含 `target halted due to debug-request` 或类似的成功日志。

---

## 🔍 2. 芯片操作与救砖

### 解除芯片保护 (Recover / Mass Erase)

当遇到 `APPROTECT` 或 `read protection` 错误时使用。

**J-Link 用户:**

```bash
# nRF52 系列
nrfjprog -f nrf52 --recover

# nRF51 系列
nrfjprog -f nrf51 --recover
```

**ST-Link 用户 (OpenOCD):**

```bash
# 一键执行 Mass Erase
openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; halt; nrf5 mass_erase; reset; exit"
```

### 软复位芯片

```bash
# J-Link
nrfjprog -f nrf52 --reset

# ST-Link
openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; reset; exit"
```

---

## 🛠 3. 环境与工具链验证

### 一键全环境检查

项目自带的脚本，最全面的检查方式。

```bash
./scripts/one_click_verify.sh
```

### 单独检查工具版本

```bash
# ARM GCC 编译器
arm-none-eabi-gcc --version

# Python 版本
python3 --version

# 检查 Python 依赖
pip3 show flask intelhex
```

---

## 📂 4. 常用文件路径

| 文件用途 | 相对路径 |
| :--- | :--- |
| **Web 启动脚本** | `nrf5_airtag_web.py` |
| **密钥文件** | `config/*_keyfile` 或 `user_sessions/*/raw_firmware.hex` |
| **编译输出目录** | `heystack-nrf5x/nrf52810/armgcc/_build/` |
| **nRF5 SDK** | `nrf-sdk/nRF5_SDK_15.3.0_59ac345/` |

---

> [!TIP]
> 记不住命令？直接使用 Web Studio (`python3 nrf5_airtag_web.py`)，它会自动在后台执行这些操作！
