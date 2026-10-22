create_clock -name clk_50m -period 20.000 [get_ports {clk}]
# ADC_CLK为转发给外设的25MHz时钟，在下次转发上升沿前锁存上一周期数据。
# 本约束仅定义主时钟，未包含板级走线和ADC输出延迟；外部接口时序需实板核对。
