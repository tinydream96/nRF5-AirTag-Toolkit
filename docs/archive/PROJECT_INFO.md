# nRF52810 AirTag 开发工具包

## 项目信息
- 项目名称: nRF52810-AirTag-Toolkit
- 创建时间: 2025年07月20日 11:19:47
- 版本: v1.0
- 适用系统: macOS (Intel & Apple Silicon)
- 目标芯片: nRF52810

## 快速开始
1. 运行环境检查: `./scripts/one_click_verify.sh`
2. 连接硬件后刷写: `./scripts/compile_and_flash_2s.sh`

## 目录结构
- docs/: 完整文档系统
- scripts/: 自动化脚本
- config/: 配置和密钥文件
- firmware/: 固件文件
- heystack-nrf5x/: 项目源码
- tools/: 工具说明

## 注意事项
- 需要手动下载 nRF5 SDK 15.3.0
- 确保已安装必要的开发工具
- 密钥文件需要妥善保管
