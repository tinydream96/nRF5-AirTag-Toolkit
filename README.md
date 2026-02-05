# 🏷️ nRF5-AirTag-Toolkit

> **[🇺🇸 English](./README.md)** | [🇨🇳 中文](./README_zh.md)

<p align="center">
  <br><b>Home of the Infinity Tag.</b><br>
  The most powerful, elegant, and only "Zero-Configuration" firmware deployment toolkit for the Apple Find My network.
</p>

# 💎 Introducing: Infinity Tag

**nRF5-AirTag-Toolkit** brings you the next evolution of tracking technology: the **Infinity Tag**.
If you're tired of "Zombie Devices" caused by fixed key rotation, this is the revolution you've been waiting for.

### 1. ♾️ The Flagship: Infinity Tag (Infinite Dynamic Keys)

<p align="center">
  <video src="docs/images/web_studio_demo.mov" width="800" controls muted autoplay loop style="border-radius: 12px; box-shadow: 0 20px 50px rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1);">
    Your browser does not support HTML5 video.
  </video>
</p>

Conventional "Standard Tags" (Static Mode) recycle a fixed set of ~200 keys. Once exhausted or recognized, they can be flagged by Apple's anti-tracking network, resulting in sparse updates.

**The Infinity Tag Advantage:**

* **True Privacy:** Uses **Dynamic Seed** technology to generate keys on-the-fly.
* **Infinite Lifespan:** Keys never repeat. Period.
* **Cinema-Grade Tracking:** Smooth, gapless location history that rivals the original AirTag.

> **Note:** We still support **Standard Tag** mode for legacy compatibility, but Infinity Tag is the future.

### 2. 🖥️ Apple-Grade Experience: Web Studio 2.0

Say goodbye to the terminal. We've built a Web Control Center with extreme industrial aesthetics:

* **Glassmorphism UI:** Perfectly aligned with macOS design principles.
* **Intelligent Sensing:** Plug and play! Hardware types (J-Link/ST-Link) and chip models (51822/52832/5281x) are automatically detected.
* **Dynamic Calibration:** Even if you select the wrong model, the system auto-corrects it during the flashing process.

### 3. 🐣 Zero Friction: True "Nanny-State" Automation

Whether you're an expert or a total beginner, it's just three steps:

1. **Launch the tool**
2. **Click "Start Flashing"**
3. **Light up your AirTag!**
All complex SDK configurations, patch merging, and hex conversions are handled by your automated background manager.

---

# ✨ Core Features

| Feature | Details | Advantage |
| :--- | :--- | :--- |
| **Smart Decryption** | Auto-detects `Device Security` | **The ultimate unbricker**—instantly "cleanse" locked or production chips. |
| **All-Series Support** | Native support for nRF51 / nRF52 | One tool for 99% of common modules on the market. |
| **Bilingual Logs** | Real-time English/Chinese diagnostics | Transparent process—no more guesswork or "black box" flashing. |
| **Instant Delivery** | One-click key package download | Flash and go—immediately compatible with OpenHaystack/FindMy. |

---

# 🚀 5-Minute Setup

> [!TIP]
> **Prerequisites:** Ensure your drivers are installed and your device is connected via a debugger.

> [!WARNING]
> **J-Link Compatibility:** Older J-Link clones (e.g., "ARM-OB STM32" from ~2012) may fail to unlock/recover chips with Readback Protection. If `nrfjprog --recover` times out or OpenOCD reports "cannot read IDR", use a genuine Segger J-Link or a newer, high-quality clone.

### Step 1: Fire up the Engine

Run a single command to start the Web Studio:

```bash
python3 nrf5_airtag_web.py
```

### Step 2: Enter the Control Center

Navigate to: `http://127.0.0.1:52810`

### Step 3: Witness the Magic

Click the blue **"START FLASHING"** button.
Watch the elegant progress bar—system detection, firmware patching, and key injection happen in seconds.

---

# 📘 Documentation & Support

> [!IMPORTANT]
> Although this tool is extremely simplified, we still provide a comprehensive knowledge base.

**🚀 Quick Start**

* [5-Min Quick Start](docs/getting-started/index.md) - Get started with Web Studio immediately
* [Environment Setup](docs/getting-started/environment.md) - Install toolchain, SDK and drivers

**📖 In-Depth Guides**

* [Web Studio Guide](docs/manuals/web-studio.md) - Master all Web interface features
* [CLI Flash Tool](docs/manuals/cli-tool.md) - Command line tool for advanced users
* [Hardware Connection](docs/hardware/connection.md) - Wiring diagrams and unbricking

**🔬 Advanced Topics**

* [Dynamic Keys Tech](docs/advanced/dynamic-keys.md) - Deep dive into technical principles
* [Mass Production](docs/advanced/production.md) - Large scale production workflows

---

# 📂 Architecture at a Glance

```text
.
├── nrf5_airtag_web.py      # 🖥️ Core: The automated brain of Web Studio
├── templates/              # 🎨 Soul: The high-aesthetic UI layer
├── scripts/                # 🛠️ Skeleton: Efficient low-level driver logic
├── heystack-nrf5x/         # 🧠 Gene: Deeply optimized firmware source
└── docs/                   # 📚 Wealth: Million-dollar practical documentation
```

---

# 🤝 Acknowledgements & Disclaimer

Built on the shoulders of giants. Special thanks to [OpenHaystack](https://github.com/seemoo-lab/openhaystack) for their pioneering work.

**⚠️ Disclaimer:**

* This project is for educational and research purposes only.
* Do not use this project for illegal tracking.
* AirTag and Find My are trademarks of Apple Inc.
* This project is not affiliated with Apple Inc.

---

<p align="center">
  <i>Define your digital territory with code.</i><br>
  <b>Made with ❤️ by the Global Open Source Community</b>
</p>
