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
# key_in[3:0]
# ============================================
set_property PACKAGE_PIN F15 [get_ports {key_in[0]}]
set_property PACKAGE_PIN A20 [get_ports {key_in[1]}]
set_property PACKAGE_PIN B20 [get_ports {key_in[2]}]
set_property PACKAGE_PIN A21 [get_ports {key_in[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {key_in[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_in[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_in[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_in[3]}]

# ============================================
# LED[7:0]
# ============================================
set_property PACKAGE_PIN M22 [get_ports {LED[0]}]
set_property PACKAGE_PIN N22 [get_ports {LED[1]}]
set_property PACKAGE_PIN L21 [get_ports {LED[2]}]
set_property PACKAGE_PIN K21 [get_ports {LED[3]}]
set_property PACKAGE_PIN K22 [get_ports {LED[4]}]
set_property PACKAGE_PIN J22 [get_ports {LED[5]}]
set_property PACKAGE_PIN H22 [get_ports {LED[6]}]
set_property PACKAGE_PIN M21 [get_ports {LED[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {LED[*]}]

# ============================================
# SPI Flash Boot
# ============================================
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
