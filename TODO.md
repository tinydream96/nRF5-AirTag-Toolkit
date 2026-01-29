# 项目待办事项 (TODO)

- [ ] **优化发射功率配置**
  - 目前默认为 +4dBm。
  - 计划增加选项或文档说明，允许用户调整功率：
    - **+8 dBm**: 极限覆盖 (>100m)，适合户外追踪。
    - **0 dBm / -4 dBm**: 均衡模式，省电且覆盖室内 (~20-40m)，理论续航可提升 30%~60%。
    - **-20 dBm**: 防离身模式 (<5m)。
  - 需要修改 `heystack-nrf5x/ble_stack.c` 中的 `ble_set_max_tx_power` 函数。

- [ ] **调研手机控制功能 (双向连接)**
  - 目标：实现手机控制设备响铃或修改参数。
  - 难度：**中等偏难**。
  - 阻碍：
    - 需将 `Non-Connectable` (广播模式) 改为 `Connectable`，大幅增加代码复杂度和闪存占用 (nRF51可能不够用)。
    - 需开发 GATT 服务及配套手机 App。
  - 状态：暂缓，建议仅在 nRF52 芯片上尝试。

- [ ] **调研运动感应省电功能 (Smart Beacon)**
  - 目标：平时低频/零广播，检测到震动时高频广播。
  - 难度：**中等 (强依赖硬件)**。
  - 优势：理论上是最极致的省电方案，电池寿命可达 3-5 年。
  - 需求：
    - 硬件需板载加速度计 (如 LIS3DH)。
    - 需实现 I2C 驱动与 GPIO 中断唤醒逻辑。

- [ ] **Phase 5: 独立桌面客户端体验 (Future)**
  - 目标：将现有的 Python 脚本 + 网页体验打包为独立 App (Mac .app / Win .exe)。
  - 优势：
    - 用户仅需下载运行一个文件，无需安装 Python 环境。
    - 启动时自动打开本地浏览器。
    - 支持将 Hex 文件拖拽到窗口刷机。
    - **全能兼容性**：内置 OpenOCD，理论上支持市面 99% 的调试器 (J-Link, FTDI, DAPLink, etc.)。
    - **UI 升级**：增加 "调试器类型" 下拉框 (支持 J-Link, DAPLink, ST-Link, CMSIS-DAP 配置文件切换)。
    - 结合 "Local Bridge" 模式，彻底解决 WebUSB 兼容性问题。
  - 工具：PyInstaller, Electron (Optional), webview.

- [ ] **Phase 4: 硬件兼容性扩展**
  - [ ] **验证 DAPLink / CMSIS-DAP 支持 (High Priority)**
    - ST-Link 由于驱动/协议限制在 WebUSB 上体验不佳（需 Zadig 换驱动）。
    - DAPLink 使用标准协议，是 WebUSB 的最佳搭档。需采购硬件进行实测。
  - [ ] **调研 J-Link WebUSB 可行性**
    - 结论：困难。J-Link 使用私有非公开协议，且 WebUSB 支持需要特定固件或 Segger 官方 JS 库限制。不像 DAPLink 那样开箱即用。
