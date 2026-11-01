# Self-contained build script - run with: gw_sh.exe build_gowin.tcl
# All sources live in the "src" folder next to this script; nothing outside
# this dlb_validation folder is needed, so the whole folder can be copied to
# any machine and rebuilt. Sources are added with RELATIVE paths so the .gprj
# also stays portable.
set script_dir [file dirname [info script]]
cd $script_dir
create_project -name dlb_validation -dir [file dirname $script_dir] -pn GW2A-LV55PG484C8/I7 -device_version C -force
set_option -top_module Top
set_option -output_base_name dlb_validation
foreach source [lsort [glob "src/*.v"]] {add_file $source}
add_file "src/DLB.cst"
add_file "src/DLB.sdc"
run all
