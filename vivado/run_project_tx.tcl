# Rebuild the Vivado project-mode TX run so GUI synth_1/impl_1 matches
# the batch checkpoint flow in synth_soc.tcl.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set project_xpr [file join $repo_root "vivado" "build" "rv32_soc_synth_tx" "rv32_soc_synth_tx.xpr"]
set mem_file    [file join $repo_root "instruction.mem"]
set top_name    "rv32_soc_fpga_demo_top"

if {![file exists $project_xpr]} {
  error "Missing project: $project_xpr. Run make vivado_synth_tx first."
}

open_project $project_xpr

if {[file exists $mem_file]} {
  add_files -quiet -fileset sources_1 $mem_file
  set mem_obj [get_files -quiet $mem_file]
  if {[llength $mem_obj] > 0} {
    set_property file_type {Memory Initialization Files} $mem_obj
  }
} else {
  puts "WARNING: $mem_file does not exist; project-mode synthesis may use empty IMEM init."
}

catch {reset_run impl_1}
catch {reset_run synth_1}

set batch_post_synth [file join $repo_root "vivado" "build" "rv32_soc_synth_tx" "post_synth.dcp"]
set synth_ref_dcp [file join $repo_root "vivado" "build" "rv32_soc_synth_tx" "rv32_soc_synth_tx.srcs" "utils_1" "imports" "synth_1" "${top_name}.dcp"]
if {![file exists $batch_post_synth]} {
  error "Missing batch checkpoint: $batch_post_synth. Run make vivado_flow_tx first."
}
file mkdir [file dirname $synth_ref_dcp]
file copy -force $batch_post_synth $synth_ref_dcp
puts "INFO: copied batch post-synth checkpoint to synth reference $synth_ref_dcp"

set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
puts "INFO: synth_1 flatten=[get_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY [get_runs synth_1]] directive=[get_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE [get_runs synth_1]]"

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_1 status=$synth_status"
if {![string match "*Complete*" $synth_status]} {
  error "synth_1 did not complete: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl_1 status=$impl_status"
if {![string match "*Complete*" $impl_status]} {
  error "impl_1 did not complete: $impl_status"
}

puts "INFO: project-mode TX implementation completed successfully."
