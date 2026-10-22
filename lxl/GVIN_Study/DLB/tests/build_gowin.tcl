set project_dir [file normalize [file join [file dirname [info script]] ..]]
set workspace [file normalize [file join $project_dir .. .. ..]]
create_project -name dlb_validation -dir "$workspace/Claude_Temp/DLB_refactor/gowin" -pn GW2A-LV55PG484C8/I7 -device_version C -force
set_option -top_module Top
set_option -output_base_name dlb_validation
foreach source [lsort [glob "$project_dir/src/*.v"]] {add_file $source}
foreach name {encoder_quad.v tb6612_motor_driver.v PWM.v} {
    add_file "$workspace/DLB/DLB/DLB.srcs/sources_1/new/$name"
}
add_file "$project_dir/../PID_Motor/src/Key.v"
foreach name {uart_byte_rx.v uart_byte_tx.v} {add_file "$project_dir/../uart_loopback/src/$name"}
add_file "$project_dir/src/DLB.cst"
add_file "$project_dir/src/DLB.sdc"
run all
