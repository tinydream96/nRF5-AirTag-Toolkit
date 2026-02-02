# 🏷️ nRF5-AirTag-Toolkit

> [🇺🇸 English](./README.md) | **[🇨🇳 中文](./README_zh.md)**

<p align="center">
  <br><b>Infinity Tag 的大本营。</b><br>
  目前最强大、最优雅、且唯一具备“零门槛”体验的 Apple Find My 网络固件部署方案。
</p>

# 💎 隆重介绍：Infinity Tag (终极形态)

**nRF5-AirTag-Toolkit** 为您带来追踪技术的下一次进化：**Infinity Tag**。
如果您厌倦了因固定密钥轮换导致的“僵尸设备”问题，这就是您一直在等待的革命。

### 1. ♾️ 旗舰功能：Infinity Tag (无限动态密钥)

<p align="center">
  <video src="docs/images/web_studio_demo.mov" width="800" controls muted autoplay loop style="border-radius: 12px; box-shadow: 0 20px 50px rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1);">
    您的浏览器不支持 HTML5 视频播放。
  </video>
</p>

传统的 "Standard Tag" (Standard Mode/Static Mode) 只能循环使用固定的 200 个密钥。一旦耗尽或被识别，它们就会被苹果的反追踪网络标记，导致位置更新稀疏。

**Infinity Tag 的压倒性优势：**

* **绝对隐私：** 采用 **Dynamic Seed** 技术实时生成密钥。
* **无限寿命：** 密钥永不重复。永远。
* **影院级追踪：** 丝滑流畅、无断点的轨迹记录，完美复刻原生 AirTag 体验。

> **注意：** 为了保持兼容性，我们依然支持 **Standard Tag** 模式，但 Infinity Tag 才是未来。

### 2. 🖥️ 苹果级交互：Web Studio 2.0

告别枯燥的黑窗口。我们打造了一个拥有极致工业美感的 Web 智控中心：

* **玻璃拟态设计（Glassmorphism）：** 与 macOS 审美完美统一。
* **智能感知系统：** 即插即用！硬件类型（J-Link/ST-Link）、芯片型号（51822/52832/5281x）全自动识别，无需手动选择。
* **动态校准：** 即使你选错了型号，系统也会在刷写瞬间自动纠正。

### 3. 🐣 小白零压力：真正的“保姆级”自动化

不管你懂不懂代码，只需三步：

1. **运行程序**
2. **点击“开始刷写”**
3. **点亮 AirTag！**
所有复杂的 SDK 配置、补丁合并、十六进制转换，全部由后台自动化管家完成。

---

# ✨ 核心特性

| 特性 | 详情 | 优势 |
| :--- | :--- | :--- |
| **智能解密** | 自动检测 `Device Security` | **救砖神器**，二手的、锁死的芯片一键“洗白” |
| **全系兼容** | 支持 nRF51 / nRF52 全家桶 | 一套工具，适配市场上 99% 的常见模块 |
| **双语日志** | 实时输出中英双语诊断信息 | 刷写过程透明化，排障不再像开盲盒 |
| **一键交付** | 核心密钥文件打包下载 | 刷完即得，直接在 OpenHaystack/FindMy 中使用 |

---

# 🚀 5 分钟上手

> [!TIP]
> **准备工作：** 确保你的驱动已安装，且设备通过调试器连接到电脑。

### 第一步：启动引擎

在终端输入一行命令即可启动 Web 控制台：

```bash
python3 nrf5_airtag_web.py
```

### 第二步：进入智控中心

浏览器访问: `http://127.0.0.1:52810`

### 第三步：见证奇迹

点击蓝色的 **「开始刷写」** 按钮。
你会看到顶部的进度条优雅地跳动，系统会自动识别你的调试器、检测芯片并注入无限密钥。

---

# 📘 文档与支持

> [!IMPORTANT]
> 虽然这个工具已经极度简化，但我们依然提供了一套完整的知识库。

**🚀 快速开始**

* [5 分钟快速开始](docs/getting-started/index.md) - 使用 Web Studio 立即上手  
* [环境安装](docs/getting-started/environment.md) - 安装工具链、SDK 和驱动

**📖 深入指南**

* [Web Studio 完全指南](docs/manuals/web-studio.md) - 掌握 Web 界面所有功能
* [命令行刷写工具](docs/manuals/cli-tool.md) - 高级用户的命令行工具
* [硬件连接手册](docs/hardware/connection.md) - 接线图与芯片救砖

**🔬 高级主题**

* [动态密钥技术详解](docs/advanced/dynamic-keys.md) - 技术原理深度解析
* [批量生产指南](docs/advanced/production.md) - 大规模生产工作流

---

# 📂 架构一览

```text
.
├── nrf5_airtag_web.py      # 🖥️ 核心：Web Studio 全自动化大脑
├── templates/              # 🎨 灵魂：极致美学的 UI 交互层
├── scripts/                # 🛠️ 骨架：高效的底层驱动逻辑
├── heystack-nrf5x/         # 🧠 基因：深度优化的固件源码
└── docs/                   # 📚 财富：价值百万的实操干货
```

---

# 🤝 开源致谢与免责

本项目站在巨人的肩膀上，感谢 [OpenHaystack](https://github.com/seemoo-lab/openhaystack) 的卓越工作。

**⚠️ 注意：**

* 本项目致力于技术研究，请勿用于非法追踪。
* AirTag 与 Find My 是 Apple Inc. 的注册商标。
* 本项目是社区驱动的开源实践，与 Apple Inc. 无官方关联。

---

<p align="center">
  <i>用代码，定义属于你的数字领地。</i><br>
  <b>Made with ❤️ by the Global Open Source Community</b>
</p>
