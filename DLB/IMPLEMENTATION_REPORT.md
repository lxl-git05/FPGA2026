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

## 2026-10-02：白色 UI 与 VOFA 风格导航

上位机改为白色界面，灰色虚线网格和蓝色控件。左键自由平移X及双Y；绘图区滚轮围绕鼠标点缩放三轴；X轴区域滚轮仅缩放X，左/右Y轴区域滚轮仅缩放对应Y。无需Shift。移到缓存之外留空，RESET VIEW恢复；LIVE缩放/拖动保持数据更新。

全部86项自动测试、Vite生产构建、1920×1080及1366×768实际Chrome Demo、4173生产预览通过。锚点保持、单轴隔离、Auto/Manual平移、回到拖动起点、负时间空白、实时series更新、暂停继续接收、记录及历史已检查。操作说明和详细证据见 [上位机实现报告](FPGA-Monitor/IMPLEMENTATION_REPORT.md) 最新章节。

本轮只修改上位机及说明文件，没有修改FPGA RTL或bitstream，也未进行硬件联调。上一阶段的Shift滚轮说明由本次交互取代。

## 2026-10-02：STM32 自动启摆移植与双环倒立摆控制

当前顶层已实现用户指定的“16-倒立摆-自动启摆”完整控制流程：1ms基础采样/状态计时、40ms三点峰值判断、双向35%/100ms启摆、连续两次进入中心区间后捕获、5ms角度内环、50ms位置外环、倒下停机。角度中心按用户值为2060；ADC暂用CH0，电机/编码器方向沿用既有配置。

最终按键操作以用户后续要求为准：K1按下目标+34（408/4/3），K2按下目标-34，K3按下启摆/停止；目标±4080，捕获时建立相对位置零点。默认角度PID为0.3/0.01/0.4，位置PID为0.4/0/4，两环输出均±100。外环输出以Q16.16小数作用于角度目标：`a_goal=2060-p_set`。PWM载波20kHz，小数百分比换成±2500计数后才取整。

经用户明确允许，UART每20ms上传12项：a_goal/a_real/a_set、p_goal/p_real/p_set，以及a_kp/a_ki/a_kd、p_kp/p_ki/p_kd。串口仅接受两环六个Kp/Ki/Kd，ID10/11/12及20/21/22、TYPE03；没有目标、启停、中心值等额外串口输入。既有上位机可自动发现全部通道，网页业务代码无需改动。通道映射、接线和运行说明见 [PID_UART_README.md](PID_UART_README.md)。

### 本轮验证

| 验证 | 结果 / 证据 |
| --- | --- |
| xvlog/xelab/xsim 主控制集成 | PASS：模拟889ms，71次内环、7次外环更新，44帧真实UART引脚数据；`../Claude_Temp/PID_UART_validation/pid_uart_sim.log` |
| 独立72位PID数值模型 | 按动态参数比较两环逐次输出、积分贡献/输出饱和，验证5/50ms周期与一拍计算完成 |
| 物理ADC/编码器接口仿真 | SPI角度采样、通道命令、AB正方向、捕获零点；没有将真实硬件描述为已测试 |
| 自动启摆状态机 | 双向100ms脉冲、两侧三点峰值判断、两次中心采样捕获、运行中停止、边界倒下停机 |
| 独立按键引脚仿真 | PASS：模拟342ms，真实key_in经同步/消抖，K1/K2按下±34、短毛刺不触发、长按/松开不重复、K3启停/重启、ADC新数据超时停止运行；`pendulum_keys_sim.log` |
| 集中PID数值仿真 | PASS：外环0.399994修正和内环小数误差、正负Q16.16、完整INT32反向极值误差、分数积分/积分限幅、Ki=0、待完成运算撤销、复位；`pid_numeric_sim.log` |
| 上位机实际编解码器交叉核对 | PASS：44帧、12个ID/类型/符号、小数串级关系，六个调参命令与HDL实际收到的字节逐项一致；`node DLB/tests/check_pid_uart_codec.mjs` |
| FPGA Monitor 回归 / 生产构建 | 86项测试全部通过，Vite build成功；仅更新板端使用文档，业务JS未改 |
| Vivado 2024.2 综合/布局/布线 | PASS：单50MHz系统时钟，无锁存器；setup裕量1.281ns，hold裕量0.102ns，脉宽裕量9.500ns，TNS/THS均0 |
| 资源 | 3031 LUT（14.57%）、1952寄存器（4.69%）、25 DSP（27.78%）、0 BRAM |
| DRC / Bitstream | 无DRC Error，成功生成 `build/pid_uart/Test.bit` 和 `Test_routed.dcp`；路径沿用已有位置环构建目录，内容现在为倒立摆固件 |
| diff 检查 | `git diff --check`无空白错误 |

PID乘法结果增加一拍寄存，拆开宽位乘法与累加/限幅路径，满足50MHz时序；默认参数关闭流水时保留通用PID的原整数接口，倒立摆实例开启Q16.16接口及流水。流水配置要求连续pid_tick至少间隔两个系统时钟，本顶层最短周期为5ms。新增测试台均为.sv，没有新增板端.v模块；上板逻辑仍集中于Test.v。

### 实机验证边界

本轮没有连接/下载真实FPGA，没有验证机械系统能否实际完成启摆并保持直立。ADC通道CH0、一圈408计数、电机与编码器极性仍须实物核对；中心值采用用户提供的2060。参数是STM32基线的定点初始值，不代表已经完成实机整定。

相比参考C代码，积分贡献额外限幅±100，捕获/改参清历史误差，32位相对位置代替int16_t回绕，PWM保留小数直到最后转换。ADC超时只检查采样模块有效脉冲，不能判断模拟传感器断线。UART冻结的是每20ms观察时刻的实测值、最近PID输出及系数，两环本身仍按各自周期更新。

时序报告仅确认已有XDC约束下的内部时序；现有外部引脚没有input/output delay约束，不能据此宣称ADC外部接口已完成板级时序签核。DRC仍有既有CFGBVS配置电压缺失及DSP流水优化等Warning，没有擅自猜测板卡配置电压。Vivado自身Tcl/WebTalk用户配置写入受目录权限限制，但源码、综合实现、报告与bitstream均生成成功；没有修改系统配置。

## 2026-10-02：恢复原PID成品模块，内外环独立例化

按用户要求，已完整撤销上一轮对`MyPID.v`添加的Q格式接口、Ki=0特殊处理及内部流水。当前文件与仓库原版一致，`git diff -- MyPID.v`为空，Git内容哈希均为`2ce584ef31dae6775982c935f66fcaf6e22952b9`。本节取代上一节有关PID模块扩展、小数串级接口和内部流水的实现说明；历史验证记录保留，当前使用本节的新固件与结果。

`Test.v`直接使用两个无参数扩展的原版`PID_Core`实例：`angle_pid`与`position_pid`。两个实例各自有目标、反馈、Q16.16系数、清零信号及5/50ms触发，内部状态互不共享。控制层串级关系为整数`a_goal=2060-p_out`，PWM在控制层按`a_out*25`换算，启摆状态机仍负责±35%脉冲。

为保持成品模块解耦，采样寄存放在控制层：先锁存两环输入，下一拍给各自pid_tick，没有改动PID数据通路或算法。捕获直立时先归零外环位置采样，再通过原`pid_clear`接口清历史误差，避免旧坐标产生虚假D项。在线改参也仅调用该实例的原清零接口。原PID在Ki直接变为0时保留已有I项，这个模块行为完整保留；串口改参由控制层清零后再使用新系数。

原PID目标/反馈/输出全部是整数，系数和内部积分保留原Q16.16精度。UART为兼容既有12通道映射，在边界把a_goal/a_set/p_set整数左移16位编码，不改变PID接口或计算精度。用户指定的中心2060、K1/K2按下±34、K3启摆/停止，以及六个PID系数的串口输入均保留。

### 最终验证与产物

| 验证 | 结果 |
| --- | --- |
| 成品PID文件完整性 | 原版Git哈希一致、无diff |
| 主控制HDL回归 | PASS：模拟889ms，内/外环71/7次更新，44帧物理UART引脚数据；新增捕获后外环无虚假D输出检查 |
| 独立按键输入回归 | PASS：消抖、按下±34、长按/松开不重复、K3启停/重启、运行中ADC超时、复位 |
| 原模块数值契约回归 | PASS：两个原PID例化、整数串级、Q16.16系数、INT32完整误差范围、内部小数积分/限幅、原Ki=0积分保持、调用方clear/enable优先级 |
| 上位机实际编解码器 | PASS：44帧的12个ID/类型，整数串级关系和符号，六项调参字节逐项一致 |
| Vivado2024.2完整实现 | PASS：50MHz、无锁存器，setup裕量0.331ns、hold裕量0.110ns、脉宽裕量9.500ns |
| 资源 | 2747 LUT（13.21%）、1740寄存器（4.18%）、26 DSP（28.89%）、0 BRAM |
| 固件 | 重新生成`build/pid_uart/Test.bit`及`Test_routed.dcp`，已替换上一轮修改PID版本 |

日志位于`../Claude_Temp/PID_UART_validation/`三组sim.log及`../Claude_Temp/pendulum_validation/build.log`。按`PID_UART_README.md`中的现有脚本可完整重跑。上位机业务代码没有修改，本轮不重复执行未受影响的86项前端测试与构建。

仍未下载真实FPGA或验证机械启摆/稳摆；ADC默认CH0及既有外部I/O时序约束边界不变。没有新增板端模块、修改XDC、修改系统配置或清理用户临时文件。

## 2026-10-02 21:13 固定起摆前位置零点，更新外环Ki

本节替代前文“捕获直立时建立位置原点”的行为描述。按用户要求，K3从停止切换到启动时保存编码器累计位置到position_offset，启摆及稳摆全过程保持该原点；捕获直立仅清PID状态和周期历史，不改position_offset、target_position或实际位置采样。停止保留原点，下次K3重新启动时记录本次起点。p_real始终包含相对本次起点的启摆位移，p_goal保持按键设定；未引入目标斜坡或修改±34步进。

外环位置Ki根据用户Channel 0x21截图更新默认值为0.016，Q16.16 RAW=1049，实际1049/65536≈0.01600647。外环默认Kp/Ki/Kd为0.4/0.016/4，内环仍为0.3/0.01/0.4。复位和默认系数遥测也使用1049，串口ID及类型保持原协议。

MyPID.v未修改，文件哈希仍与Git HEAD一致：2ce584ef31dae6775982c935f66fcaf6e22952b9。控制层继续直接例化两个独立原PID_Core。

回归覆盖非零编码器起点、起摆位移、非零goal捕获不变、捕获首次外环无虚假D项及新Ki积分、返回起点real恢复0；真实按键输入覆盖停止不重设零点、再次启动更新起点且保留goal。

| 检查 | 本轮结果 |
| --- | --- |
| 主控制HDL回归 | PASS：模拟1089ms，内/外环111/11次更新，54帧物理UART数据；固定起摆零点、非零goal捕获不变、起摆位移反馈、捕获无虚假D项及Ki=1049积分 |
| 真实按键HDL回归 | PASS：模拟402ms；消抖、±34、长按/释放、K3启动/停止/重新启动、重启记录新起点且goal不变、运行中ADC超时及复位 |
| 原PID数值回归 | PASS：两个成品实例、整数串级、INT32全范围误差、内部小数积分/限幅、原Ki=0保持行为及clear/enable/reset |
| FPGA Monitor实际codec | PASS：54帧12通道ID/类型、默认外环Ki=1049/65536、符号/串级关系及六个串口参数命令 |

构建改为PerformanceOptimized综合、AggressiveExplore物理优化/布线，不修改PID算法或时钟约束。策略依据AMD官方[synth_design命令说明](https://docs.amd.com/r/2023.1-English/ug835-vivado-tcl-commands/synth_design)与[实现策略说明](https://docs.amd.com/r/2024.2-English/ug904-vivado-implementation/Directives-Used-by-phys_opt_design-and-route_design-in-Implementation-Strategies)。原Explore流程出现setup=-0.297ns；随后布线后phys_opt_design异常退出，未输出新固件；最终固件以本节后续的成功实现记录为准。

最终实现PASS：50MHz单时钟，setup=0.200ns、hold=0.096ns、pulse width=9.500ns，DRC无错误，生成Test.bit（2192112字节，2026-10-02 21:24:04北京时间）及Test_routed.dcp。资源2720 LUT（13.08%）、1740寄存器（4.18%）、26 DSP（28.89%）。保留原I/O约束及引脚；本轮未连接或下载硬件，零点与Ki更新后的实际机械响应仍待上板确认。
