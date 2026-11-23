package require ::quartus::project
package require ::quartus::sta
project_open [lindex $argv 0]
create_timing_netlist
read_sdc
set failed 0
set corners 0
foreach_in_collection op [get_available_operating_conditions] {
    set_operating_conditions $op
    update_timing_netlist
    puts "Checking [get_operating_conditions_info -display_name $op]"
    incr corners
    set checked 0
    foreach check {setup hold recovery removal} {
        set paths [get_timing_paths -$check -npaths 1]
        foreach_in_collection path $paths {
            incr checked
            set slack [get_path_info -slack $path]
            puts "$check worst slack: $slack ns"
            if {$slack < 0} { set failed 1 }
        }
    }
    if {$checked == 0} { set failed 1 }
}
delete_timing_netlist
project_close
if {$corners == 0 || $failed} {
    puts stderr "Timing acceptance failed"
    exit 1
}
