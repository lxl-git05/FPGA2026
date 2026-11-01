# No false paths or multicycle exceptions on the PID datapaths.
create_clock -name clk_50m -period 20.000 [get_ports {clk}]
# ADC forwarding and capture stay in clk_50m. Datasheet gives 25ns typical delay,
# not a guaranteed max/min including board delays. Do not invent external IO delays.
# Internal STA is necessary but does not sign off the external ADC interface.
