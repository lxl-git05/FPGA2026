# 验证记录（2026-10-20）

## 默认参数更新（2026-10-21）

按用户要求，上电/复位默认改为 Kp=0.98、Ki=0、Kd=0.12；内部Q系数独立整数计算为555796 / 0 / 3402831，测试台期望与README同步。
RTL及两份测试台xvlog语法编译通过。本次仅调整默认常量，没有重跑布局布线或运行仿真；下方时序数值来自上一版默认参数的分拍构建。需重新综合并下载后，新上电默认值才会在板上生效，串口在线调参仍可覆盖。

## 当前分拍版（22:32构建）

用户已确认修改 PID_Motor 内核以解决时序。仅本工程 MyPID 改为状态机分拍，DLB 原 MyPID 和其余复用模块哈希均保持不变。
接受 tick 时为步骤0，经过步骤1至8，在160ns后统一提交结果；20ms控制定时器不变。调参clear可能让一次结果相对周期边界多延迟1个时钟，不会跳过整个20ms周期。

| 项目 | 分拍版结果 |
|---|---|
| Gowin综合 / 布局布线 / 位流生成 | 完成 |
| 50MHz setup / hold违规端点 | 0 / 0 |
| 最差setup裕量 | +1.137ns |
| Actual Fmax | 53.012MHz |
| 当前最差路径 | frame_position_0_s0/Q → real_dividend_61_s0/D（遥测换算） |
| 最差路径数据延迟 | 18.828ns |
| Logic / Register / DSP | 3958 / 2743 / 9 |
| MyPID SHA256 | 335E88373F0747A39D77343A1EC8BDE7D47C604828B0DFBB1732B6FD6EED77D5 |

SDC与CST未改，未添加多周期或false-path例外，9个IO约束沿用。
运行 `tests/run_xsim.ps1 -Suite pipeline`，两份测试台及RTL均通过xvlog语法编译；pipeline及integration均完成xelab静态展开和数据流分析，随后仍报XSIM 43-3409 / 43-3915（生成C编译失败）。
临时使用已安装GCC10链接测试引擎、隔离Tcl启动后，进入引擎启动阶段仍发生访问异常（Simtcl 6-50）；没有得到自检PASS，不能声称运行仿真通过。未修改已安装工具或系统环境配置。

新增 `tb_pid_pipeline.sv`：独立宽整数模型、100组随机完整signed32输入、正负饱和、负数算术右移、输入/限幅快照、忙时tick忽略、8拍延迟、clear/禁用/复位在8个运算阶段逐个取消；均待工具成功运行后确认。
集成测试已改为完成时检查结果，并检查20ms输出节奏及三字段快照。
报告仍在下方同一Claude_Temp目录，新结果已替换先前构建输出；修改前源码备份在 `Claude_Temp/PID_Motor_pipeline/MyPID_before.v`。
本轮未下载板卡，实机闭环尚待验收。

## 以下为初版历史记录（分拍改造前）

## 已完成的检查

- 工程 XML 中全部引用文件存在，顶层、CST、SDC 已加入。
- Gowin V1.9.12、GW2A-LV55PG484C8/I7、Device Version C：最终 RTL 综合、布局布线、位流生成完成。
- 9 个 IO 的实际布局结果与 CST 一致：M19、AB3、K20、L20、Y20、AA20、V14、AA17、V15；使用 BANK2/4/5，LVCMOS33。
- 最终资源：3895 Logic，2271 Register，9/20 DSP，9 IO。
- Xvlog 2024.2：顶层、复用 RTL、自检测试台语法编译通过；xelab 静态展开与数据流分析通过。
- 独立整数计算核对默认 Q 系数 636896 / 0 / 526304，命令 0.80 / 0.51 / 0.49 对应 453711 / 5785 / 13894892。
- SHA256 与本轮开始前记录一致，见下表。

## 50MHz时序未通过

最终报告生成于 2026-10-20 21:23（北京时间）。

| 项目 | 结果 |
|---|---|
| 时钟约束 | 20.000ns / 50MHz |
| Setup 违规端点 | 13 |
| Hold 违规端点 | 0 |
| 最差 setup slack | -7.920ns |
| 估算 Actual Fmax | 35.817MHz |
| 最差起点 | sample_target_1_s0/Q |
| 最差终点 | pid_inst/pid_out_2_s0/D |
| 关键路径数据延迟 | 27.885ns |

瓶颈为进入原 PID_Core 的目标差值、乘法、累加及输出限幅组合路径。该问题不能因为 PID 每20ms触发一次就忽略：当前实现仍由50MHz时钟寄存器采样。
按批准计划保留 MyPID 内核，不擅自流水化、降频或添加未经证明的多周期/false-path 约束。
本次没有达到50MHz时序验收，生成位流不代表硬件可靠性通过。后续需要决定内核流水化等真实实现方案。

最终报告在工作区临时目录：

```
Claude_Temp/PID_Motor_validation/gowin/pid_validation/impl/pnr/
  pid_validation.rpt.txt
  pid_validation.pin.html
  pid_validation_tr_content.html
```

## 运行仿真未通过工具启动阶段，尚未执行自检

`tests/run_xsim.ps1` 的真实结果为：xvlog 编译通过，xelab 报 XSIM 43-3409 / 43-3915，无法编译生成的 `xsim_1.c`。
因此不能声称协议、PID 运算或 UART 波形的运行仿真通过。

为定位工具问题，在 Claude_Temp 中用已安装 GCC10 编译了生成的 C 并链接临时 xsimk，随后仍受 Vivado Tcl 初始化及库加载故障阻断。
隔离 Tcl 副本和启动尝试也只位于 Claude_Temp；没有修改系统工具安装、系统环境变量或工具原文件。
原始与隔离日志在 `Claude_Temp/PID_Motor_validation` 中；标准失败日志为 `xelab.log`。

自检测试台包含以下检查，但以下均**待成功运行后确认**：物理 UART 发送/接收与 CRLF、六位小数及同次快照、命令拆包/连续/异常/越界/超长/超时/重同步、20ms 周期、正负目标反馈、PID 模型、积分限幅及换参清历史。
超时测试直接推进计数器到100ms阈值；编码器计数由测试夹具注入。实际每圈计数、方向、机械闭环响应还需板上验收。

## 复用模块 SHA256

| 文件 | SHA256 |
|---|---|
| PID_Motor/src/Key.v | 08C2B02A25B95E16786D21D9AF6108F8937A1CD8B8718A6077E905F1C3AE7EB2 |
| PID_Motor/src/MyPID.v | 8F9058250D3D8A12D0600BB052291C2EF326FBC84A76383701D299EC54BF6112 |
| DLB 原 tb6612_motor_driver.v | 1E211044D156DD54B4163671C2507A9833619F0368A01CF57417B9C069B7D062 |
| DLB 原 encoder_quad.v | 7D42E9D408F77CC9012BA0373ACBF79B23E6F1A249ABF39C785F2FF987EB1408 |
| DLB 原 PWM.v | 05A89B236D41FC49F8622A3D6C47AB38B6101D915FB7EBF43118EA2109C8820B |
| uart_loopback/src/uart_byte_rx.v | BC8660AB2878E5BF213ADDA88275F3EFF9CF5C5F0A10DC529DED6A02DC20DF21 |
| uart_loopback/src/uart_byte_tx.v | F57E1BBF2476F73E0B671D8C8C698047EF054C02AC3FC063BE775813C916A772 |
| uart_loopback/src/uart_data_rx.v | 87F7D39474902D8A031F5A79195F8BDB8844E721614A88188B0DB9F9E99A6753 |
| uart_loopback/src/uart_data_tx.v | 5E0C0628C73410B4D64BEED14E7696EB2B7954BEDD51E0CFFEA0C823059982BB |
