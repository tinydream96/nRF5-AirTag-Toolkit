# 🛠️ 环境安装指南

本指南帮助您在 macOS/Linux 上安装所有必要的开发工具。

## 必装工具清单

### 1. Python 3 + Flask

Web Studio 依赖 Python 3.7+：

```bash
# 检查版本
python3 --version

# 安装依赖
pip3 install flask intelhex
```

### 2. ARM 交叉编译工具链

用于编译 nRF 固件：

```bash
# macOS
brew install --cask gcc-arm-embedded

# Linux (Ubuntu/Debian)
sudo apt-get install gcc-arm-none-eabi

# 验证
arm-none-eabi-gcc --version
```

### 3. 调试器驱动

根据您的硬件选择：

#### J-Link (推荐)

```bash
# macOS
brew install --cask nordic-nrf-command-line-tools

# 包含：nrfjprog, mergehex, JLinkExe
```

#### ST-Link

```bash
# macOS/Linux
brew install openocd
```

#### DAPLink / CMSIS-DAP

```bash
# 通常使用 OpenOCD
brew install openocd
```

---

## nRF5 SDK 配置

### 自动配置（推荐）

运行项目提供的脚本：

```bash
chmod +x setup_sdk.sh
./setup_sdk.sh
```

脚本会引导您：

1. 下载对应版本的 SDK
2. 解压到 `nrf-sdk/` 目录
3. 验证路径正确性

### 手动配置

如果自动脚本失败：

1. **下载 SDK**:
   - nRF51 系列: [SDK 12.3.0](https://www.nordicsemi.com/Software-and-Tools/Software/nRF5-SDK/Download)
   - nRF52 系列: [SDK 15.3.0](https://www.nordicsemi.com/Software-and-Tools/Software/nRF5-SDK/Download)

2. **解压到项目目录**:

   ```
   nRF5-AirTag-Toolkit/
   └── nrf-sdk/
       ├── nRF5_SDK_12.3.0_d7731ad/  (for nRF51)
       └── nRF5_SDK_15.3.0_59ac345/  (for nRF52)
   ```

---

## 验证安装

运行以下命令确认所有工具就绪：

```bash
# 1. Python 环境
python3 -c "import flask; print('Flask OK')"

# 2. ARM 工具链
arm-none-eabi-gcc --version

# 3. 调试工具 (J-Link)
nrfjprog --version
JLinkExe -CommanderScript

# 或 OpenOCD (ST-Link)
openocd --version
```

---

## Windows 用户

虽然主要支持 macOS/Linux，但 Windows 用户可以通过以下方式使用：

1. **WSL2** (推荐): 在 WSL 中按 Linux 指南安装
2. **Git Bash + MSYS2**: 手动配置路径
3. **Docker**: 使用容器化环境（高级）

---

## 常见问题

### Q: `arm-none-eabi-gcc: command not found`

**A**: 确保工具链安装成功，并检查 PATH 环境变量。

### Q: SDK 下载太慢

**A**: 可以使用国内镜像或离线包。

### Q: nrfjprog 无法识别设备

**A**:

1. 检查 J-Link 驱动是否安装
2. 确认硬件连接（参考[硬件连接手册](../hardware/connection.md)）
3. 尝试运行 `nrfjprog --ids` 查看设备列表

---

> 下一步：[快速开始](./index.md) 或 [硬件连接手册](../hardware/connection.md)
