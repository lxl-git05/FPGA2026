# DLB 实现报告

## 前一阶段：FPGA Monitor PC 上位机

完整实现、架构、72项自动化测试、Chrome端到端验收、生产构建、运行步骤和硬件验证边界见：

[FPGA-Monitor/IMPLEMENTATION_REPORT.md](FPGA-Monitor/IMPLEMENTATION_REPORT.md)

上位机位于 `DLB/FPGA-Monitor/`；在该目录执行 `npm run dev`，浏览器点击 **Demo Mode** 即可观察波形。既有 FPGA RTL 和用户暂存内容均保留，真实 FPGA UART 硬件联调未执行。

## 2026-10-02：位置环 UART 在线调参

本阶段根据用户后续要求修改 `DLB/DLB.srcs/sources_1/new/Test.v`，参考提交 `3445a1df2909839e3544259d3ce0e9b2b66bf9c1` 的减速电机位置环行为，替换当前 ADC 测试顶层。没有切换或回退整个仓库，没有改动用户已有暂存内容及 `.gitignore`。详细操作说明见 [PID_UART_README.md](PID_UART_README.md)。

### 实现内容

- 恢复原按键目标调节、编码器位置反馈、20ms控制周期、20kHz TB6612 PWM和双四位数码管显示。
- Kp/Ki/Kd复用 `parameter_manager` 寄存器，由实际UART输入经 `protocol_rx` 校验后更新；默认值沿用参考提交的Kp/Kd，Ki=0，新增顶层 `I_LIMIT=500` 使在线Ki积分有效。
- 默认115200/8N1。SET_PARAM只接受ID 0x10/0x11/0x12、TYPE 0x03 (Q16.16)。CRC错误、错误TYPE、未知ID不改变系数。调参后清积分并同步历史误差，下一个控制周期重新运算。
- Telemetry上传goal(0x01)、real(0x02)、error(0x03)、set(0x04)、Kp/Ki/Kd(0x10～0x12)。goal为目标位置，real为编码器位置，set为PID输出/PWM计数；每帧53字节，正常50Hz。
- 先记录同次PID输入，再将结果与对应系数锁存成完整快照；发送期间保持字段不变。内部误差保留33位，上传INT32误差时饱和而不截断翻转符号。
- 复用现有PID数学核心及驱动模块，未新建板端 `.v` 模块。未修改引脚约束；保留ADC接口并关闭片选。现有 `DLB/DLB.xpr` 已包含所需模块且顶层为Test，无需修改项目文件。
- 提供可复现HDL测试、FPGA Monitor编解码器交叉验证与Vivado完整构建脚本。上位机只更新README中的板端状态和快照说明，业务通道名称仍由用户配置。

### 验证结果

| 验证 | 结果和证据 |
| --- | --- |
| Xilinx xvlog/xelab/xsim 2024.2 | PASS：32次PID运算、11帧物理UART TX数据、9次合法参数写入；日志 `../Claude_Temp/PID_UART_validation/pid_uart_sim.log` |
| 独立72位整数PID模型 | 按动态系数比较误差、积分、差分、Q格式输出；覆盖小数累积、±500积分限幅、±2500输出限幅、正负方向、参数更新清零、复位恢复 |
| UART接收和拒绝路径 | 从RX引脚按真实115200/8N1发送16字节SET_PARAM；Kp/Ki/Kd、负Q值及32位RAW极值写入成功；坏CRC/TYPE/ID各拒绝一次 |
| UART发送一致性 | 独立按比特读取TX引脚，校验53字节帧的Header、SEQ、LEN、COUNT、全部ID/TYPE/RAW、CRC和Stop Bit；发送途中修改位置、系数与加速PID更新时快照保持不变 |
| 控制/位置边界 | 两次自然更新验证20ms间隔；AB正反方向计数、回原点不清编码器、按键优先级、显示正确；goal/real的INT32全跨度产生±4294967295误差，上传正确饱和 |
| FPGA Monitor真实codec交叉验证 | PASS：`node DLB/tests/check_pid_uart_codec.mjs`用实际ProtocolDecoder分块解析11帧HDL捕获数据，校验goal/real/error/set与正负Q16.16；实际ProtocolEncoder生成的Kp=1.0命令逐字节等于发送给DUT的命令 |
| 上位机回归 | `npm.cmd run test`：8个文件、72项测试通过；`npm.cmd run build`：成功，生产产物正常生成 |
| 综合/布局/布线/bitstream | Vivado 2024.2、xc7a35tfgg484-2、50MHz；完整构建成功，Bitgen Completed Successfully |
| 布线后时序 | WNS=+0.013ns、TNS=0；WHS=+0.107ns、THS=0；脉宽余量+9.500ns；setup/hold/pulse-width失败端点均0 |
| 资源和DRC | 综合报告1822 LUT、1338 FF、13 DSP、1 BUFG、0 latch；DRC无Error，未降低检查等级 |

测试台先运行两个真实20ms周期，再加速控制计数器以覆盖边界；UART收发始终使用实际比特时间。部分目标按键事件和极端反馈通过测试台强制注入，用于覆盖无法在短时间内由真实电机产生的情况。这些仿真结果不代表实机电机运动已验收。

### 构建产物

| 文件 | 用途 |
| --- | --- |
| `build/pid_uart/Test.bit` | 可烧录文件，2192112字节 |
| `build/pid_uart/Test_routed.dcp` | 已完成布局布线的检查点 |
| `build/pid_uart/timing.rpt` | 最终50MHz时序证据 |
| `build/pid_uart/utilization.rpt` | 综合资源使用情况 |
| `build/pid_uart/drc.rpt` | DRC报告 |
| `scripts/build_pid_uart.tcl` | 从源码与现有XDC完整构建，时序失败即停止 |
| `scripts/test_pid_uart.ps1` | 编译并执行HDL验收测试，未见PASS或遇Fatal/Error则失败 |
| `tests/pid_uart_tb.sv` | UART/PID/控制边界验收测试台 |
| `tests/check_pid_uart_codec.mjs` | HDL捕获数据与上位机实际codec的交叉验证 |

`Test.bit` SHA256：`C745EC2497A28F87B061A8921E88C92D7A2E430BAF58CFC178E46019C3BE357B`。

构建对应 `Test.v` SHA256：`ED513CF7A3F1107E13B8740B47BA78965BECE26145008D53626F221633D93037`。输出和临时证据受既有Git忽略规则管理，源码、脚本和说明文件可以独立纳入版本控制。

### 实际验证边界

未连接或烧录真实FPGA，未进行真实电机闭环、编码器方向及USB UART联调；遵循 `AGENT.md` 中由用户随后上板测试的分工。默认系数沿用指定提交，不能据此宣称适合任意电机和负载。

当前布线后setup余量为0.013ns，已通过现有50MHz约束，但余量较小；更改器件速度等级、系数结构或实现设置后应重新检查最终时序。既有XDC未描述外设同步输入/输出延迟，报告的通过范围是已约束路径。没有添加虚假的多周期例外或降低DRC等级。

DRC保留原工程配置电压未声明(CFGBVS-1)、DSP未流水化建议和布局相关Warning，无Error。Vivado另外报告Tcl Store/WebTalk配置写入受限，bitstream已成功生成；未修改系统目录、系统环境变量或配置。网页构建保留ECharts单块超过500kB的体积提示，构建成功。

积分使用原核心的贡献限幅，未加入条件积分/反算抗饱和。UART三项系数独立修改，复位不保留在线参数，goal目前仍由按键设置。这些均是已实现行为，不存在待补代码或未完成TODO。

## 2026-10-02：上位机波形交互修复

修复只能横向拖动及缩放后停止更新：现在左键支持上下左右平移，普通滚轮缩放X，Shift+滚轮缩放双Y；LIVE下操作保持实时更新，PAUSE仅在用户点击时冻结。新增RESET VIEW恢复已配置视图。暂停时更改时间窗不会重新捕获新数据。

全部81项自动化测试、生产构建、1920×1080与1366×768实际Chrome Demo交互及生产preview检查通过。没有修改本阶段的FPGA代码或bitstream。变更和证据详见 [上位机实现报告](FPGA-Monitor/IMPLEMENTATION_REPORT.md) 的后续修复章节。
