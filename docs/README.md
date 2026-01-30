# 📖 文档导航

欢迎来到 **nRF5-AirTag-Toolkit** 文档中心！本项目提供了业界最优雅的 nRF 芯片刷写体验。

---

## 🚀 快速开始（新手必读）

### [01-快速开始](./getting-started/index.md)

**5 分钟上手** | 推荐指数: ⭐⭐⭐⭐⭐

适用人群：首次使用者、想快速体验 Web Studio 的用户

**内容概览**：

- Web Studio 启动与使用
- 硬件连接速查
- Dynamic vs Static 模式选择
- 常见问题速查

---

### [02-环境安装](./getting-started/environment.md)

**工具链配置** | 预计时间: 30-60 分钟

适用人群：首次搭建开发环境的用户

**内容概览**：

- Python + Flask 环境
- ARM GCC 工具链安装
- 调试器驱动（J-Link / ST-Link / DAPLink）
- nRF5 SDK 配置
- 安装验证清单

---

## 📖 深入指南（掌握全部功能）

### ⚡ 快速查阅

- **[常用命令速查表 (Cheat Sheet)](reference/cheat-sheet.md)** - 救砖、连接检查、环境验证
- **[Web Studio 指南](manuals/web-studio.md)** - 图形化工具使用手册

**Web 界面详解** | 推荐指数: ⭐⭐⭐⭐

适用人群：想深入了解 Web Studio 的用户

**内容概览**：

- 自动检测机制
- 密钥模式详解（Dynamic / Static）
- 批量刷写模式
- 离线固件包使用
- 故障诊断技巧

---

### [04-命令行刷写工具](./manuals/cli-tool.md)

**CLI 工具完全指南** | 推荐指数: ⭐⭐⭐⭐

适用人群：批量生产、无 GUI 环境、自动化脚本需求

**内容概览**：

- `nrf5_airtag_flash.sh` 交互流程
- 批量刷写脚本模板
- 调试器选择策略
- 芯片特定配置
- 与 Web Studio 对比

---

### [05-硬件连接手册](./hardware/connection.md)

**接线图 & 救砖指南** | 推荐指数: ⭐⭐⭐⭐⭐

适用人群：遇到连接问题、芯片保护、接线不确定的用户

**内容概览**：

- 调试器选择建议
- 常见模块接线图（nRF51822 / 52832 等）
- 芯片保护解除（Mass Erase）
- 接线禁忌与故障排查

---

## 🔬 高级主题（探索技术原理）

### [06-动态密钥技术详解](./advanced/dynamic-keys.md)

**核心技术白皮书** | 推荐指数: ⭐⭐⭐⭐

适用人群：想了解 Dynamic Mode 原理、密钥管理的用户

**内容概览**：

- Seed-Based Derivation 算法
- Static vs Dynamic 模式对比
- 断电影响分析
- 离线推演机制
- 最佳实践建议

---

### [07-批量生产指南](./advanced/production.md)

**工业级自动化** | 推荐指数: ⭐⭐⭐

适用人群：批量生产、自动化生产线需求

**内容概览**：

- 三种生产方案对比
- 全自动化脚本模板
- Pogo Pin 夹具方案
- 密钥管理最佳实践
- 质量控制流程
- 交付清单

---

## 🗂️ 旧版文档归档

如果您在寻找旧版文档（如 01-17 编号的过时文档），请查看：
📁 [archive 目录](./archive/)

> ⚠️ **注意**: Archive 中的文档基于旧的命令行流程，大部分内容已过时。仅作参考或特殊情况查阅。

---

## 📚 文档路线图

### 路线 A：新手快速上手

```
01-快速开始 → 02-环境安装 → 05-硬件连接手册（如遇问题）
```

### 路线 B：深度玩家

```
01-快速开始 → 03-Web-Studio-完全指南 → 06-动态密钥技术详解
```

### 路线 C：批量生产

```
02-环境安装 → 04-命令行刷写工具 → 07-批量生产指南
```

---

## 🆘 获取帮助

- **硬件连接**: [Connection Guide](hardware/connection.md)
- **常用命令**: [Cheat Sheet](reference/cheat-sheet.md) ⚡
- **芯片保护/救砖**: [05-硬件连接手册 - 芯片保护解除](./hardware/connection.md#4-芯片保护解除救砖)
- **Dynamic 模式困惑**: [06-动态密钥技术详解](./advanced/dynamic-keys.md)
- **Web Studio 报错**: [03-Web-Studio-完全指南 - 故障诊断](./manuals/web-studio.md#故障诊断)

---

**更新日期**: 2026-01-29  
**文档版本**: v2.1 (目录重构)
