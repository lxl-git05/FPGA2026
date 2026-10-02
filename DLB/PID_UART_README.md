# 减速电机位置环：UART 调参和 goal / real / set

`DLB/DLB.srcs/sources_1/new/Test.v` 恢复提交 `3445a1df2909839e3544259d3ce0e9b2b66bf9c1` 的位置环行为，并接入现有 Protocol V1 收发模块。无需切换 Git 提交。原有 PID、编码器、按键、数码管和电机驱动模块继续复用。

## 使用

1. 烧录仓库根目录下的 `DLB/build/pid_uart/Test.bit`。Vivado 工程的器件为 `xc7a35tfgg484-2`，顶层为 `Test`。
2. 复位时当前位置作为零点，目标为 0，Kp/Ki/Kd 恢复默认值。按键1松开加102计数，按键2松开减102计数；按键3松开回到复位原点，不清零编码器；按键4未使用。以408计数/圈计算，102计数约90°。
3. 在 `FPGA-Monitor` 目录运行 `npm.cmd run dev`，用 Chrome / Edge 打开 localhost，点击连接串口，使用 **115200、8N1**。
4. 收到数据后，按下面的 ID 表给通道命名。仅对 **0x10、0x11、0x12** 开启 Writable，填写适合的滑块范围。滑块直接调节；数值框按 Enter 发送。看到 `SYNCED` 表示 FPGA 上传的参数 RAW 与请求相同。
5. 位置 goal/real 可放左轴，set 放右轴。数码管左4位为 `|set|`，右4位为 `|real|` 的最后4位，符号请看上位机。

## 通道表

| PARAM_ID | 建议名称 | TYPE | 含义 | 可写 |
| --- | --- | --- | --- | --- |
| 0x01 | goal | INT32 (0x01) | PID 采样时的目标位置，编码器计数 | 否 |
| 0x02 | real | INT32 (0x01) | 同次采样的编码器累计位置，计数 | 否 |
| 0x03 | error | INT32 (0x01) | goal − real；超出INT32时饱和 | 否 |
| 0x04 | set | INT32 (0x01) | PID 控制输出，带方向的 PWM 计数，−2500～2500 | 否 |
| 0x10 | Kp | Q16.16 (0x03) | 比例系数 | 是 |
| 0x11 | Ki | Q16.16 (0x03) | 每个采样周期的积分系数 | 是 |
| 0x12 | Kd | Q16.16 (0x03) | 误差差分系数 | 是 |

每次 PID 更新后上传一帧：COUNT=7、LEN=43、总长度53字节，约50帧/秒。goal/real/set 以及当次运算使用的三个系数整帧锁存；发送期间不变。UART 默认一帧约4.6ms，下一次采样前能发送完成；发送忙时跳过该次上传，控制计算继续。协议没有额外 ACK，通过后续 Telemetry 确认参数更新。

`set` 是送入驱动器的控制量，`|set|/2500` 对应占空比，不是速度反馈；PWM 发生器在 PWM 周期边界更新占空比。正负方向保持该提交的 `TB6612 DIR_REVERSE=1`、`ENCODER_DIR_REVERSE=0`。STBY 沿用板上直接接3V3的方式。ADC片选关闭，保留ADC顶层端口以兼容现有引脚约束。

## 参数与算法

在 `Test.v` 模块参数里修改 `KP_INIT / KI_INIT / KD_INIT` 可以改变烧录后的初始值；UART 修改存于寄存器，复位后恢复初始值。

| 参数 | 默认 RAW / 整数 | 用途 |
| --- | --- | --- |
| KP_INIT | 1623462 | 沿用位置环提交，Kp=1623462/65536 |
| KI_INIT | 0 | 初始不积分 |
| KD_INIT | 1341560 | 沿用位置环提交，Kd=1341560/65536 |
| I_LIMIT | 500 | 积分项输出限幅 ±500，非Q格式 |
| ENCODER_DIR_REVERSE | 0 | 0为原AB计数方向，1反向 |

Q16.16 的 `RAW = 系数 × 65536`，上传原始补码，PC负责量化。例如系数1.0对应65536，0.5对应32768。可先给 Kp/Kd 配置滑块0～100、步长0.01，Ki配置0～10、步长0.001；这是控件范围示例，实际稳定参数取决于电机、负载和接线。

控制周期固定 `Ts=0.02s`，沿用 `PID_Core` 的离散算法：

```text
error = goal - real
P = Kp * error
I = clamp(I + Ki * error, -I_LIMIT, I_LIMIT)
D = Kd * (error - last_error)
set = clamp(P + I + D, -2500, 2500)
```

内部保留Q格式小数，最终算术右移16位得到有符号整数。若从连续PID系数转换，`Ki_FPGA=Ki_continuous×0.02`，`Kd_FPGA=Kd_continuous/0.02`，Kp不变。积分项限幅有效，但没有额外实现基于输出饱和的条件积分或反算抗饱和。

收到合法 `SET_PARAM` 后只更新对应系数，同时清除积分、同步上次误差并将输出暂置0，下一次20ms控制周期重新运算。三个系数分别写入，不属于原子批量更新。ID不支持、TYPE不为Q16.16、CRC错误时不修改系数。目标位置由按键调整；协议不支持写入goal/real/set。

## 引脚

沿用 `DLB/DLB.srcs/constrs_1/new/DLB_XDC.xdc`，没有改动约束：

| 信号 | FPGA封装引脚 |
| --- | --- |
| clk / rst_n | Y18 / B21 |
| UART TX / RX | M15 / J21 |
| encoder A / B | A13 / A15 |
| TB6612 IN1 / IN2 / PWM | A18 / F13 / E13 |
| key1 / key2 / key3 / key4 | F15 / A20 / B20 / A21 |

外接UART使用3.3V TTL并共地，适配器TX接FPGA RX、RX接FPGA TX。方向校准沿用原提交；更换电机或AB线后需核对目标增大时反馈也增大。

## 可复现验证和构建

在仓库根目录执行（Vivado 2024.2 的 bin 需在 PATH，或使用下列绝对路径）：

```powershell
& .\DLB\scripts\test_pid_uart.ps1
node .\DLB\tests\check_pid_uart_codec.mjs
```

测试脚本支持 `-VivadoBin 'E:\AppDownloadE\Vitis\Vivado\2024.2\bin'`。如当前PowerShell限制脚本执行，可使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\DLB\scripts\test_pid_uart.ps1`，仅影响该进程。

构建时把日志和工具中间文件留在工作区的Claude_Temp：

```powershell
New-Item -ItemType Directory -Force .\Claude_Temp\PID_UART_validation | Out-Null
Push-Location .\Claude_Temp\PID_UART_validation
& 'E:\AppDownloadE\Vitis\Vivado\2024.2\bin\vivado.bat' -mode batch -source '..\..\DLB\scripts\build_pid_uart.tcl' -log build.log -journal build.jou
Pop-Location
```

输出位于 `DLB/build/pid_uart/`：`Test.bit`、`Test_routed.dcp`、时序/资源/DRC报告。脚本检查无锁存器、单系统时钟，以及布线后setup/hold通过，再生成bitstream。已有GUI工程已包含这些收发模块，也可直接以Test顶层重新综合和实现。

本次仿真和实现结果见 [IMPLEMENTATION_REPORT.md](IMPLEMENTATION_REPORT.md)。仿真反馈由测试台提供，尚未执行实际FPGA、电机或USB UART上板联调。
