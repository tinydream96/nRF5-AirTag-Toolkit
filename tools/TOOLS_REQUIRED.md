# 必需工具清单

## 自动安装 (推荐)
```bash
# 运行一键安装脚本
./scripts/one_click_install.sh

# 验证安装
./scripts/one_click_verify.sh
```

## 手动安装

### Homebrew 安装的工具
```bash
brew install --cask gcc-arm-embedded
brew install openocd
brew install libusb
brew install --cask nordic-nrf-command-line-tools
brew install git python3
```

### Python 包
```bash
pip3 install intelhex
```

### 手动下载
- nRF5 SDK 15.3.0: https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK

## 验证安装
```bash
./scripts/one_click_verify.sh
```
