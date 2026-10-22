# 配置接口与单位

`config_bank`是唯一写入者。输入：`write_valid`、`write_id[7:0]`、`write_micro signed[63:0]`，仅在`ready=1`时接受请求。
`write_micro`统一表示实际数值×1000000；例如period=5ms对应5000000，双环开关1对应1000000。
转换器采用128位移位累加及恢复除法，最终检查signed32范围。没有请求队列；上层需要遵守ready。正常115200串口字节间隔远大于单次转换时间。

## 首版UART开放项

| ID(hex) | 名称 | 单位 |
|---|---|---|
| 00 / 01 / 02 | Kp_A / Ki_A / Kd_A | 连续C参数，输出百分比/ADC及对应时间量纲 |
| 03 | goal_A | 直立ADC基准，当前默认2180 |
| 04 / 05 / 06 | Kp_B / Ki_B / Kd_B | 连续C参数，输出ADC修正/编码器计数及时间量纲 |
| 07 | goal_B | 编码器目标计数 |

增益写入递增对应`epoch_a`或`epoch_b`，控制器在下一控制边界锁存增益，先clear后tick。
目标写入不递增增益epoch，因此不会清积分和误差历史。
goal_A必须保证其±fall_adc严格位于两端有效阈值内；goal_B必须在±travel_counts内。

## 首版保留的内部全局写入项

下列ID只在`stopped=1`时接受，**UART解析器不识别这些命令名称**。当前板级将配置端口接到八个PID命令，日后可在此增加调试总线或非易失存储加载。

| ID(hex) | 寄存器 | 范围/校验 |
|---|---|---|
| 80 | dual_loop | 0 / 1 |
| 81 | auto_start | 0 / 1 |
| 82 / 83 | period_a_ms / period_b_ms | 1～1000ms，事务重算该环三个Q系数 |
| 84 | capture_adc | 1～fall_adc，且不小于outer_limit_adc |
| 85 | fall_adc | 不小于capture_adc，直立±范围仍在ADC有效区内 |
| 86 | kick_percent | 1～100% |
| 87 | kick_ms | 1～1000ms |
| 88 | judge_ms | 1～1000ms |
| 89 | swing_timeout_ms | 1～60000ms |
| 8A | adc_timeout_ms | 1～1000ms |
| 8B / 8C | rail_low / rail_high | 不覆盖直立±fall_adc；high≤4092 |
| 8D | outer_limit_adc | 1～capture_adc |
| 8E | inner_limit_percent | 1～100% |
| 8F | inner_i_percent | 0～100% |
| 90 | outer_i_adc | 0～10000 ADC码 |
| 91 | travel_counts | 1～1000000计数，当前goal_B仍须在范围内 |

周期写入先使用候选周期重算三个系数，任何一个溢出都不提交；全部成功时周期、三个系数及epoch同时更新。
其他配置转换为整数后检查范围，负数全局值拒绝；小数按正负对称四舍五入量化。
无Flash擦写、掉电保存或启动后自动加载逻辑。未来增加存储时应从同一接口加载并进行整组校验，不能绕过配置模块直接覆盖控制器。
