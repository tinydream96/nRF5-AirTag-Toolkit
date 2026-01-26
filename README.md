# 🏷️ nRF5-AirTag-Toolkit

> **打造属于你自己的 AirTag —— 基于 Apple Find My 网络的极致开源工具箱**
>
> *让每一块 nRF5 芯片都能被全世界的 iPhone 守护。*

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Hardware](https://img.shields.io/badge/hardware-nRF52810%20|%20nRF52832-blue)
![Debugger](https://img.shields.io/badge/debugger-JLink%20|%20STLink-orange)

---

## 📖 简介 (Introduction)

**nRF5-AirTag-Toolkit** 是目前最完善、最“保姆级”的第三方 Find My 网络固件部署方案。

它是为了解决开源社区中“刷机难、配置烦、密钥乱”的痛点而诞生的。无论你是拥有 **J-Link** 还是廉价的 **ST-Link**，无论你是资深嵌入式工程师还是没有任何代码基础的小白，这个工具箱都能让你在 5 分钟内点亮你的设备。

### ✨ 核心创新 (Core Innovations)

#### 1. ♾️ 无限动态密钥 (Infinite Dynamic Keys) —— **本项目最大亮点**

传统开源固件仅支持 "Static Mode" (固定密钥)，只能存储约 200 个密钥并循环使用，容易被追踪指纹，且隐私性较差。**更有甚者，Apple 设备一旦检测到密钥重复使用，可能会拒绝上报位置，导致追踪轨迹点越来越稀疏。本项目彻底解决了这一痛点。**

**本项目首创 "Dynamic Seed" 技术：**

* **原理**：设备仅存储一个随机种子 (Seed)，通过 SHA256 算法实时计算未来的密钥。
* **效果**：**密钥永不重复，无限生成。**
* **隐私**：极高的抗追踪能力，达到 AirTag 原生级别的隐私标准。

👉 **[深度解析：无限动态密钥技术详解](docs/16-Dynamic_Keys_技术详解.md)**

#### 2. ⚡️ 极速自动化 (Zero-Friction Flashing)

* **[新] 全系芯片支持**: 一个脚本统一支持 nRF51822 / nRF52832 / nRF52810。
* **[新] 智能回退机制**: J-Link 模式优先尝试标准方式，失败自动切换 Direct Mode，完美适配 macOS。
* 自动处理 SoftDevice 协议栈合并与固件补丁。

#### 3. 🖥️ Web Studio 智控中心 (Recommended)

* **颜值巅峰**：玻璃拟态设计，极致的工业美感与交互体验。
* **全自动流程**：支持硬件自动识别（即插即用）、自动递增 ID、一键下载密钥包。
* **实时监控**：刷写日志实时回传，所见即所得。

<p align="center"><img src="docs/images/web_studio_ui.png" width="800" alt="Web Studio UI"></p>

#### 4. 🛡️ 救砖黑科技 (Anti-Brick Guard)

* 内置芯片解锁机制，自动检测 `Device is secured` 并执行 Mass Erase 解锁。
* 这意味着你可以直接购买**拆机芯片**或**量产锁死**的模块，工具自动帮你“洗白”成全新的开发板。

---

## 🚀 快速开始 (Quick Start)

我们为不同基础的用户准备了不同的入口：

### 方案 A：Web Studio (推荐)

最直观的可视化操作，支持全系芯片。

```bash
python3 nrf5_airtag_web.py
```

浏览器打开: <http://127.0.0.1:5001>

### 方案 B：终端脚本 (Terminal)

适合生产线或纯命令行环境。

```bash
./nrf5_airtag_flash.sh
```

### 📘 文档导航

* **小白入门**:
  * [nRF51822 统一刷写指南](docs/14-nRF51822_统一刷写工具指南.md) (核心文档)
  * [nRF52832 刷机保姆级教程](docs/10-nRF52832刷机保姆级教程.md)
* **进阶技巧**:
  * [常见开发板接线图集](docs/17-常见开发板接线图集.md) (**New!** 含接线图)
  * [J-Link 芯片解锁指南](docs/14-nRF51822_统一刷写工具指南.md#4-常见问题-faq)
  * [完整文档列表](docs/README-文档导航.md)

---

## 🗺️ 未来路线图 (Roadmap)

我们正在构建更宏大的未来，让 Find My 开发变得像安装 App 一样简单。

* [x] **🖥️ 跨平台 GUI 客户端 (Web Studio)**
  * **全新推出**: 基于 Web 技术的 Studio 控制台，支持 macOS/Linux。
  * **自动化体验**: 鼠标点一点，固件自动补丁、编译、刷写全流程。

* [ ] **🪟 Windows 平台原生支持**
  * 当前脚本基于 Bash (macOS/Linux)。
  * 未来将移植 PowerShell 版本，让 Windows 用户不仅能在 WSL 里跑，还能直接原生运行。

* [x] **♾️ 全系 nRF 芯片支持**
  * [x] nRF52810 (已支持)
  * [x] nRF52832 (已支持)
  * [x] nRF51822 (已支持)
  * [ ] **nRF52840**: 支持 USB Dongle 形态。

---

## 📂 目录结构

```text
.
├── config/                 # [隐私] 存放生成的专属密钥和日志 (Git已忽略)
├── docs/                   # 📚 价值百万的文档库
├── heystack-nrf5x/         # 核心固件源码 (基于 OpenHaystack)
├── nrf5_airtag_flash.sh    # ⚡️ 统一命令行刷写工具
├── nrf5_airtag_web.py      # 🖥️ Web Studio 后端
├── scripts/                # 辅助工具脚本
└── README.md
```

---

## 🤝 致谢 (Acknowledgements)

本项目核心固件基于优秀的开源项目二次开发，特此感谢：

* **[heystack-nrf5x](https://github.com/pix/heystack-nrf5x)**: 本项目的固件核心，基于 acalatrava 的工作进行了 nRF5 适配。
* **[OpenHaystack](https://github.com/seemoo-lab/openhaystack)**: 逆向工程 Find My 网络的先驱，没有他们就没有这一切。

---

## ⚠️ 免责声明

本项目仅供教育和研究使用。

* 请勿将本项目用于非法追踪他人。
* AirTag 和 Find My 是 Apple Inc. 的商标。
* 本项目与 Apple Inc. 无任何关联。

---

*Made with ❤️ by Open Source Community*
