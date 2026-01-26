# 🏷️ nRF5-AirTag-Toolkit

> **[🇺🇸 English](./README.md)** | [🇨🇳 中文](./README_zh.md)

> **Build Your Own AirTag —— The Ultimate Open Source Toolkit based on Apple Find My Network**
>
> *Let every nRF5 chip be guarded by iPhones worldwide.*

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Hardware](https://img.shields.io/badge/hardware-nRF52810%20|%20nRF52832-blue)
![Debugger](https://img.shields.io/badge/debugger-JLink%20|%20STLink-orange)

---

## 📖 Introduction

**nRF5-AirTag-Toolkit** is the most complete and "worry-free" third-party Find My network firmware deployment solution available.

It was born to solve the pain points of "difficult flashing, annoying configuration, and messy keys" in the open source community. Whether you have a **J-Link** or a cheap **ST-Link**, whether you are a senior embedded engineer or a complete beginner with no coding experience, this toolkit allows you to light up your device in 5 minutes.

### ✨ Core Innovations

#### 1. ♾️ Infinite Dynamic Keys —— **The Highlight**

Traditional open source firmware only supports "Static Mode" (fixed keys), which can only store about 200 keys and cycle through them, making them easy to fingerprint and poor in privacy. **Even worse, once Apple devices detect key reuse, they may refuse to report location, resulting in sparse tracking points. This project completely solves this pain point.**

**This project pioneers "Dynamic Seed" technology:**

* **Principle**: The device only stores a random seed (Seed), and calculates future keys in real-time via SHA256 algorithm.
* **Effect**: **Keys never repeat, generated infinitely.**
* **Privacy**: Extremely high anti-tracking capability, reaching AirTag native privacy standards.

👉 **[Deep Dive: Infinite Dynamic Keys Technology](docs/16-Dynamic_Keys_技术详解.md)**

#### 2. ⚡️ Zero-Friction Flashing

* **[NEW] All Series Support**: One script unifies support for nRF51822 / nRF52832 / nRF52810.
* **[NEW] Smart Fallback**: J-Link mode tries standard method first, fails over to Direct Mode automatically, perfect for macOS.
* Automatically handles SoftDevice stack merging and firmware patching.

#### 3. 🖥️ Web Studio (Recommended)

* **Peak Aesthetics**: Glassmorphism design, ultimate industrial beauty and interaction experience.
* **Fully Automatic**: Supports hardware auto-detection (plug and play), auto-increment ID, one-click key package download.
* **Real-time Monitoring**: Flashing logs returned in real-time, WYSIWYG.

<p align="center"><img src="docs/images/web_studio_ui.png" width="800" alt="Web Studio UI"></p>

#### 4. 🛡️ Anti-Brick Guard

* Built-in chip unlock mechanism, automatically detects `Device is secured` and performs Mass Erase unlock.
* This means you can buy **salvaged chips** or **locked production modules**, and the tool automatically "washes" them into brand new dev boards.

---

## 🚀 Quick Start

We have prepared different entry points for users with different backgrounds:

### Option A: Web Studio (Recommended)

The most intuitive visual operation, supporting all series.

```bash
python3 nrf5_airtag_web.py
```

Open in browser: <http://127.0.0.1:5001>

### Option B: Terminal Script

Suitable for production lines or pure command line environments.

```bash
./nrf5_airtag_flash.sh
```

### 📘 Documentation Navigation

* **Beginner**:
  * [nRF51822 Unified Flashing Guide](docs/14-nRF51822_统一刷写工具指南.md) (Core Doc)
  * [nRF52832 Flashing Guide](docs/10-nRF52832刷机保姆级教程.md)
* **Advanced**:
  * [Common Board Pinouts](docs/17-常见开发板接线图集.md) (**New!** Includes wiring diagrams)
  * [J-Link Chip Unlock Guide](docs/14-nRF51822_统一刷写工具指南.md#4-常见问题-faq)
  * [Full Documentation List](docs/README-文档导航.md)

---

## 🗺️ Roadmap

We are building a grander future to make Find My development as simple as installing an App.

* [x] **🖥️ Cross-Platform GUI Client (Web Studio)**
  * **New Launch**: Web-based Studio console, supports macOS/Linux.
  * **Automation**: Just click, and firmware patching, compilation, and flashing are done automatically.

* [ ] **🪟 Windows Native Support**
  * Current scripts are based on Bash (macOS/Linux).
  * Future port to PowerShell, allowing Windows users to run natively without WSL.

* [x] **♾️ All nRF Series Support**
  * [x] nRF52810 (Supported)
  * [x] nRF52832 (Supported)
  * [x] nRF51822 (Supported)
  * [ ] **nRF52840**: Support USB Dongle form factor.

---

## 📂 Directory Structure

```text
.
├── config/                 # [Privacy] Stores generated exclusive keys and logs (Git ignored)
├── docs/                   # 📚 The Million Dollar Library
├── heystack-nrf5x/         # Core firmware source (Based on OpenHaystack)
├── nrf5_airtag_flash.sh    # ⚡️ Unified command line flashing tool
├── nrf5_airtag_web.py      # 🖥️ Web Studio Backend
├── scripts/                # Helper scripts
└── README.md
```

---

## 🤝 Acknowledgements

The core firmware of this project is based on secondary development of excellent open source projects, special thanks to:

* **[heystack-nrf5x](https://github.com/pix/heystack-nrf5x)**: The firmware core of this project, nRF5 adaptation based on acalatrava's work.
* **[OpenHaystack](https://github.com/seemoo-lab/openhaystack)**: Pioneer of reverse engineering Find My network, none of this would be possible without them.

---

## ⚠️ Disclaimer

This project is for education and research purposes only.

* Do not use this project to illegally track others.
* AirTag and Find My are trademarks of Apple Inc.
* This project is not affiliated with Apple Inc. in any way.

---

*Made with ❤️ by Open Source Community*
