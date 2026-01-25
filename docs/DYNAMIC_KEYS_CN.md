# 动态密钥固件构建指南 (Dynamic Key Generation Guide)

本指南介绍如何在 nRF52 (nRF52832/nRF52810) 上使用基于 ECC P-224 的动态密钥生成功能。

## 1. 简介

原版 OpenHaystack 使用静态固定密钥列表。本修改引入了类似 AirTag 的动态生成机制：

- **算法**: NIST P-224 (secp224r1)
- **机制**: SHA256(种子 + 时间计数器) -> 私钥 -> 公钥
- **优势**: 无限密钥，无需定期重新刷写固件。

## 2. 准备工作

### 2.1 环境要求

确保你已经安装了 `gcc-arm-none-eabi` 和 `nrf-command-line-tools` (nrfjprog)。

### 2.2 生成主种子 (Master Seed)

你需要生成一个唯一的 32 字节随机种子。我们提供了一个 Python 脚本来完成此操作。

运行脚本：

```bash
pip3 install cryptography
python3 heystack-nrf5x/tools/generate_seed.py
```

脚本会输出类似如下的内容：

```c
[Generated Master Seed]
C Array:
{
    0xa1, 0xb2, ... 
    ...
};
```

### 2.3 配置固件

脚本 `generate_seed.py` 现在支持自动更新 `main.c` 文件。

运行脚本时，它不仅会打印生成的密钥，还会自动查找并替换 `heystack-nrf5x/main.c` 中的 `m_master_key_seed`。

```bash
python3 heystack-nrf5x/tools/generate_seed.py
```

观察终端输出，如果看到 `Successfully updated m_master_key_seed in main.c`，说明配置已完成。无需手动复制粘贴。

## 3. 编译与烧录

### 3.1 编译

进入对应芯片的目录进行编译。

**对于 nRF52832:**

```bash
cd heystack-nrf5x/nrf52832/armgcc
make
```

**对于 nRF52810:**

```bash
cd heystack-nrf5x/nrf52810/armgcc
make
```

### 3.2 烧录

连接你的 J-Link，执行：

```bash
make flash
```

或者使用我们专门为动态固件准备的脚本（无需手动 Keyfile）：

```bash
./n52832autoflash_dynamic.sh
```

**注意**：旧的 `n52832autoflash_jlink.sh` 是用于静态密钥注入的，不适用于此动态固件。请使用带 `_dynamic` 后缀的新脚本。

## 4. 验证与数据获取

### 4.1 验证广播

1. 烧录完成后，设备将立即开始广播。
2. 设备每次重启计数器归零，所以你会先看到 Key #0。

### 4.2 获取 FindMy 数据

要从苹果网络获取位置数据，你需要生成特定时间段的密钥列表。

**方式 A: 标准列表 (推荐)**

```bash
python3 heystack-nrf5x/tools/export_keys.py
```

**方式 B: 兼容 Macless-Haystack JSON (如果你使用现有的 Fetcher)**

```bash
python3 heystack-nrf5x/tools/export_keys.py --macless-json --device-name "MyTag" > my_keys.json
```

此命令会生成一个可以直接喂给 fetcher 使用的 JSON 文件（包含 `additionalKeys` 数组）。

输出说明：

- **Public Key**: 对应 OpenHaystack 的 "Advertisement Key"。
- **Hashed Adv Key**: 用于向苹果服务器查询 रिपोर्ट (Reports)。通常你需要上传这个哈希值的 Base64。
- **Private Key**: (JSON模式中可见) 用于解密下载到的报告。

**注意**:
由于此固件没有 RTC (实时时钟)，**每次断电重启后计数器都会重置为 0**。因此，查询时主要关注 Key 0, 1, 2... 等，取决于设备运行了多久。

## 5. 常见问题

- **无法连接 J-Link / nrfjprog 报错**:
  如果遇到 `Error -102` 或 `Failed to read device memories`，请使用我们新提供的**Direct J-Link 脚本**，它绕过了 `nrfjprog` 直接与硬件通信：

  ```bash
  chmod +x n52832autoflash_dynamic_direct.sh
  ./n52832autoflash_dynamic_direct.sh
  ```

  该脚本会自动处理解锁和刷写流程。

- **功耗**: 每次密钥轮换（每15分钟）会进行一次 ECC 计算，耗时约 100-200ms，对电池寿命影响极小。

- **广播频率**: 默认广播间隔为 **1000ms (1秒)**。这是由 `ble_stack.h` 定义的。

- **MAC 地址**: 是的，设备的蓝牙 MAC 地址会根据当前的 Public Key 自动变化。具体逻辑是取 Public Key 的前 6 个字节，并将高两位设置为 `11` (Random Static Address)，这完全符合苹果 FindMy 的隐私协议。所以你在扫描软件中看到的 MAC 地址和 Public Key 数据是对应的。
