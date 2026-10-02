# Run: vivado -mode batch -source DLB/scripts/build_pid_uart.tcl
# Outputs go to DLB/build/pid_uart; no project or hardware connection is needed.
set dlb_root [file normalize [file join [file dirname [info script]] ..]]
set rtl_root [file join $dlb_root DLB DLB.srcs sources_1 new]
set output_dir [file join $dlb_root build pid_uart]
file mkdir $output_dir
set_param general.maxThreads 4
foreach source {Test.v MyPID.v Key.v Seg8.v encoder_quad.v tb6612_motor_driver.v PWM.v protocol_rx.v protocol_tx.v parameter_manager.v telemetry_param_mux.v uart_byte_rx.v uart_byte_tx.v} {
    read_verilog [file join $rtl_root $source]
}
read_xdc [file join $dlb_root DLB DLB.srcs constrs_1 new DLB_XDC.xdc]
synth_design -top Test -part xc7a35tfgg484-2
if {[llength [get_cells -quiet -hier -filter {REF_NAME =~ LD*}]]} {error "Unexpected latches"}
if {[llength [get_clocks]] != 1} {error "Expected one 50MHz system clock"}
report_utilization -file [file join $output_dir utilization.rpt]
opt_design
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
report_timing_summary -file [file join $output_dir timing.rpt]
report_drc -file [file join $output_dir drc.rpt]
set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$setup_slack < 0 || $hold_slack < 0} {
    error "Timing failed: setup=$setup_slack ns hold=$hold_slack ns"
}
write_checkpoint -force [file join $output_dir Test_routed.dcp]
write_bitstream -force [file join $output_dir Test.bit]
puts "PASS: PID UART bitstream; setup=$setup_slack ns hold=$hold_slack ns"
exit
