# protocol_rx 系列模块使用说明书

## 1. 模块用途

`protocol_rx` 系列模块用于实现：

```
电脑上位机
    ↓
UART字节流
    ↓
协议解析
    ↓
参数ID / 类型 / 数值
    ↓
更新FPGA内部参数
```

当前接收链：

```
uart_byte_rx.v
      ↓
 protocol_rx.v
      ↓
parameter_manager.v
      ↓
 PID / Control
```

原有：

```
uart_data_rx.v
```

仍然可以保留，用于普通固定长度 UART 数据接收，但**不参与协议接收**。

# 2. 各模块职责

## 2.1 uart_byte_rx.v

作用：

```
UART_RX波形
    ↓
1 Byte
```

输出：

```
data_byte
rx_Done
```

其中：

```
rx_Done = 1
```

只保持一个 `clk` 周期，表示：

```
成功接收到一个完整Byte
```

通常：

> 不需要修改该模块。

## 2.2 protocol_rx.v

作用：

```
UART Byte Stream
       ↓
识别 A5 5A
       ↓
解析 Protocol V1
       ↓
校验 CRC16
       ↓
输出 SET_PARAM
```

主要输出：

```
set_valid

set_param_id

set_param_type

set_param_value
```

一般情况下：

> 协议确定后不要频繁修改。

## 2.3 parameter_manager.v

这是 RX 侧最经常修改的模块。

作用：

```
SET_PARAM
   ↓
根据 PARAM_ID
   ↓
修改对应 FPGA 参数
```

例如：

```
ID = 0x10
TYPE = Q16.16
VALUE = 0x00004000
```

则：

```
Kp = 0.25
```

以后新增可以修改的 FPGA 参数，主要修改：

```
parameter_manager.v
```

# 3. 当前 PC → FPGA 协议

当前只实现：

```
MSG_TYPE = 0x10
SET_PARAM
```

不实现：

```
Command
GET_PARAM
ACK
LOG
```

因为当前需求只有：

> 电脑修改 FPGA 参数。

# 4. SET_PARAM 帧格式

完整格式：

```
┌────────┬─────┬──────────┬──────┬─────────────┬─────────────┬───────┐
│ HEADER │ VER │ MSG_TYPE │ SEQ  │ PAYLOAD_LEN │   PAYLOAD   │ CRC16 │
├────────┼─────┼──────────┼──────┼─────────────┼─────────────┼───────┤
│   2B   │ 1B  │    1B    │  2B  │     2B      │     6B      │  2B   │
└────────┴─────┴──────────┴──────┴─────────────┴─────────────┴───────┘
```

其中：

```
HEADER = A5 5A

VER = 01

MSG_TYPE = 10
```

# 5. SET_PARAM Payload

Payload 固定为：

```
PARAM_ID      1 Byte

DATA_TYPE     1 Byte

VALUE         4 Byte
```

共：

```
6 Byte
```

因此：

```
PAYLOAD_LEN = 06 00
```

# 6. 示例：PC修改 Kp

假设：

```
Kp = 0.25
```

Kp 数据类型：

```
Q16.16
```

转换：

```
0.25 × 65536
= 16384
```

十六进制：

```
0x00004000
```

Little Endian：

```
00 40 00 00
```

假设：

```
PARAM_ID = 0x10
TYPE     = 0x03
```

Payload：

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
10 03 00 40 00 00
CRC_L CRC_H
```

# 7. protocol_rx 接收完成后的输出

如果：

```
CRC正确

VER正确

MSG_TYPE正确

PAYLOAD_LEN正确
```

则输出：

```
set_param_id    = 0x10

set_param_type  = 0x03

set_param_value = 0x00004000

set_valid       = 1
```

其中：

```
set_valid
```

只保持：

```
1个 clk 周期
```

# 8. parameter_manager 如何工作

`parameter_manager` 只在：

```
set_valid == 1
```

时处理数据。

例如：

```
case(set_param_id)

    ID_KP:
    begin
        kp <= set_param_value;
    end

    ID_KI:
    begin
        ki <= set_param_value;
    end

    ID_KD:
    begin
        kd <= set_param_value;
    end

endcase
```

所以：

```
protocol_rx
```

负责：

```
“收到的是什么”
```

而：

```
parameter_manager
```

负责：

```
“收到以后改哪个变量”
```

两者必须分开。

# 9. parameter_manager 新增参数步骤

以后如果需要新增一个可修改参数，例如：

```
Target Position
```

推荐按照以下步骤。

## Step 1：增加 output

例如：

```
output reg signed [31:0] target_position;
```

## Step 2：定义 PARAM_ID

例如：

```
localparam ID_TARGET_POSITION = 8'h01;
```

注意：

> ID 必须与 TX Telemetry 中使用的 ID 完全一致。

例如：

```
TX:
0x01 = Target Position

RX:
0x01 = Target Position
```

不能出现同一个参数使用两个 ID。

# 10. Step 3：确定 DATA_TYPE

例如 Target Position 是：

```
INT32
```

那么：

```
localparam TYPE_INT32 = 8'h01;
```

对应协议：

```
0x01 = INT32
```

# 11. Step 4：增加 case

例如：

```
ID_TARGET_POSITION:
begin

    if(set_param_type == TYPE_INT32)
    begin

        target_position <= set_param_value;

        update_done <= 1'b1;

    end

    else
    begin

        type_error <= 1'b1;

    end

end
```

完成。

# 12. RX增加参数总结

新增一个 PC 可修改参数：

```
① parameter_manager 增加 output

② 分配 / 使用对应 PARAM_ID

③ 确认 DATA_TYPE

④ case 增加处理

⑤ 将 output 接到真正使用该参数的模块
```

通常：

```
protocol_rx.v
```

不需要修改。

# 13. 参数应该由谁保存

建议：

> 所有 PC 可以修改的参数统一由 `parameter_manager` 保存。

例如：

```
parameter_manager
│
├── Kp
├── Ki
├── Kd
├── Target
└── OutputLimit
```

不要出现：

```
Kp保存在PID模块
Ki保存在parameter_manager
Kd保存在顶层
```

否则后面管理会很乱。

推荐：

```
                 parameter_manager
                  /      |      \
                 /       |       \
               Kp       Ki       Kd
                │        │        │
                └────────┼────────┘
                         ▼
                        PID
```

# 14. 参数同时连接 TX

例如：

```
parameter_manager
        │
       Kp
        │
        ├────────→ PID
        │
        └────────→ telemetry_param_mux
```

这样 PC 修改：

```
Kp = 0.25
```

过程：

```
PC
↓
SET_PARAM
↓
protocol_rx
↓
parameter_manager
↓
Kp更新
↓
PID使用新Kp
↓
telemetry_param_mux
↓
protocol_tx
↓
PC重新收到Kp
```

这样可以实现：

```
设置值：0.25

FPGA实际值：0.25

✓ 已同步
```

因此目前不需要专门设计 ACK。

# 15. DATA_TYPE 必须检查

不能只看：

```
PARAM_ID
```

例如：

```
ID = Kp
```

理论类型必须：

```
Q16.16
```

如果 PC 错误发送：

```
ID   = Kp

TYPE = INT32
```

建议：

```
拒绝更新参数
```

并产生：

```
type_error
```

否则可能把：

```
1
```

当成：

```
Q16.16 Raw = 1
```

实际变成：

```
0.00001526
```

会导致参数错误。

# 16. PARAM_ID 错误

如果收到：

```
ID = 0x99
```

但 FPGA 没有这个参数：

```
parameter_manager
```

不应该修改任何数据。

产生：

```
id_error = 1
```

即可。

# 17. CRC 错误

如果：

```
CRC接收值
!=
FPGA计算值
```

则：

```
set_valid = 0
```

参数绝对不能更新。

同时：

```
crc_error = 1
```

用于调试。

原则：

> CRC错误的数据必须整体丢弃。

# 18. 格式错误

以下情况都应视为格式错误：

```
VER != 0x01

MSG_TYPE != 0x10

PAYLOAD_LEN != 6
```

此时：

```
format_error = 1
```

并重新寻找：

```
A5 5A
```

# 19. uart_data_rx 与 protocol_rx 的区别

`uart_data_rx` 适合：

```
固定接收4 Byte

↓
拼成32bit
```

例如：

```
12 34 56 78
```

组成：

```
0x12345678
```

而 `protocol_rx` 处理：

```
A5 5A
VER
TYPE
SEQ
LEN
PAYLOAD
CRC
```

所以协议接收必须：

```
UART_RX
↓
uart_byte_rx
↓
protocol_rx
```

不要：

```
UART_RX
↓
uart_data_rx
↓
protocol_rx
```

# 20. uart_data_rx 是否还能使用

可以继续保留。

新版：

```
uart_byte_rx
```

仍然保持接口：

```
clk
rst_n

baud_set
uart_rx

data_byte
rx_Done
```

因此旧：

```
uart_data_rx
```

理论上仍然可以正常使用。

但不要让：

```
uart_data_rx
```

和：

```
protocol_rx
```

同时实例化两个 `uart_byte_rx` 去处理同一个物理 UART，除非明确知道自己在做什么。

正式上位机工程：

> 推荐只使用 `protocol_rx`。

# 21. Q16.16 参数注意事项

例如 PC 页面显示：

```
Kp = 0.2
```

PC 后台转换：

```
0.2 × 65536
≈ 13107
```

发送：

```
RAW = 13107
```

FPGA收到以后：

```
parameter_manager
```

直接保存：

```
kp = 13107
```

不要再进行：

```
/65536
```

因为 FPGA PID 本身就是按照 Q16.16 使用该值。

即：

```
网页：
0.2

↓ encode

UART：
13107

↓ receive

FPGA：
Q16.16 RAW = 13107
```

# 22. INT32 参数注意事项

例如：

```
Target = -1000
```

PC转换为：

```
32bit补码
```

然后 Little Endian 发送。

FPGA：

```
set_param_value
```

保存的仍然是相同的：

```
32bit补码
```

如果最终参数定义为：

```
reg signed [31:0]
```

即可正常得到：

```
-1000
```

# 23. RX Byte Order

所有多字节数据统一：

```
Little Endian
```

例如：

```
0x12345678
```

UART发送：

```
78 56 34 12
```

protocol_rx 恢复：

```
VALUE[7:0]   = 78

VALUE[15:8]  = 56

VALUE[23:16] = 34

VALUE[31:24] = 12
```

最终：

```
0x12345678
```

# 24. SEQ

PC → FPGA 的每一个 SET_PARAM Frame 同样带：

```
SEQ
```

例如：

```
0000
0001
0002
0003
```

当前 FPGA：

```
last_seq
```

主要用于调试。

暂时不需要根据 SEQ：

```
拒绝重复帧
```

或者：

```
自动重发
```

V1 保持简单。

# 25. 不建议 PC 修改参数时直接连接 PID 寄存器

错误设计：

```
protocol_rx
↓
直接修改 PID内部寄存器
```

推荐：

```
protocol_rx
↓
parameter_manager
↓
PID
```

原因：

- 协议和控制算法解耦
- PID 不需要知道 UART 存在
- 参数可以同时用于 Telemetry
- 后面更方便增加参数
- Testbench 更容易测试

# 26. 模块间职责边界

必须坚持：

## uart_byte_rx

只负责：

```
UART波形
→ Byte
```

不能认识：

```
Kp
协议ID
CRC帧
```

## protocol_rx

只负责：

```
Byte Stream
→ 协议
→ ID / TYPE / VALUE
```

不能知道：

```
Kp具体存在哪里
PID怎么算
```

## parameter_manager

只负责：

```
ID
→ 对应FPGA参数
```

不能处理：

```
UART波形
CRC
帧头
```

# 27. 推荐工程结构

```
UART/
│
├── uart_byte_tx.v
├── uart_byte_rx.v
│
├── uart_data_tx.v
├── uart_data_rx.v
│
├── protocol_tx.v
├── protocol_rx.v
│
├── telemetry_param_mux.v
└── parameter_manager.v
```

其中正式上位机通信：

```
FPGA → PC

telemetry_param_mux
        ↓
protocol_tx
        ↓
uart_byte_tx
```

以及：

```
PC → FPGA

uart_byte_rx
        ↓
protocol_rx
        ↓
parameter_manager
```

# 28. 当前 RX V1 功能范围

目前只实现：

```
SET_PARAM
```

即：

```
PC修改FPGA参数
```

暂时不实现：

```
GET_PARAM
COMMAND
ACK
LOG
RESET
START
STOP
```

因为：

```
Telemetry
```

已经可以负责参数回读。

保持 V1 简单。

# 29. 日常新增可调参数时需要做什么

以后想让 PC 可以修改一个新参数，只需要记住：

```
① 这个参数必须有唯一 PARAM_ID

② 明确 DATA_TYPE

③ parameter_manager 增加 output

④ parameter_manager 增加 case

⑤ 将 output 接入实际业务模块

⑥ 如果需要网页确认修改结果，
   同时加入 telemetry_param_mux
```

例如：

```
新增 Speed_Kp

ID = 0x20
TYPE = Q16.16
```

然后：

```
Parameter Manager
↓
增加 Speed_Kp
↓
接入 Speed PID
↓
接入 Telemetry MUX
```

完成。

# 30. TX 与 RX 的对称关系

整个通信库最终可以理解为：

```
================ FPGA → PC ================

FPGA数据
   ↓
telemetry_param_mux
   ↓
protocol_tx
   ↓
uart_byte_tx
   ↓
PC


================ PC → FPGA ================

PC
   ↓
uart_byte_rx
   ↓
protocol_rx
   ↓
parameter_manager
   ↓
FPGA参数
```

其中：

```
telemetry_param_mux
```

决定：

> 哪些数据可以被电脑看到。

而：

```
parameter_manager
```

决定：

> 哪些数据允许被电脑修改。

这两个模块是后续项目中最主要的配置入口。

# 31. 最重要的使用原则

整个 RX 系列可以浓缩为：

```
protocol_rx：
负责“收到什么”

parameter_manager：
负责“修改什么”
```

后续增加参数时：

> 优先修改 `parameter_manager.v`，不要随意改动 `protocol_rx.v`。

如果一个参数既需要：

```
网页显示
```

又需要：

```
网页修改
```

则同时加入：

```
telemetry_param_mux
+
parameter_manager
```

即可形成完整的双向参数通道。