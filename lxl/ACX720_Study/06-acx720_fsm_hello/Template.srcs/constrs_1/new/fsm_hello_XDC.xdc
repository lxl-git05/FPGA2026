# ============================================
# Clock
# ============================================
set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

# ============================================
# Reset
# ============================================
set_property PACKAGE_PIN B21 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ============================================
# check_ok
# ============================================
set_property PACKAGE_PIN M22 [get_ports check_ok]
set_property IOSTANDARD LVCMOS33 [get_ports check_ok]

# ============================================
# SPI Flash Boot
# ============================================
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
