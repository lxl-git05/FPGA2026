# Self-contained build script - run with: gw_sh.exe build_gowin.tcl
# All sources live in the "src" folder next to this script. Paths are derived from
# $script_dir at run time, so on ANY machine the script finds the right files;
# nothing outside this dlb_validation folder is needed.
set script_dir [file dirname [info script]]
set project_dir [file dirname $script_dir]
create_project -name dlb_validation -dir "$project_dir" -pn GW2A-LV55PG484C8/I7 -device_version C -force
set_option -top_module Top
set_option -output_base_name dlb_validation
foreach source [lsort [glob "$script_dir/src/*.v"]] {add_file $source}
add_file "$script_dir/src/DLB.cst"
add_file "$script_dir/src/DLB.sdc"
run all
