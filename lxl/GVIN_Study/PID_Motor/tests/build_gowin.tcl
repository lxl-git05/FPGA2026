# Run with gw_sh.exe; all generated files stay in workspace Claude_Temp.
set project_dir [file normalize [file join [file dirname [info script]] ..]]
set workspace [file normalize [file join $project_dir .. .. ..]]
create_project -name pid_validation -dir "$workspace/Claude_Temp/PID_Motor_validation/gowin" -pn GW2A-LV55PG484C8/I7 -device_version C -force
set_option -top_module top
set_option -output_base_name pid_validation
foreach name {top.v MyPID.v PID_Motor.cst PID_Motor.sdc} {
    add_file "$project_dir/src/$name"
}
foreach name {tb6612_motor_driver.v encoder_quad.v PWM.v} {
    add_file "$workspace/DLB/DLB/DLB.srcs/sources_1/new/$name"
}
foreach name {uart_byte_rx.v uart_byte_tx.v} {
    add_file "$project_dir/../uart_loopback/src/$name"
}
run all
