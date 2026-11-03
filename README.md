# OV5640 FPGA 工程

基于 Digilent Genesys 2（`xc7k325tffg900-2`）的 OV5640 FPGA 视觉处理工程，提供图像采集、灰度预处理、帧调度与 HDMI 可视化的模块化 RTL 实现。

工程围绕实时预览、手动拍照、冻结显示与结果展示组织功能，并配套板级接线说明、接口文档和可复现的自动化仿真流程。

## 快速验证

需要 Python **3.9 或以上**、Icarus Verilog **11 或以上**，并保证 `python`、`iverilog`、`vvp` 在 PATH 中。不需要安装 Python 第三方包，也不需要 Vivado 或开发板。

Ubuntu / Debian：

```sh
sudo apt-get update
sudo apt-get install -y python3 iverilog git
git clone https://github.com/shajiaolayu/fpga-emotion-peripherals.git
cd fpga-emotion-peripherals
python3 scripts/run_tests.py
python3 scripts/audit_release.py
```

Windows：安装 Python 和 Icarus Verilog，将两者的可执行文件目录加入 PATH。在本仓库根目录执行：

```powershell
python scripts/run_tests.py
python scripts/audit_release.py
```

测试在临时目录生成合成图像、软件参考灰度数据和人工分数，结束后自动清理。可以用 `--case roi`、`--case formatter` 等参数单独运行；每个测试默认有 180 秒超时。

## 工程模块

| 部分 | 内容 |
| --- | --- |
| 摄像头接口 | SCCB 16 位地址访问、芯片 ID 与配置回读、RGB565 DVP 接收、帧完整性检查 |
| 时钟域与缓存 | 异步事件 FIFO、帧缓存、完整帧预取、双缓冲所有权与复位同步 |
| 输入预处理 | 320×240 图像中的固定 192×192 ROI、RGB565 灰度转换、4×4 平均得到 48×48 输入 |
| 操作控制 | 拨码消抖、连续模式与手动拍照调度、忙碌期间触发处理 |
| 显示 | 实时预览与冻结照片的数据通路、中文字模、分数百分比、计时与结果发布 |
| 板级参考 | Genesys 2 时钟、引脚约束与 HDMI 编码依赖 |

`src/rtl/ov5640_photo_top.v` 是系统集成参考，当前路径使用 `photo_overlap_pipeline` → `photo_stream_consumer`。保留的 `photo_stream_pipeline` 是已有串行通路参考，当前板级顶层不使用它。

## 目录与接口

```text
src/rtl/             工程 RTL 与头文件
src/assets/          字体、显示掩码和通用指数查表
src/constraints/     板级引脚及时间约束参考
src/third_party/     Digilent rgb2dvi，保留原许可
sim/                 模块测试、传感器模型与核心接口测试替身
scripts/             测试入口、合成数据生成与发布审计
docs/                接线、私有核心接口及验证范围
release-manifest.json 公开文件清单与 SHA-256
```

接线及操作见 [wiring.md](docs/wiring.md)，私有核心的加载、启动和结果契约见 [core-interface.md](docs/core-interface.md)，测试覆盖与边界见 [validation.md](docs/validation.md)。

## 系统集成与依赖

工程通过 `inference_core` 接口连接识别核心。核心实现、模型权重及其二进制产物不随本仓库分发；完整识别系统的综合与运行需要另外提供获授权的核心。

板级实现参考 Vivado 2019.2，默认系统工作时钟为 120 MHz；部分源码注释中的 50 MHz 是历史描述，集成应以顶层参数和时钟模块为准。`.v` 文件需要按 SystemVerilog 解析，RTL 目录加入 include 路径，所需 `.mem` 需要注册为初始化文件。

本仓库的仿真覆盖图像采集、预处理、帧调度、显示和接口协议，不评价神经网络识别准确率。`sim/inference_core_interface_stub.sv` 只检查人工图案的输入顺序并返回人工分数，带有禁止综合的保护，不属于生产硬件源码。仓库不提供完整识别系统的 XPR、构建脚本、bit 或网表。

现有版权与第三方许可声明保留，第三方来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本次发布不新增覆盖全部自有源码的许可证；公开可读取不代表对私有核心授予许可。
