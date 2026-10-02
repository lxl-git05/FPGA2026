# protocol_tx 系列模块使用说明书

## 1. 模块用途

`protocol_tx` 系列模块用于实现：

```
FPGA内部数据
    ↓
参数选择
    ↓
协议打包
    ↓
UART发送
    ↓
电脑上位机
```

当前发送链由以下模块组成：

```
telemetry_param_mux.v
        ↓
   protocol_tx.v
        ↓
   uart_byte_tx.v
        ↓
      UART_TX
```

其中原来的：

```
uart_data_tx.v
```

仍然可以继续使用，但是它与 `protocol_tx` 属于两套不同的上层发送方式。

# 2. 各模块职责

## 2.1 uart_byte_tx.v

功能：

```
1 Byte
   ↓
UART波形
```

输入：

```
data_byte
send_en
baud_set
```

输出：

```
uart_tx
tx_done
uart_state
```

一般情况下：

> 不需要修改。

## 2.2 protocol_tx.v

功能：

```
参数
 ↓
协议帧
 ↓
CRC
 ↓
UART
```

负责自动生成：

```
A5 5A

VER

MSG_TYPE

SEQ

PAYLOAD_LEN

COUNT

PARAM_ID
PARAM_TYPE
PARAM_VALUE

...

CRC16
```

同时负责：

- SEQ 自动累加
- Payload 长度自动计算
- 参数自动遍历
- VALUE 按 Little Endian 发送
- CRC16/MODBUS 自动计算
- 整帧发送完成提示

一般情况下：

> 写好以后不要修改。

## 2.3 telemetry_param_mux.v

这是用户最经常修改的模块。

功能：

```
param_index
     ↓
   case
     ↓
选择需要发送的数据
     ↓
param_id
param_type
param_value
```

例如：

```
param_index = 0
```

返回：

```
Target Position
ID   = 0x01
TYPE = INT32
VALUE
```

# 3. 推荐工程结构

建议：

```
UART/
│
├── uart_byte_tx.v
├── uart_data_tx.v
│
├── protocol_tx.v
└── telemetry_param_mux.v
```

以后如果增加接收：

```
UART/
│
├── uart_byte_tx.v
├── uart_byte_rx.v
│
├── uart_data_tx.v
│
├── protocol_tx.v
├── protocol_rx.v
│
└── telemetry_param_mux.v
```

# 4. 第一次部署步骤

第一次把协议加入工程时，按照以下顺序操作。

## Step 1：加入三个模块

添加：

```
uart_byte_tx.v
protocol_tx.v
telemetry_param_mux.v
```

其中：

```
protocol_tx
```

内部已经实例化：

```
uart_byte_tx
```

因此顶层不需要再单独实例化 `uart_byte_tx`。

# 5. Step 2：找到需要上传的数据

例如当前 FPGA 中存在：

```
target_position
position
error
pid_output

kp
ki
kd
```

这些数据可能分别来自：

```
PID
Encoder
Motor
Control
```

等模块。

要求：

> 所有需要发送的数据最终都必须能够在顶层模块中通过 wire 获得。

例如：

```
wire signed [31:0] position;
```

编码器：

```
encoder u_encoder
(
    .position(position)
);
```

然后该 `position` 可以同时连接到：

```
PID
MUX
其他模块
```

# 6. 如果数据是模块内部变量怎么办

例如 PID 内部存在：

```
reg signed [31:0] error;
```

但没有输出端口。

那么顶层无法直接使用。

需要给 PID 增加：

```
output signed [31:0] error_out;
```

然后：

```
assign error_out = error;
```

顶层：

```
wire signed [31:0] error;
```

例化：

```
pid u_pid
(
    ...
    .error_out(error)
);
```

然后才能连接到 MUX。

原则：

```
模块内部变量
      ↓
   output
      ↓
顶层 wire
      ↓
MUX input
```

不要在正式 RTL 中直接写：

```
u_pid.error
```

进行跨模块访问。

# 7. Step 3：修改 telemetry_param_mux

以后增加参数时，主要就是修改这个模块。

增加一个参数通常只需要 4 步。

# 8. MUX 添加新参数的标准流程

假设现在需要增加：

```
motor_speed
```

## 第一步：增加 input

例如：

```
input signed [31:0] motor_speed,
```

## 第二步：分配 PARAM_ID

例如：

```
localparam ID_MOTOR_SPEED = 8'h05;
```

注意：

每个参数 ID 必须唯一。

例如：

```
0x01 Target Position
0x02 Position
0x03 Error
0x04 PID Output
0x05 Motor Speed

0x10 Kp
0x11 Ki
0x12 Kd
```

# 9. 第三步：在 case 中增加参数

假设现在原本有：

```
0 ~ 6
```

共 7 个参数。

增加：

```
8'd7:
begin

    param_id = ID_MOTOR_SPEED;

    param_type = TYPE_INT32;

    param_value = motor_speed;

end
```

# 10. 第四步：修改 PARAM_COUNT

原来：

```
localparam [7:0] PARAM_COUNT = 8'd7;
```

修改为：

```
localparam [7:0] PARAM_COUNT = 8'd8;
```

完成。

# 11. MUX 添加参数总结

以后增加一个变量：

```
新增 input
    ↓
新增 PARAM_ID
    ↓
新增 case
    ↓
PARAM_COUNT + 1
```

也就是：

```
4步
```

不需要修改：

```
protocol_tx.v
uart_byte_tx.v
```

# 12. 数据类型选择

当前协议支持：

```
localparam TYPE_INT32  = 8'h01;
localparam TYPE_UINT32 = 8'h02;
localparam TYPE_Q16_16 = 8'h03;
localparam TYPE_Q8_24  = 8'h04;
```

## 普通有符号整数

例如：

```
position
error
pid_output
```

使用：

```
param_type = TYPE_INT32;
```

## 普通无符号整数

例如：

```
counter
timer
```

使用：

```
param_type = TYPE_UINT32;
```

## Q16.16

例如：

```
Kp
Ki
Kd
```

内部：

```
0.25
```

表示为：

```
0.25 × 65536
= 16384
```

FPGA直接发送：

```
16384
```

MUX：

```
param_type = TYPE_Q16_16;
param_value = kp;
```

电脑自动解析成：

```
0.25
```

FPGA不需要进行浮点转换。

# 13. 一个完整 MUX 参数示例

例如：

```
8'd4:
begin

    param_id = ID_KP;

    param_type = TYPE_Q16_16;

    param_value = kp;

end
```

表示：

```
第4号发送参数

参数名称：
Kp

协议ID：
0x10

数据格式：
Q16.16

实际数据：
kp
```

# 14. Step 4：在顶层建立协议连接 wire

需要：

```
wire [7:0] param_count;

wire [7:0] param_index;

wire [7:0] param_id;

wire [7:0] param_type;

wire [31:0] param_value;
```

发送控制：

```
reg protocol_send_en;

wire protocol_busy;

wire protocol_done;
```

# 15. Step 5：实例化 MUX

例如：

```
telemetry_param_mux u_telemetry_param_mux
(
    .param_index(param_index),

    .target_position(target_position),
    .position(position),
    .error(error),
    .pid_output(pid_output),

    .kp(kp),
    .ki(ki),
    .kd(kd),

    .param_count(param_count),

    .param_id(param_id),
    .param_type(param_type),
    .param_value(param_value)
);
```

# 16. Step 6：实例化 protocol_tx

```
protocol_tx u_protocol_tx
(
    .clk(clk),

    .rst_n(rst_n),

    .send_en(protocol_send_en),

    .baud_set(3'd4),

    .param_count(param_count),

    .param_index(param_index),

    .param_id(param_id),

    .param_type(param_type),

    .param_value(param_value),

    .uart_tx(uart_tx),

    .tx_busy(protocol_busy),

    .tx_done(protocol_done)
);
```

# 17. protocol_tx 和 MUX 的关系

关系如下：

```
             protocol_tx

                 │
                 │ param_index
                 ▼

        telemetry_param_mux

                 │
          ┌──────┼──────┐
          │      │      │
          ▼      ▼      ▼
         ID     TYPE   VALUE

          │      │      │
          └──────┼──────┘
                 │
                 ▼

             protocol_tx
```

例如：

```
protocol_tx：
param_index = 0
```

MUX：

```
param_id    = 01
param_type  = 01
param_value = target_position
```

发送完成以后：

```
param_index = 1
```

MUX：

```
param_id    = 02
param_type  = 01
param_value = position
```

一直到：

```
param_index = param_count - 1
```

然后 protocol_tx 自动发送 CRC。

# 18. Step 7：产生发送触发信号

`send_en` 必须是：

```
1个 clk 周期高电平
```

不要长期保持：

```
protocol_send_en = 1;
```

推荐：

```
always @(posedge clk or negedge rst_n)
begin

    if (!rst_n)
    begin

        protocol_send_en <= 1'b0;

    end

    else
    begin

        protocol_send_en <= 1'b0;

        if (send_flag && !protocol_busy)
        begin

            protocol_send_en <= 1'b1;

        end

    end

end
```

# 19. 例如 20ms 上传一次

如果：

```
PID周期 = 20ms
```

可以：

```
每20ms
   ↓
产生 send_flag
   ↓
检查 protocol_busy
   ↓
空闲
   ↓
send_en = 1clk
```

例如：

```
if (pid_20ms_flag && !protocol_busy)
begin

    protocol_send_en <= 1'b1;

end
```

这样就实现：

```
50Hz Telemetry
```

# 20. tx_busy 和 tx_done

## tx_busy

当：

```
tx_busy = 1
```

表示：

```
当前正在发送完整协议帧
```

不要再次启动发送。

因此：

```
if (!protocol_busy)
```

后才能发送下一帧。

## tx_done

当：

```
tx_done = 1
```

表示：

```
一整帧发送完成
```

仅保持：

```
1个 clk
```

可用于调试或统计。

# 21. UART 波特率

当前：

```
baud_set = 3'd4;
```

对应：

```
115200
```

对于 50MHz 时钟：

```
0 = 9600
1 = 19200
2 = 38400
3 = 57600
4 = 115200
```

通常建议：

```
115200 8N1
```

# 22. 当前协议发送的数据结构

例如：

```
Target = 1000
Position = 876
Kp = 0.25
```

最终 Payload：

```
03

01 01 E8 03 00 00

02 01 6C 03 00 00

10 03 00 40 00 00
```

其中：

```
03
```

表示：

```
3个参数
```

# 23. 完整协议帧

格式：

```
A5 5A

VER

MSG_TYPE

SEQ_L
SEQ_H

LEN_L
LEN_H

COUNT

PARAM0

PARAM1

...

CRC_L
CRC_H
```

例如：

```
A5 5A
01
01
00 00
13 00
03

01 01 E8 03 00 00
02 01 6C 03 00 00
10 03 00 40 00 00

CRC_L CRC_H
```

# 24. 新增参数实战例子

假设增加：

```
Velocity
```

来源：

```
wire signed [31:0] velocity;
```

## MUX input

加入：

```
input signed [31:0] velocity,
```

## ID

```
localparam ID_VELOCITY = 8'h05;
```

## case

```
8'd7:
begin

    param_id = ID_VELOCITY;

    param_type = TYPE_INT32;

    param_value = velocity;

end
```

## 数量

修改：

```
PARAM_COUNT = 8'd8;
```

## 顶层连接

```
.velocity(velocity),
```

完成。

# 25. 删除参数

删除一个参数时：

```
删除 case
    ↓
重新排列 param_index
    ↓
PARAM_COUNT - 1
    ↓
删除对应 input（如果不再需要）
```

注意：

`param_index` 最好连续：

```
0
1
2
3
4
...
```

不要写成：

```
0
1
4
7
```

否则 protocol_tx 遍历时会出现无效项。

# 26. PARAM_ID 和 param_index 的区别

非常重要。

## param_index

这是 FPGA 内部遍历使用：

```
0
1
2
3
...
```

意义只是：

```
“现在发送第几个参数”
```

电脑看不到它。

## PARAM_ID

这是协议参数编号。

例如：

```
0x01 Target
0x02 Position
0x10 Kp
```

电脑通过它判断：

```
当前收到的是什么参数
```

所以：

```
param_index
```

可以因为 MUX 调整而改变。

但是：

```
PARAM_ID
```

一旦确定以后尽量不要改。

例如：

```
0x10 永远表示 Kp
```

# 27. 参数顺序能不能变化

可以。

例如原来：

```
Index 0 → Target ID01
Index 1 → Position ID02
Index 2 → Kp ID10
```

以后变成：

```
Index 0 → Position ID02
Index 1 → Kp ID10
Index 2 → Target ID01
```

电脑依然能够识别。

因为电脑看的是：

```
PARAM_ID
```

而不是：

```
param_index
```

# 28. 一个参数必须满足什么条件

当前 V1 要求：

```
VALUE 固定为 32bit
```

所以：

```
INT32
UINT32
Q16.16
Q8.24
```

都正好是：

```
32bit
```

如果原数据只有：

```
wire [15:0] pwm;
```

可以：

```
param_value = {16'd0, pwm};
```

并使用：

```
UINT32
```

# 29. signed 数据注意事项

例如：

```
input signed [31:0] error;
```

赋给：

```
reg [31:0] param_value;
```

是没问题的。

FPGA实际传输的是：

```
32bit补码
```

例如：

```
-520
```

会发送：

```
F8 FD FF FF
```

电脑看到：

```
TYPE = INT32
```

以后按照有符号 32bit 解析，就能恢复：

```
-520
```

# 30. Q16.16 数据注意事项

例如：

```
Kp = 0.2
```

不要让 FPGA 转成：

```
"0.2"
```

也不要转成 float。

FPGA只保留：

```
Q16.16 Raw
```

即：

```
0.2 × 65536
≈ 13107
```

MUX：

```
param_value = kp;

param_type = TYPE_Q16_16;
```

电脑负责：

```
13107 / 65536
≈ 0.199997
```

# 31. 当前设计的数据一致性

protocol_tx 在发送每个参数之前都会锁存：

```
param_id
param_type
param_value
```

所以：

```
一个32bit VALUE的4个Byte
```

一定来自同一次数据。

不会出现：

```
Byte0 = Position旧值
Byte1 = Position新值
```

的问题。

# 32. 需要注意：整帧不是严格同时采样

例如：

```
Target
Position
Error
PID Output
Kp
Ki
Kd
```

它们是逐个参数锁存的。

因此整帧发送过程中，如果：

```
Position
```

一直变化，那么不同参数的采样时间可能相差几毫秒。

当前用于：

```
PID调参
波形查看
状态监测
```

通常没有问题。

如果后面需要：

```
所有参数必须属于完全相同的控制周期
```

再增加：

```
Frame Snapshot
```

即可。

当前不需要。

# 33. uart_data_tx 是否还能使用

可以。

因为新版：

```
uart_byte_tx
```

保持原接口：

```
clk
rst_n

data_byte
send_en
baud_set

uart_tx
tx_done
uart_state
```

所以原来的：

```
uart_data_tx
```

仍然可以正常实例化。

但是注意：

> 同一个物理 UART_TX 引脚不能同时由 `uart_data_tx` 和 `protocol_tx` 驱动。

例如不允许：

```
uart_data_tx ──┐
               ├── uart_tx
protocol_tx ───┘
```

除非以后增加发送仲裁模块。

当前建议：

正式上位机协议使用：

```
protocol_tx
```

普通固定数据测试时：

```
uart_data_tx
```

二选一。

# 34. 第一次测试建议

不要第一次就接真实 PID。

建议先用固定值：

```
wire signed [31:0] target_position = 32'd1000;

wire signed [31:0] position = 32'd876;

wire signed [31:0] error = 32'd124;

wire signed [31:0] pid_output = -32'sd520;
```

Q16.16：

```
wire signed [31:0] kp = 32'sd16384;
```

也就是：

```
Kp = 0.25
```

然后用串口工具查看 HEX。

确认能看到类似：

```
A5 5A ...
```

再进入电脑 HTML 协议解析。

# 35. 推荐开发顺序

建议按照：

```
① uart_byte_tx
        ↓
② protocol_tx
        ↓
③ telemetry_param_mux
        ↓
④ 固定测试数据
        ↓
⑤ 串口HEX验证
        ↓
⑥ HTML协议解析
        ↓
⑦ 实时曲线
        ↓
⑧ 接入真正PID
```

不要一开始同时调：

```
FPGA PID
UART
Protocol
HTML
曲线
```

否则出错时不好定位。

# 36. 日常使用时真正需要记住的内容

以后你使用这个库，实际上只需要记住：

```
想发送一个新参数
```

执行：

```
① 顶层拿到这个信号

② MUX增加 input

③ 分配 PARAM_ID

④ case增加一项

⑤ 选择 DATA_TYPE

⑥ PARAM_COUNT + 1
```

例如：

```
8'd8:
begin

    param_id = 8'h20;

    param_type = TYPE_INT32;

    param_value = current;

end
```

完成。

# 37. 最终设计思想

整个发送库可以理解为：

```
                FPGA业务模块

      PID    Encoder    Motor    Sensor
       │        │         │        │
       └────────┴─────────┴────────┘
                     │
                     ▼
          telemetry_param_mux
                     │
                ID TYPE VALUE
                     │
                     ▼
               protocol_tx
                     │
               Protocol V1
                     │
                     ▼
              uart_byte_tx
                     │
                     ▼
                  UART_TX
                     │
                     ▼
                  PC HTML
```

其中：

```
业务模块
```

只负责产生数据。

```
telemetry_param_mux
```

只负责决定：

```
发送哪些数据
protocol_tx
```

只负责：

```
如何按照协议发送
uart_byte_tx
```

只负责：

```
如何产生UART波形
```

这样各模块职责清晰，后续扩展参数时主要只修改：

```
telemetry_param_mux.v
```

即可。