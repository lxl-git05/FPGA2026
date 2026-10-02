# FPGA UART 调参协议 V1.0

## 1. 协议用途

本协议用于 FPGA 与电脑上位机之间的 UART 通信，主要用于：

- FPGA 实时数据上传
- PID 参数调节
- 编码器、PWM、误差等数据显示
- Q 格式数据传输
- 上位机实时波形绘制
- 参数查询与修改
- 后续扩展 ESP32、WiFi、WebSocket 等通信方式

设计原则：

1. FPGA 只负责发送原始二进制数据。
2. 浮点显示、Q 格式转换由电脑完成。
3. 一帧可以发送多个不同类型的参数。
4. 所有多字节数据统一使用小端序 Little Endian。
5. 协议应方便 FPGA 状态机实现，同时保留后续扩展能力。

# 2. UART 配置

默认 UART 参数：

```
Baud Rate : 115200
Data Bits : 8
Stop Bits : 1
Parity    : None
Flow Ctrl : None
```

即：

```
115200 8N1
```

# 3. 完整数据帧

数据帧格式：

```
┌────────┬─────┬──────────┬──────┬─────────────┬────────────┬───────┐
│ HEADER │ VER │ MSG_TYPE │ SEQ  │ PAYLOAD_LEN │  PAYLOAD   │ CRC16 │
├────────┼─────┼──────────┼──────┼─────────────┼────────────┼───────┤
│   2B   │ 1B  │    1B    │  2B  │     2B      │    N B     │  2B   │
└────────┴─────┴──────────┴──────┴─────────────┴────────────┴───────┘
```

所有多字节数据均采用：

```
Little Endian
```

# 4. 帧头 HEADER

固定为：

```
A5 5A
```

作用：

- 判断一帧数据的开始
- 串口丢字节后重新同步

例如：

```
A5 5A 01 01 ...
```

检测到：

```
A5 5A
```

即可认为后面可能是一帧新的数据。

# 5. 协议版本 VER

当前版本：

```
VER = 0x01
```

即：

```
Protocol V1
```

未来协议发生较大变化时可以升级：

```
0x01 = V1
0x02 = V2
...
```

# 6. 消息类型 MSG_TYPE

当前定义：

| MSG_TYPE | 名称           | 方向      | 作用         |
| -------- | -------------- | --------- | ------------ |
| `0x01`   | TELEMETRY      | FPGA → PC | 实时数据上传 |
| `0x10`   | SET_PARAM      | PC → FPGA | 修改参数     |
| `0x11`   | GET_PARAM      | PC → FPGA | 查询参数     |
| `0x12`   | PARAM_RESPONSE | FPGA → PC | 参数查询应答 |
| `0x20`   | COMMAND        | PC → FPGA | 控制命令     |
| `0x21`   | COMMAND_ACK    | FPGA → PC | 命令应答     |
| `0x30`   | LOG            | FPGA → PC | 调试日志     |
| `0x31`   | ERROR          | FPGA → PC | 错误信息     |

目前第一阶段重点实现：

```
0x01 TELEMETRY
0x10 SET_PARAM
0x11 GET_PARAM
0x12 PARAM_RESPONSE
```

其他类型暂时保留。

# 7. SEQ 帧序号

SEQ 长度：

```
2 Byte
```

范围：

```
0 ~ 65535
```

每发送一帧：

```
SEQ = SEQ + 1
```

例如：

```
0000
0001
0002
...
FFFE
FFFF
0000
```

采用自然溢出。

作用：

- 判断是否丢包
- 判断数据顺序
- 调试通信问题

由于采用小端序：

```
SEQ = 42
```

即：

```
0x002A
```

实际发送：

```
2A 00
```

# 8. PAYLOAD_LEN

长度：

```
2 Byte
```

表示：

> PAYLOAD 区域包含多少个 Byte。

不包含：

```
HEADER
VER
MSG_TYPE
SEQ
PAYLOAD_LEN
CRC16
```

例如 Payload 有 19 Byte：

```
19 = 0x0013
```

实际发送：

```
13 00
```

# 9. CRC16

采用：

```
CRC-16/MODBUS
```

参数：

```
Polynomial : 0xA001
Initial    : 0xFFFF
```

CRC 计算范围：

```
VER
↓
MSG_TYPE
↓
SEQ
↓
PAYLOAD_LEN
↓
PAYLOAD
```

不参与 CRC：

```
HEADER A5 5A
CRC16本身
```

CRC16 最终按照小端序发送：

```
CRC_L
CRC_H
```

例如：

```
CRC = 0x1234
```

串口发送：

```
34 12
```

# 10. TELEMETRY 实时数据格式

当：

```
MSG_TYPE = 0x01
```

Payload 格式为：

```
COUNT

PARAM_1
PARAM_2
PARAM_3
...
```

其中：

```
COUNT = 本帧包含多少个参数
```

COUNT 长度：

```
1 Byte
```

每一个参数固定占：

```
6 Byte
```

格式：

```
┌──────────┬───────────┬─────────────────────┐
│ PARAM_ID │ DATA_TYPE │        VALUE        │
├──────────┼───────────┼─────────────────────┤
│    1B    │    1B     │         4B          │
└──────────┴───────────┴─────────────────────┘
```

因此：

```
一个参数 = 6 Byte
```

# 11. PARAM_ID 参数编号

推荐定义：

| ID     | 参数            |
| ------ | --------------- |
| `0x01` | Target Position |
| `0x02` | Position        |
| `0x03` | Error           |
| `0x04` | PID Output      |
| `0x05` | Velocity        |
| `0x06` | PWM             |
| `0x10` | Kp              |
| `0x11` | Ki              |
| `0x12` | Kd              |

FPGA 中建议统一定义，例如：

```
localparam PARAM_TARGET_POS = 8'h01;
localparam PARAM_POSITION   = 8'h02;
localparam PARAM_ERROR      = 8'h03;
localparam PARAM_PID_OUT    = 8'h04;
localparam PARAM_VELOCITY   = 8'h05;
localparam PARAM_PWM        = 8'h06;

localparam PARAM_KP         = 8'h10;
localparam PARAM_KI         = 8'h11;
localparam PARAM_KD         = 8'h12;
```

后续新增参数只需要继续分配新的 ID。

# 12. DATA_TYPE 数据类型

当前 V1 定义：

| DATA_TYPE | 类型   | 说明                |
| --------- | ------ | ------------------- |
| `0x01`    | INT32  | 32 位有符号整数     |
| `0x02`    | UINT32 | 32 位无符号整数     |
| `0x03`    | Q16.16 | 16位整数 + 16位小数 |
| `0x04`    | Q8.24  | 8位整数 + 24位小数  |

暂时保留：

```
0x05 ~ 0xFF
```

以后可以增加：

```
FLOAT32
Q1.31
Q24.8
BOOL
ENUM
```

第一版暂时不需要。

# 13. INT32 示例

假设：

```
Target Position = 1000
```

定义：

```
PARAM_ID = 0x01
DATA_TYPE = 0x01
```

1000 转成十六进制：

```
1000 = 0x000003E8
```

由于使用小端序：

```
E8 03 00 00
```

因此完整参数：

```
01 01 E8 03 00 00
│  │  └────────── VALUE = 1000
│  └───────────── INT32
└──────────────── Target Position
```

# 14. 负数 INT32 示例

假设：

```
PID Output = -520
```

32 位补码：

```
-520 = 0xFFFFFDF8
```

小端序发送：

```
F8 FD FF FF
```

定义：

```
PARAM_ID  = 0x04
DATA_TYPE = 0x01
```

最终：

```
04 01 F8 FD FF FF
```

电脑按照 INT32 解析即可得到：

```
-520
```

# 15. Q16.16 示例

假设：

```
Kp = 0.25
```

Q16.16 转换：

```
Raw = 0.25 × 65536
    = 16384
```

十六进制：

```
16384 = 0x00004000
```

小端序：

```
00 40 00 00
```

定义：

```
PARAM_ID  = 0x10
DATA_TYPE = 0x03
```

最终：

```
10 03 00 40 00 00
```

电脑收到后：

```
Raw = 16384
```

根据：

```
DATA_TYPE = Q16.16
```

进行：

```
Value = Raw / 65536
```

得到：

```
Kp = 0.25
```

FPGA 不需要进行浮点转换。

# 16. Q16.16 的负数示例

例如：

```
Value = -1.5
```

转换：

```
-1.5 × 65536
= -98304
```

FPGA直接发送这个 32 位补码值。

电脑解析为 signed int32：

```
raw = -98304
```

然后：

```
value = -98304 / 65536
      = -1.5
```

# 17. 多种数据混合发送示例

假设 FPGA 当前需要上传：

```
Target Position = 1000       INT32
Position        = 876        INT32
Kp              = 0.25       Q16.16
```

参数数量：

```
COUNT = 3
```

第一个参数：

```
01 01 E8 03 00 00
```

表示：

```
ID    = Target
TYPE  = INT32
VALUE = 1000
```

第二个：

```
02 01 6C 03 00 00
```

表示：

```
ID    = Position
TYPE  = INT32
VALUE = 876
```

第三个：

```
10 03 00 40 00 00
```

表示：

```
ID    = Kp
TYPE  = Q16.16
VALUE = 0.25
```

因此整个 Payload：

```
03

01 01 E8 03 00 00
02 01 6C 03 00 00
10 03 00 40 00 00
```

Payload 长度：

```
1 + 3 × 6
= 19 Byte
= 0x0013
```

# 18. 完整 TELEMETRY 帧示例

假设：

```
VER      = 01
MSG_TYPE = 01
SEQ      = 42
LEN      = 19
```

完整数据：

```
A5 5A

01
01

2A 00

13 00

03

01 01 E8 03 00 00
02 01 6C 03 00 00
10 03 00 40 00 00

CRC_L CRC_H
```

整理成一行：

```
A5 5A 01 01 2A 00 13 00
03
01 01 E8 03 00 00
02 01 6C 03 00 00
10 03 00 40 00 00
CRC_L CRC_H
```

电脑解析后得到：

```
Target Position = 1000
Position        = 876
Kp              = 0.25
```

# 19. SET_PARAM 修改参数

电脑修改 FPGA 参数时：

```
MSG_TYPE = 0x10
```

Payload：

```
PARAM_ID
DATA_TYPE
VALUE
```

例如电脑希望：

```
Kp = 0.2
```

Q16.16：

```
0.2 × 65536
≈ 13107
```

十六进制：

```
13107 = 0x00003333
```

小端：

```
33 33 00 00
```

Payload：

```
10 03 33 33 00 00
```

含义：

```
10
│
└── 修改 Kp

03
│
└── 数据类型 Q16.16

33 33 00 00
│
└── Raw = 13107
    Kp ≈ 0.199997
```

完整帧：

```
A5 5A
01
10
SEQ_L SEQ_H
06 00
10 03 33 33 00 00
CRC_L CRC_H
```

# 20. GET_PARAM 查询参数

电脑查询 Kp：

```
MSG_TYPE = 0x11
```

Payload：

```
10
```

即：

```
PARAM_ID = 0x10
```

FPGA收到以后返回：

```
MSG_TYPE = 0x12
```

例如：

```
10 03 33 33 00 00
```

表示：

```
Kp ≈ 0.2
```

# 21. 上位机数据解析规则

电脑收到每个参数：

```
PARAM_ID
DATA_TYPE
VALUE[4]
```

首先将 VALUE 合成为一个 32 位原始值：

```
raw
```

然后根据 DATA_TYPE 转换。

例如：

```
switch (type)
{
    case 0x01:
        // INT32
        value = rawSigned;
        break;

    case 0x02:
        // UINT32
        value = rawUnsigned;
        break;

    case 0x03:
        // Q16.16
        value = rawSigned / 65536.0;
        break;

    case 0x04:
        // Q8.24
        value = rawSigned / 16777216.0;
        break;
}
```

因此 FPGA 无需处理：

```
ASCII
printf
小数转字符串
Q格式转float
```

这些全部由电脑完成。

# 22. 上位机数据保存原则

电脑端建议分成三层。

## 实时数据显示

只保存最新值，例如：

```
Target   = 1000
Position = 876
Kp       = 0.25
```

## 实时波形缓存

内存只保存最近一定数量的数据，例如：

```
10000 Point
```

如果采样率：

```
50Hz
```

则：

```
10000 / 50
= 200s
```

即显示最近约：

```
3.3分钟
```

防止网页因为持续运行而越来越卡。

## 完整数据记录

完整实验数据可以保存到：

```
IndexedDB
```

用于网页内部历史记录。

同时支持导出：

```
CSV
BIN
```

例如 CSV：

```
time,target,position,error,pid_out,kp,ki,kd
0.000,1000,0,1000,2500,0.2,0.01,0.05
0.020,1000,20,980,2500,0.2,0.01,0.05
0.040,1000,51,949,2500,0.2,0.01,0.05
```

用于后续：

```
Python
MATLAB
Excel
Origin
```

分析。

# 23. V1 协议总结

最终 V1 固定为：

```
HEADER      A5 5A

VER         1 Byte

MSG_TYPE    1 Byte

SEQ         2 Byte

PAYLOAD_LEN 2 Byte

PAYLOAD     N Byte

CRC16       2 Byte
```

字节序：

```
Little Endian
```

Telemetry 单参数：

```
PARAM_ID  1B
TYPE      1B
VALUE     4B
```

即：

```
6 Byte / Parameter
```

主要 DATA_TYPE：

```
01 = INT32
02 = UINT32
03 = Q16.16
04 = Q8.24
```

主要消息：

```
01 = TELEMETRY

10 = SET_PARAM
11 = GET_PARAM
12 = PARAM_RESPONSE
```

# 24. 当前开发阶段

第一阶段 FPGA：

```
uart_byte_tx.v
uart_byte_rx.v

↓

protocol_tx.v
protocol_rx.v

↓

crc16.v

↓

parameter_manager.v
```

第二阶段电脑：

```
index.html

↓

Web Serial

↓

protocol.js

↓

实时参数
实时曲线
PID调参
历史数据
CSV导出
```

FPGA 和电脑均严格按照本文档中的 Protocol V1 实现。

后续即使增加：

```
ESP32
WiFi
WebSocket
Python
```

FPGA Protocol V1 本身仍然可以保持不变。