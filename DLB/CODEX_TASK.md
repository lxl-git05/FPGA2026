# FPGA Monitor PC 上位机全自动开发任务书

> 本文档是本项目的最高优先级开发规格。
>
> Codex 必须完整阅读本文档后再开始修改工程。
>
> 本任务要求自主完成。除非出现完全无法继续的外部阻塞，否则禁止向用户询问设计问题、确认问题或选择问题。
>
> 遇到未明确的小细节时，自行采用合理、简单、可维护的方案，并继续工作。
>
> 不允许因为任务较大而只完成框架、伪代码、TODO 或演示页面。
>
> 必须实际创建代码、运行能够运行的测试、执行构建、修复发现的问题，并留下完整文档供后续 Agent 接手。

# 1. 项目目标

开发一个运行于 Windows 11 上 Edge / Chrome 的 FPGA 调试上位机。

主要用途：

- 通过 Web Serial API 与 FPGA UART 通信。
- 接收 FPGA Protocol V1 Telemetry 数据。
- 自动发现 FPGA 上传的数据通道。
- 实时显示数据。
- 绘制类似 VOFA / 示波器的实时波形。
- 支持通道显示 / 隐藏。
- 支持通道重命名。
- 支持通道颜色修改。
- 支持左右 Y 轴。
- 支持 Y 轴 Auto / Manual。
- 支持实时 / 暂停 / 历史观察。
- 支持实验数据记录。
- 支持历史 Session。
- 支持 CSV 导出。
- 支持 PC 修改 FPGA 参数。
- 支持 Q16.16、Q8.24 等格式的人类数值 ↔ FPGA RAW 转换。
- 显示 TX / RX 原始 HEX 数据。
- 显示协议解析错误、CRC 错误、SEQ 丢帧。
- 所有用户配置持久化保存。

本项目不是普通串口助手。

UI 定位为：

```
VOFA
+
简易数字示波器
+
FPGA 参数调试器
+
实验数据记录器
```

# 2. 核心设计原则

## 2.1 浏览器禁止硬编码 FPGA 参数业务含义

禁止出现：

```
0x10 = "Kp"
0x11 = "Ki"
0x12 = "Kd"
```

这种硬编码。

浏览器只知道：

```
PARAM_ID
DATA_TYPE
VALUE
```

例如 FPGA 第一次上传：

```
ID = 0x10
TYPE = Q16.16
VALUE = 0.25
```

浏览器自动创建：

```
Channel 0x10
```

用户随后可以将其重命名：

```
位置环 Kp
```

该名称保存到本地配置。

后续再次打开网页，自动恢复。

# 3. Channel 的唯一机器身份

每个 Channel 使用：

```
PARAM_ID
```

作为唯一机器 Key。

例如：

```
0x01
0x02
0x10
```

但 PARAM_ID 不决定 UI 名称。

Channel 推荐数据模型：

```
{
    sourceId: 0x10,

    name: "Channel 0x10",

    type: 0x03,

    rawValue: 13107,

    value: 0.199996948,

    unit: "",

    visible: true,

    color: "...",

    axis: "left",

    writable: false,

    sliderMin: 0,
    sliderMax: 1,
    sliderStep: 0.001
}
```

用户修改：

```
name
unit
visible
color
axis
writable
sliderMin
sliderMax
sliderStep
```

后必须持久化。

# 4. 协议 Protocol V1

所有多字节数据：

```
Little Endian
```

完整 Frame：

```
HEADER       2 Byte
VER          1 Byte
MSG_TYPE     1 Byte
SEQ          2 Byte
PAYLOAD_LEN  2 Byte
PAYLOAD      N Byte
CRC16        2 Byte
```

帧头：

```
A5 5A
```

协议版本：

```
01
```

CRC：

```
CRC-16/MODBUS

Polynomial = 0xA001
Initial    = 0xFFFF
```

CRC 计算范围：

```
VER
MSG_TYPE
SEQ
PAYLOAD_LEN
PAYLOAD
```

以下不参与 CRC：

```
A5 5A
CRC16自身
```

CRC 发送：

```
CRC_L
CRC_H
```

# 5. FPGA → PC：TELEMETRY

消息类型：

```
MSG_TYPE = 0x01
```

Payload：

```
COUNT 1 Byte

重复 COUNT 次：

PARAM_ID   1 Byte
DATA_TYPE  1 Byte
VALUE      4 Byte
```

因此一个参数：

```
6 Byte
```

Payload 长度：

```
1 + COUNT × 6
```

例如三个参数：

```
03

01 01 E8 03 00 00
02 01 6C 03 00 00
10 03 00 40 00 00
```

表示三个参数。

# 6. DATA_TYPE

当前支持：

```
0x01 = INT32

0x02 = UINT32

0x03 = Q16.16

0x04 = Q8.24
```

所有类型在 UART 中 VALUE 都固定为：

```
4 Byte
```

# 7. ValueCodec

必须单独实现：

```
ValueCodec.js
```

它是浏览器代码中唯一负责：

```
RAW ↔ Human Value
```

转换的模块。

禁止把 Q16.16 转换逻辑散落到 UI、Chart、ParameterController 等其他文件。

## 7.1 Decode

INT32：

```
Raw signed int32
→ Human value
```

UINT32：

```
Raw uint32
→ Human value
```

Q16.16：

```
Human = SignedRaw / 65536
```

Q8.24：

```
Human = SignedRaw / 16777216
```

## 7.2 Encode

INT32：

```
Human
→ int32
```

UINT32：

```
Human
→ uint32
```

Q16.16：

```
Raw = round(Human × 65536)
```

Q8.24：

```
Raw = round(Human × 16777216)
```

必须处理：

```
负数
32bit补码
范围检查
NaN
Infinity
```

# 8. PC → FPGA：SET_PARAM

当前 PC→FPGA 只实现：

```
SET_PARAM
```

不要实现：

```
Command
GET_PARAM
RESET
START
STOP
ACK
其他复杂指令
```

保持简单。

MSG_TYPE：

```
0x10
```

Payload 固定：

```
PARAM_ID    1 Byte
DATA_TYPE   1 Byte
VALUE       4 Byte
```

所以：

```
PAYLOAD_LEN = 6
```

# 9. SET_PARAM 示例

例如：

```
Channel ID = 0x10

TYPE = Q16.16

用户输入：
0.25
```

ValueCodec：

```
0.25 × 65536
=
16384
=
0x00004000
```

实际 Payload：

```
10 03 00 40 00 00
```

完整帧：

```
A5 5A
01
10
SEQ_L SEQ_H
06 00

10
03
00 40 00 00

CRC_L CRC_H
```

# 10. 参数修改 UI

任何被用户设置为：

```
writable = true
```

的 Channel，应自动出现在右侧 Parameter Control 面板。

浏览器源码不得通过名称判断：

```
Kp
Ki
Kd
```

哪些可写。

完全根据用户配置。

# 11. 参数控件

每个可写参数同时提供：

```
Slider
+
Numeric Input
```

例如：

```
Kp

0.000 ├────────●────────────┤ 2.000

      [ 0.250000 ]
```

Slider 参数：

```
Min
Max
Step
```

均允许用户配置。

配置永久保存。

# 12. Slider 发送规则

禁止 Slider 每产生一个 mousemove 就疯狂发送 UART。

采用节流。

拖动期间：

```
最大约 20Hz
```

即大约：

```
50ms
```

最多发送一次。

鼠标松开：

```
立即发送最终值
```

数字输入框：

```
Enter
```

发送。

也允许：

```
Blur
```

时发送最终合法值。

必须进行范围与合法性检查。

# 13. 参数同步

当前协议不需要单独 ACK。

要求所有 writable Channel 同时通过 Telemetry 上传。

例如：

```
PC：

Kp = 0.25
```

发送 SET_PARAM。

FPGA 更新参数。

下一次 Telemetry：

```
ID 0x10
Q16.16
0.25
```

浏览器认为：

```
Requested = 0.25
Actual = 0.25

SYNCED
```

UI 可以显示：

```
✓
```

若长期不一致：

```
未同步
```

不要伪造 ACK。

# 14. Web Serial

实现：

```
SerialTransport.js
```

它只能负责：

```
requestPort
open
close
read bytes
write bytes
connection state
```

它不得：

```
解析协议
理解Q16.16
操作Chart
操作Channel
理解Kp/Ki/Kd
```

默认参数：

```
115200
8N1
```

UI 可以选择波特率。

主要目标环境：

```
Windows 11
Microsoft Edge
Google Chrome
```

# 15. 串口读取必须处理任意分包

非常重要。

Web Serial 每次 read() 返回的数据边界：

```
不等于协议Frame边界
```

可能出现：

```
一次读取半帧

一次读取3帧

A5在本批最后一个Byte
5A在下一批第一个Byte
```

ProtocolDecoder 必须使用内部 Buffer。

禁止假设：

```
一次Serial Read == 一帧
```

# 16. ProtocolDecoder

实现：

```
ProtocolDecoder.js
```

职责：

```
Byte Stream
→ 找 A5 5A
→ Header同步
→ 读取LEN
→ 等待完整Frame
→ CRC验证
→ Frame解析
→ 输出Telemetry
```

必须支持：

```
粘包
拆包
乱码后重新同步
错误CRC丢弃
异常LEN保护
未知MSG_TYPE安全忽略
```

禁止操作 DOM。

禁止操作 ECharts。

# 17. ProtocolEncoder

实现：

```
ProtocolEncoder.js
```

职责：

```
业务参数
→ SET_PARAM Frame
→ Uint8Array
```

负责：

```
SEQ
Little Endian
Length
CRC16
```

UI 不允许自己拼协议字节。

# 18. Channel 自动发现

收到 Telemetry 参数后：

如果 ID 已存在：

```
更新当前值
```

如果 ID 不存在：

```
自动创建 Channel
```

默认名称：

```
Channel 0x01
Channel 0x10
```

ID 建议统一显示两位 HEX。

不要要求用户修改源码。

# 19. Channel 配置持久化

实现：

```
ConfigStore.js
```

使用：

```
localStorage
```

保存：

```
Channel name
unit
visible
color
axis
writable
sliderMin
sliderMax
sliderStep

串口波特率
图表时间窗
左右Y轴设置
其他纯UI配置
```

使用版本化 Key，例如：

```
fpga-monitor-config-v1
```

不得随意更改已有存储 Schema。

如果未来 Schema 改变，提供迁移或安全 fallback。

# 20. 颜色系统

使用固定默认 Palette。

Channel 第一次出现时：

```
按发现顺序
```

分配颜色。

禁止随机颜色。

例如：

```
Channel 0 → Palette[0]
Channel 1 → Palette[1]
...
```

用户可以自行修改颜色。

修改后：

```
持久化
```

后续重启仍使用用户颜色。

# 21. UI 主布局

桌面优先。

整体布局：

```
┌─────────────────────────────────────────────────────────────────────────┐
│ FPGA Monitor   ● Connected   COM5   115200   RX 50Hz   Lost 0   CRC 0 │
├─────────────────┬───────────────────────────────────────┬───────────────┤
│ CHANNELS        │                                       │ CONTROL       │
│                 │                                       │               │
│ Channel列表     │              WAVEFORM                 │ 可写参数       │
│ 当前数值        │                                       │ Slider        │
│ 显示/隐藏       │                                       │ Input         │
│ 颜色            │                                       │               │
├─────────────────┴───────────────────────────────────────┴───────────────┤
│ LIVE | Pause | 1s | 5s | 10s | 30s | 60s | Y Axis | Record           │
├─────────────────────────────────────────────────────────────────────────┤
│ Communication Log                                                       │
│ RX ...                                                                  │
│ TX ...                                                                  │
│ ERR ...                                                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

整体风格：

```
现代
简洁
偏工程工具
深色主题优先
高信息密度
不要花哨动画
```

# 22. Channel Panel

左侧 Channel Panel 每个通道显示：

```
显示 / 隐藏
颜色
名称
当前值
单位
```

例如：

```
👁 Position
   ■
   983 pulse
```

支持：

```
重命名
单位设置
颜色修改
显示/隐藏
选择Left/Right Y
设置 writable
设置 Slider 参数
```

隐藏 Channel：

```
只是停止渲染
```

禁止：

```
停止接收
停止记录
删除历史
```

# 23. 波形

使用：

```
Apache ECharts
```

使用 npm 包管理，不依赖必须联网才能加载的 CDN。

实时图：

```
一张主Chart
```

不要第一版就创建十几个 Chart。

所有 visible Channel 绘制到主图。

# 24. X Axis

提供快速时间窗口：

```
1s
5s
10s
30s
60s
```

支持：

```
LIVE
PAUSE
```

LIVE：

```
自动跟随最新数据
```

PAUSE：

```
图表停止滚动
```

但以下必须继续：

```
串口接收
协议解析
数据记录
历史保存
```

点击 LIVE 后重新跳回最新数据。

# 25. Y Axis

绝对不能只有 Auto。

必须实现：

```
LEFT Y

Auto
或
Manual Min / Max
```

以及：

```
RIGHT Y

Auto
或
Manual Min / Max
```

Channel 可以选择：

```
Left
Right
```

例如：

```
Position → Left
Error    → Right
```

必须支持观察“小信号叠加在大信号旁边”的情况。

# 26. Chart Tooltip

鼠标移动到波形上时：

使用统一时间 Cursor。

显示该时刻所有 visible Channel：

```
Time       5.280 s

Target     1000
Position    983
Error        17
PID Out     452
```

# 27. Zoom / Pan

必须支持：

```
鼠标滚轮 / ECharts DataZoom
拖动
缩放
```

PAUSE 状态下尤其方便查看历史区域。

# 28. 浏览器默认右键

在应用区域禁用浏览器默认：

```
contextmenu
```

避免右键菜单干扰示波器操作。

V1 不必实现复杂自定义右键菜单。

不要依赖浏览器或鼠标驱动的“右键手势”作为核心功能。

# 29. 实时数据和绘图解耦

禁止：

```
收到一帧
→ 立即setOption完整重绘
```

FPGA 可以：

```
50Hz
```

接收层：

```
所有数据都接收
所有数据都保存
```

Chart：

```
大约20~30FPS
```

独立刷新即可。

使用 requestAnimationFrame 或合理 throttle。

# 30. Data Store

实现：

```
ChannelStore.js
```

它是实时数据的唯一中心状态。

数据流：

```
ProtocolDecoder
      ↓
ChannelStore
   /    |     \
Chart   UI    Recorder
```

Chart 不允许直接读取 SerialTransport。

UI 不允许直接解析协议。

Recorder 不允许自己解析 UART。

# 31. 实时缓存

每个 Channel 使用有限 Ring Buffer。

例如默认：

```
20,000 Point
```

允许后续调整。

禁止无上限向 JS Array push。

否则网页运行几小时后内存会越来越大。

# 32. 时间

当前 FPGA 协议没有 Timestamp。

因此 V1 每个 Telemetry Frame 至少保存：

```
hostReceiveTime
SEQ
```

绘图默认使用：

```
从连接或Session开始的相对时间
```

使用：

```
performance.now()
```

记录高分辨率相对接收时间。

保留：

```
SEQ
```

供后续丢帧分析。

不要假装 PC 接收时间就是 FPGA 精确采样时间。

架构上保留以后加入 FPGA Timestamp 的能力。

# 33. Communication Log

页面底部实现：

```
Communication Log
```

支持过滤：

```
RX
TX
ERR
```

颜色区分：

```
RX  = 蓝/青

TX  = 绿

ERR = 红

WARN = 黄
```

# 34. Log 内容

每条记录至少包含：

```
时间
方向
Raw HEX
简要解析结果
```

例如：

```
17:20:03.521 TX
A5 5A 01 10 ...

SET_PARAM
ID=0x10
TYPE=Q16.16
RAW=16384
VALUE=0.25
```

RX：

```
17:20:03.542 RX
A5 5A ...

TELEMETRY
SEQ=421
COUNT=7
```

错误：

```
CRC ERROR
Expected=...
Received=...
```

# 35. Log 必须有限长度

禁止无限创建 DOM 元素。

例如：

```
最大 2000 条
```

超过后移除最旧日志。

该限制只影响日志显示。

不得影响实验记录数据。

# 36. 顶部状态栏

至少显示：

```
Disconnected / Connected

Port

Baud

RX Frames/s

TX Frames

Current RX SEQ

Lost Frames

CRC Errors

Format Errors

Recording status
```

SEQ：

如果：

```
100
101
103
```

应统计：

```
Lost = 1
```

注意正确处理：

```
65535 → 0
```

自然溢出。

# 37. Recording

实现：

```
Record
Stop
```

点击 Record：

创建一个 Session。

记录：

```
Session ID
开始时间
结束时间
协议版本
每帧SEQ
每个Channel数据
Channel ID
Type
Raw
Decoded Value
Host Timestamp
```

# 38. IndexedDB

使用：

```
IndexedDB
```

保存实验历史。

不要使用 localStorage 存储海量实验数据。

推荐：

```
fpga-monitor-db-v1
```

写入应批量进行。

禁止每收到一个参数就开启一次昂贵事务。

使用 RAM Buffer 批量写入。

# 39. 历史 Session

实现历史列表。

至少显示：

```
名称
开始时间
时长
Frame数量 / Sample数量
```

支持：

```
查看
重命名
删除
导出CSV
```

# 40. CSV Export

提供 CSV 导出。

CSV 至少包含：

```
timestamp
seq
channelId
channelName
type
raw
value
```

或者使用宽表形式，只要实现稳定且文档说明。

必须正确导出负数和小数。

# 41. Demo / Mock Mode

必须实现一个：

```
MockTransport.js
```

其接口与：

```
SerialTransport
```

保持兼容。

目的：

没有 FPGA 时也可以测试网页。

Demo Mode 自动生成合法 Protocol V1 Telemetry Frame。

模拟例如：

```
Channel 0x01 INT32
Channel 0x02 INT32
Channel 0x03 INT32
Channel 0x10 Q16.16
Channel 0x11 Q16.16
Channel 0x12 Q16.16
```

但这些 ID 在 Demo 中只是测试数据。

正式浏览器业务代码仍然禁止硬编码业务名称。

模拟数据应形成明显波形：

```
正弦
目标阶跃
误差衰减
等
```

使 Chart 能被实际验收。

# 42. 项目技术栈

推荐使用：

```
HTML5
CSS
Vanilla JavaScript ES Modules
Vite
ECharts
IndexedDB
Web Serial
```

不要引入：

```
React
Vue
Angular
Electron
大型UI框架
```

当前项目不需要这些依赖。

目标：

```
结构清晰
代码容易理解
Agent容易维护
运行轻量
```

# 43. 推荐目录结构

创建：

```
FPGA-Monitor/
│
├── index.html
│
├── package.json
│
├── README.md
│
├── ARCHITECTURE.md
│
├── AGENTS.md
│
│
├── src/
│   │
│   ├── main.js
│   │
│   ├── app/
│   │   └── AppController.js
│   │
│   ├── serial/
│   │   ├── SerialTransport.js
│   │   └── MockTransport.js
│   │
│   ├── protocol/
│   │   ├── ProtocolConstants.js
│   │   ├── CRC16.js
│   │   ├── ValueCodec.js
│   │   ├── ProtocolDecoder.js
│   │   └── ProtocolEncoder.js
│   │
│   ├── store/
│   │   ├── ChannelStore.js
│   │   └── ConfigStore.js
│   │
│   ├── chart/
│   │   └── ChartController.js
│   │
│   ├── control/
│   │   └── ParameterController.js
│   │
│   ├── recorder/
│   │   └── HistoryStore.js
│   │
│   ├── logger/
│   │   └── FrameLogger.js
│   │
│   └── styles/
│       └── main.css
│
└── tests/
    ├── crc16.test.js
    ├── valueCodec.test.js
    ├── protocolDecoder.test.js
    └── protocolEncoder.test.js
```

如果实际开发中发现少量文件需要合并，可以合理合并。

但禁止最后退化为：

```
一个index.html
里面几千行JS
```

# 44. 文件头 Agent 注释

每个主要 JS 文件开头必须包含类似：

```
/**
 * Responsibility:
 *   本文件负责什么。
 *
 * Allowed dependencies:
 *   可以依赖哪些模块。
 *
 * Forbidden responsibilities:
 *   本文件绝对不应该做什么。
 *
 * Public API:
 *   对外暴露什么。
 *
 * Architecture invariants:
 *   修改本文件时必须保持哪些规则。
 */
```

这些注释主要是为了：

```
未来 Agent
Codex
维护者
```

而不是写无意义注释。

禁止大量：

```
// i++
```

这种没有价值的注释。

# 45. ARCHITECTURE.md

必须创建：

```
ARCHITECTURE.md
```

并明确记录以下不可破坏原则：

```
1. UI 禁止直接访问 SerialPort。

2. ChartController 禁止解析协议。

3. ProtocolDecoder 禁止操作 DOM。

4. ProtocolEncoder 禁止操作 DOM。

5. 浏览器源码禁止硬编码 PARAM_ID 的业务名称。

6. DATA_TYPE 转换只能由 ValueCodec 负责。

7. 所有 SET_PARAM 必须经过 ProtocolEncoder。

8. 所有串口发送必须经过 SerialTransport。

9. ChannelStore 是实时Channel状态的唯一真源。

10. ConfigStore 是Channel UI配置的统一管理者。

11. 隐藏Channel不能停止数据接收或记录。

12. Chart刷新频率与UART接收频率必须解耦。

13. 历史数据库与实时RingBuffer必须解耦。

14. Communication Log不得无限增长。

15. 新增FPGA Telemetry Channel原则上不得要求修改网页源码。

16. 可写参数由用户配置 writable 决定，不根据名字硬编码。

17. PARAM_ID只是机器唯一Key，不等同于UI名称。

18. 任何Agent修改架构前必须先阅读ARCHITECTURE.md。
```

# 46. AGENTS.md

创建：

```
AGENTS.md
```

告诉后续 Agent：

```
开始修改前必须阅读：

README.md
ARCHITECTURE.md
CODEX_TASK.md
```

并要求：

```
保持模块职责
不要为了省事跨层调用
不要无原因更改Protocol V1
不要硬编码Channel业务含义
修改协议代码必须同步更新测试
完成修改后必须运行测试和build
```

# 47. 测试

必须配置自动测试。

推荐：

```
Vitest
```

至少测试：

## CRC16

使用确定输入验证 CRC。

## ValueCodec

测试：

```
INT32 正数
INT32 负数

UINT32

Q16.16:
0
0.25
0.2
-1.5

Q8.24
```

## ProtocolEncoder

构造：

```
SET_PARAM
ID=0x10
TYPE=Q16.16
VALUE=0.25
```

检查：

```
Header
Version
Type
Seq
Len
Payload
Little Endian
CRC
```

全部正确。

## ProtocolDecoder

必须测试：

```
完整一帧输入

一个Byte一个Byte输入

随机拆成多个chunk

多个Frame一次输入

前面加入垃圾数据

A5 A5 5A重新同步

CRC错误

不完整Frame等待下一chunk

两个连续Frame
```

# 48. 测试原则

禁止只写：

```
测试文件存在
```

但没有真正验证协议。

测试必须能够发现：

```
Endian错误
CRC错误
长度错误
Q格式错误
拆包错误
粘包错误
```

# 49. 构建命令

package.json 至少提供：

```
npm run dev

npm run test

npm run build
```

Codex 完成任务前必须实际运行：

```
npm install
npm run test
npm run build
```

发现问题必须自行修复。

不能把错误留给用户。

# 50. README

README.md 必须写清楚：

```
项目用途

安装步骤

npm install

npm run dev

浏览器要求

如何连接串口

如何使用Demo Mode

如何重命名Channel

如何修改颜色

如何隐藏Channel

如何配置左右Y轴

如何设置Y轴范围

如何把Channel设为Writable

如何设置Slider Min/Max/Step

如何修改FPGA参数

如何开始Record

如何查看历史

如何导出CSV

Protocol V1概要

常见问题
```

Windows 11 用户应当可以根据 README 独立运行。

# 51. UI 配置保存

页面刷新或浏览器重新打开后，需要恢复：

```
Channel名称
Channel颜色
Channel单位
Channel显示状态
Left/Right Axis
Writable状态
Slider范围
Slider Step
Y轴模式
Y轴Min/Max
时间窗口
波特率
```

不要保存：

```
Web Serial Port权限对象
```

这种浏览器无法可靠序列化的对象。

# 52. UI 视觉要求

优先深色工程风。

参考：

```
数字示波器
开发工具
VS Code
现代监控Dashboard
```

不要：

```
炫彩渐变过多
大面积动画
游戏风
营销网站风
巨大的圆角卡片堆叠
```

要求：

```
紧凑
清晰
对比度足够
长期盯着波形不疲劳
```

# 53. 响应式范围

主要目标：

```
1920×1080 Windows桌面
```

同时至少保证：

```
1366×768
```

可正常使用。

手机端不是 V1 重点。

# 54. 错误处理

任何错误不得导致整个应用崩溃。

例如：

```
串口断开
用户取消端口选择
CRC错误
未知TYPE
未知ID
IndexedDB失败
配置JSON损坏
```

应：

```
记录日志
显示合理状态
继续运行或安全降级
```

# 55. 未知 DATA_TYPE

如果 FPGA 未来发：

```
TYPE = 0x99
```

浏览器不得崩溃。

Channel 仍可创建。

显示：

```
Unsupported Type 0x99
```

保留 Raw。

但不尝试错误转换。

# 56. 性能要求

目标：

```
50Hz Telemetry
10~30 Channel
连续运行数小时
```

页面不应明显越来越卡。

重点避免：

```
无限数组
无限DOM日志
每帧全量重建Chart
每个样本一次IndexedDB事务
```

# 57. 不允许的实现

禁止：

```
把所有JS写进index.html

硬编码Kp/Ki/Kd ID

Channel隐藏后停止记录

Chart直接处理SerialPort

UI直接计算CRC

Slider直接拼Uint8Array协议

每帧刷新整个DOM

日志无限增长

历史数据全部同时加载到Chart

使用随机颜色导致每次颜色变化

依赖互联网CDN才能正常运行

大量TODO未完成
```

# 58. Codex 自主工作要求

从开始到结束：

```
不要向用户询问：

“要不要这样？”
“颜色用什么？”
“文件夹叫什么？”
“确认继续吗？”
“是否安装依赖？”
```

所有这类非关键问题自行决定。

优先原则：

```
正确性
>
稳定性
>
模块解耦
>
易维护
>
视觉美观
>
炫技
```

# 59. 如果已有工程文件

开始前先检查当前目录。

如果已有：

```
HTML
JS
CSS
README
协议说明
```

先阅读。

尽量复用合理内容。

如果现有架构明显不适合，可以重构。

但不要误删：

```
FPGA Verilog
Protocol MD
用户已有资料
Git历史
```

只修改 PC 上位机相关内容。

# 60. Git

如果当前目录已经是 Git Repository：

开发前检查：

```
git status
```

不要删除用户未提交的修改。

完成后：

```
再次git status
```

并在最终报告说明修改了哪些文件。

如果仓库当前不是 Git Repository：

不要擅自初始化，除非确实必要。

# 61. 最终验收

在结束任务之前，Codex 必须自行完成以下验收：

```
npm install 成功

npm run test 全部通过

npm run build 成功

Demo Mode 可以启动

模拟Telemetry可以自动生成Channel

Channel能够重命名

Channel配置刷新后仍保存

颜色可修改并保存

显示/隐藏正常

波形正常滚动

Pause不停止数据接收

Live可以恢复

左右Y轴正常

Manual Y Min/Max正常

Communication Log存在

RX/TX颜色不同

Raw HEX可查看

CRC错误能够被记录

SET_PARAM可以编码

Q16.16输入0.25时RAW正确为16384

Slider和Numeric Input联动

Writable Channel动态生成控制项

历史Recording功能存在

IndexedDB可创建Session

CSV可以导出

页面刷新不会丢失UI配置
```

如果某项失败：

```
继续修复
```

不要直接结束。

# 62. 最终交付报告

完成以后创建：

```
IMPLEMENTATION_REPORT.md
```

内容包括：

```
实现了什么

目录结构

核心架构

协议实现说明

测试结果

Build结果

如何运行

如何进入Demo Mode

如何连接真实FPGA

目前已知限制

后续可扩展项
```

已知限制必须诚实写明。

不要把未测试的功能写成：

```
已验证正常
```

# 63. 当前范围之外

本次不要主动增加：

```
用户系统
云端数据库
账号登录
远程服务器
ESP32 WiFi
WebSocket
React
Vue
Electron
AI分析
PID自动整定
FFT
复杂双游标
多Chart工作区
插件系统
```

这些均属于未来版本。

V1 的重点是：

```
稳定UART
稳定协议
实时波形
参数修改
配置保存
历史记录
调试日志
良好架构
```

# 64. 最终目标

用户回来验收时，应当看到一个已经可以独立运行的 FPGA Monitor：

```
打开项目
↓
npm install
↓
npm run dev
↓
Edge / Chrome打开
↓
Demo Mode立即看到动态波形
```

连接真实 FPGA 后：

```
选择串口
↓
自动发现 Channel
↓
重命名 / 配颜色
↓
观察波形
↓
设置Y轴
↓
将某Channel设为Writable
↓
配置Slider范围
↓
修改参数
↓
PC自动根据DATA_TYPE编码
↓
发送SET_PARAM
↓
Communication Log显示TX Raw HEX
↓
FPGA Telemetry返回新值
↓
界面确认同步
↓
Record实验
↓
查看历史
↓
导出CSV
```

整个过程：

> 新增 FPGA Telemetry 参数原则上不需要修改网页源代码。

这条要求是本项目最重要的长期扩展性目标之一。