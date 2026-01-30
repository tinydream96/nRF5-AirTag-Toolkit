# ⚡ 命令行刷写工具完全指南

基于 `nrf5_airtag_flash.sh` 脚本的高级刷写指南。

## 适用场景

- 批量生产（循环刷写多台设备）
- 无 GUI 环境（服务器/树莓派）
- 自动化脚本集成
- 调试特定芯片型号

---

## 快速开始

```bash
./nrf5_airtag_flash.sh
```

脚本会交互式引导您完成:

1. 选择芯片型号 (nRF51822 / nRF52832 / nRF52810)  
2. 选择密钥模式 (Dynamic / Static)
3. 选择调试器 (J-Link / ST-Link)
4. 配置设备参数

---

## 完整命令流程示例

### 场景：批量刷写（以 nRF52832 为例）

> 💡 以下流程适用于所有芯片型号（nRF51822/52832/52810/52811），仅参数略有不同。

```bash
$ ./nrf5_airtag_flash.sh

========================================
   nRF5 AirTag Flash Tool (Direct J-Link)
========================================

Select Chip Model:
 1. nRF51822 (S130)
 2. nRF52832 (S132)
 3. nRF52810 (S112)
Enter choice [1-3]: 2

-> Selected: nRF52832 (Offset: 0x26000)

Select Key Mode:
 1. [Dynamic] Infinite Keys (Generates Seed & Offline Keys)
 2. [Static]  Fixed Keys (Requires Keyfile)
Enter choice [1]: 1

-> Selected: Dynamic

Select Debugger:
 1. [J-Link] (Detected!) - Recommended
 2. [ST-Link] (OpenOCD)
Enter choice [1]: 1

-> Selected: J-Link

Device Name Prefix (e.g. MSF): TAG
Start Number (1-999): 1
Base Interval (ms) [Default 2000]: 2000
Flash SoftDevice? (y/N): y
Enable DCDC? (y/N) [N]: y
```

然后脚本会自动：

1. 生成第一台设备 `TAG001` 的种子
2. 编译固件并注入种子  
3. 刷写到芯片
4. 询问是否继续下一台 (`TAG002`, `TAG003`...)

---

## 高级参数说明

### 芯片特定配置

| 芯片 | SoftDevice | APP_OFFSET | 供电要求 |
|------|-----------|-----------|---------|
| nRF51822 | S130 v2.0.1 | 0x1B000 | 1.8-3.6V |
| nRF52832 | S132 v6.1.1 | 0x26000 | 1.7-3.6V |
| nRF52810 | S112 v6.1.1 | 0x19000 | 1.7-3.6V |

### 广播间隔计算

```bash
实际间隔 = BASE_INTERVAL + (DEVICE_NUMBER × 10)
```

示例：

- 设备1: 2000 + (1 × 10) = 2010 ms  
- 设备2: 2000 + (2 × 10) = 2020 ms
- ...

这样可以避免多设备同时广播造成干扰。

---

## Dynamic vs Static 模式详解

### Dynamic 模式

**生成内容**:

- `seeds/TAG001/seed_TAG001.hex`: 种子（Hex 文本）
- `seeds/TAG001/seed_TAG001.bin`: 种子（二进制）
- `config/TAG001_devices.json`: 离线密钥配置

**适用**: 长期追踪、隐私要求高

### Static 模式

**生成内容**:

- `config/TAG001_keyfile`: 200 个固定密钥
- `config/TAG001_devices.json`: Find My 配置文件

**适用**: 调试、兼容旧版 OpenHaystack

---

## 调试器选择策略

### J-Link (推荐)

**优点**:

- 速度最快（4000 kHz）
- 自动 Recover 保护芯片
- 支持 nrfjprog 和 JLinkExe 双路径

**缺点**:

- 硬件成本较高

### ST-Link

**优点**:

- 便宜、易获取
- OpenOCD 开源支持好

**缺点**:

- 速度较慢
- 不支持某些高级功能（如 CTRL-AP 访问）

---

## 批量生产模板脚本

```bash
#!/bin/bash
# 批量生产脚本示例

PREFIX="TAG"
START_NUM=1
END_NUM=50

for i in $(seq $START_NUM $END_NUM); do
    echo "============================================"
    echo " 刷写设备: ${PREFIX}$(printf \"%03d\" $i)"
    echo "============================================"
    
    # 自动应答脚本输入
    echo -e \"2\\n1\\n1\\n$PREFIX\\n$i\\n2000\\ny\\ny\\ny\" | ./nrf5_airtag_flash.sh
    
    echo "设备 ${PREFIX}$(printf \"%03d\" $i) 完成，请更换下一台设备"
    sleep 2
done
```

---

## 故障排查

### nrfjprog 连接失败

**现象**: `unable to connect to target`

**解决**:

```bash
# 尝试恢复
nrfjprog --recover -f nrf52

# 检查设备列表
nrfjprog --ids
```

### J-Link 驱动问题

**现象**: `JLinkExe: command not found`

**解决**:

```bash
# macOS
brew install --cask nordic-nrf-command-line-tools

# 验证
which JLinkExe
```

### OpenOCD Mass Erase 失败

**现象**: `mass_erase failed`

**解决**:

```bash
# 检查调试器连接
openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; targets; exit"

# 手动 Recover
openocd -f interface/stlink.cfg -f target/nrf52.cfg -c "init; halt; nrf5 mass_erase; reset; exit"
```

---

## 与 Web Studio 对比

| 特性 | CLI Tool | Web Studio |
|------|---------|-----------|
| **可视化** | ❌ | ✅ |
| **批量刷写** | ✅ | ⚠️ (需手动循环) |
| **自动检测** | ⚠️ (需手动选择) | ✅ |
| **跨平台** | macOS/Linux | 浏览器 |
| **脚本集成** | ✅ | ❌ |

---

> 相关文档:
>
> - [快速开始](../getting-started/index.md)
> - [批量生产指南](../advanced/production.md)
