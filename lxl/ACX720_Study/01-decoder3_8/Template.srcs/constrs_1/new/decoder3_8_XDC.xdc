# ============================================
# Reset
# ============================================
set_property PACKAGE_PIN B21 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ============================================
# In[2:0]
# ============================================
set_property IOSTANDARD LVCMOS33 [get_ports {In[*]}]

set_property PACKAGE_PIN G22 [get_ports {In[0]}]
set_property PACKAGE_PIN D22 [get_ports {In[1]}]
set_property PACKAGE_PIN E22 [get_ports {In[2]}]

# ============================================
# Out[7:0]
# ============================================
set_property PACKAGE_PIN M22 [get_ports {Out[0]}]
set_property PACKAGE_PIN N22 [get_ports {Out[1]}]
set_property PACKAGE_PIN L21 [get_ports {Out[2]}]
set_property PACKAGE_PIN K21 [get_ports {Out[3]}]
set_property PACKAGE_PIN K22 [get_ports {Out[4]}]
set_property PACKAGE_PIN J22 [get_ports {Out[5]}]
set_property PACKAGE_PIN H22 [get_ports {Out[6]}]
set_property PACKAGE_PIN M21 [get_ports {Out[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Out[*]}]

# ============================================
# SPI Flash Boot
# ============================================
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
