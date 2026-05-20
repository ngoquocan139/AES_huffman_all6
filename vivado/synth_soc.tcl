# Vivado batch flow for the RV32I + Huffman/AES SoC.
#
# Environment variables used by sim/Makefile:
#   PROJECT_NAME      rv32_soc_synth_tx / rv32_soc_synth_rx / ...
#   TOP_NAME          rv32_soc_fpga_demo_top or rv32_soc_top
#   FPGA_BUILD        tx_only / rx_only / full
#   VIVADO_FLOW       synth / impl / bit
#   VIVADO_CLOCK_MHZ  default 50
#   VIVADO_XDC        optional XDC path, relative to repo root if not absolute

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc append_unique {list_var item} {
  upvar $list_var values
  set norm_item [file normalize $item]
  if {[lsearch -exact $values $norm_item] < 0} {
    lappend values $norm_item
  }
}

proc copy_reports_to_sim {report_dir sim_dir project_name} {
  file mkdir [file join $sim_dir "vivado_reports" $project_name]
  foreach rpt [glob -nocomplain [file join $report_dir "*"]] {
    file copy -force $rpt [file join $sim_dir "vivado_reports" $project_name [file tail $rpt]]
  }
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ".."]]
set sim_dir    [file join $repo_root "sim"]
set rtl_dir    [file join $repo_root "rtl"]

set project_name [env_or_default PROJECT_NAME "rv32_soc_synth_tx"]
set top_name     [env_or_default TOP_NAME "rv32_soc_fpga_demo_top"]
set fpga_build   [env_or_default FPGA_BUILD "tx_only"]
set flow         [env_or_default VIVADO_FLOW "synth"]
set xdc_path     [env_or_default VIVADO_XDC ""]
set clock_mhz    [env_or_default VIVADO_CLOCK_MHZ "50"]
set synth_directive [env_or_default VIVADO_SYNTH_DIRECTIVE "RuntimeOptimized"]
set opt_directive   [env_or_default VIVADO_OPT_DIRECTIVE ""]
set place_directive [env_or_default VIVADO_PLACE_DIRECTIVE ""]
set phys_opt_directive [env_or_default VIVADO_PHYS_OPT_DIRECTIVE ""]
set route_directive [env_or_default VIVADO_ROUTE_DIRECTIVE ""]
set power_opt     [env_or_default VIVADO_POWER_OPT "0"]
set power_opt_post_place [env_or_default VIVADO_POWER_OPT_POST_PLACE $power_opt]
set reuse_synth  [env_or_default VIVADO_REUSE_SYNTH "0"]
set reuse_impl   [env_or_default VIVADO_REUSE_IMPL "0"]
set part_name    "xc7z020clg484-1"

set build_dir  [file join $repo_root "vivado" "build" $project_name]
set report_dir [file join $build_dir "reports"]
set post_synth_dcp [file join $build_dir "post_synth.dcp"]
set post_route_dcp [file join $build_dir "post_route.dcp"]
file mkdir $build_dir
file mkdir $report_dir

set sim_instruction_mem [file join $sim_dir "instruction.mem"]
set root_instruction_mem [file join $repo_root "instruction.mem"]
if {[file exists $sim_instruction_mem]} {
  file copy -force $sim_instruction_mem $root_instruction_mem
  puts "INFO: copied $sim_instruction_mem to $root_instruction_mem for IMEM initialization"
} elseif {![file exists $root_instruction_mem]} {
  puts "WARNING: no instruction.mem found in sim/ or repo root; IMEM will synthesize with empty/default init if supported"
}

puts "INFO: repo_root=$repo_root"
puts "INFO: project_name=$project_name"
puts "INFO: top_name=$top_name"
puts "INFO: fpga_build=$fpga_build"
puts "INFO: flow=$flow"
puts "INFO: clock_mhz=$clock_mhz"
puts "INFO: synth_directive=$synth_directive"
puts "INFO: opt_directive=$opt_directive"
puts "INFO: place_directive=$place_directive"
puts "INFO: phys_opt_directive=$phys_opt_directive"
puts "INFO: route_directive=$route_directive"
puts "INFO: power_opt=$power_opt"
puts "INFO: power_opt_post_place=$power_opt_post_place"
puts "INFO: reuse_synth=$reuse_synth"
puts "INFO: reuse_impl=$reuse_impl"

set clk_period_ns [expr {1000.0 / double($clock_mhz)}]
set auto_clock_xdc [file join $build_dir "auto_clock.xdc"]
set auto_fh [open $auto_clock_xdc w]
puts $auto_fh "create_clock -name clk_i -period $clk_period_ns \[get_ports clk_i\]"
close $auto_fh

set can_reuse_synth [expr {($flow eq "impl" || $flow eq "bit") && $reuse_synth eq "1" && [file exists $post_synth_dcp]}]
set can_reuse_impl  [expr {$flow eq "bit" && $reuse_impl eq "1" && [file exists $post_route_dcp]}]

if {$can_reuse_impl} {
  puts "INFO: reusing existing post-route checkpoint: $post_route_dcp"
  open_checkpoint $post_route_dcp
} elseif {$can_reuse_synth} {
  puts "INFO: reusing existing post-synth checkpoint: $post_synth_dcp"
  open_checkpoint $post_synth_dcp
} else {
  create_project -force $project_name $build_dir -part $part_name
  set_property target_language Verilog [current_project]
  set_property simulator_language Verilog [current_project]

  set defines {}
  lappend defines SYNTHESIS
  if {$fpga_build eq "tx_only"} {
    lappend defines FPGA_TX_ONLY
  } elseif {$fpga_build eq "rx_only"} {
    lappend defines FPGA_RX_ONLY
  } elseif {$fpga_build eq "full"} {
    puts "INFO: full build selected; TX and RX are both included."
  } else {
    error "Unsupported FPGA_BUILD=$fpga_build. Use tx_only, rx_only, or full."
  }

  set rtl_files {}
  set rtl_f [file join $sim_dir "rtl.f"]
  if {![file exists $rtl_f]} {
    error "Missing RTL file list: $rtl_f"
  }

  set fh [open $rtl_f r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
      continue
    }
    if {[string match "#*" $line]} {
      continue
    }
    if {[string match "-f*" $line]} {
      continue
    }
    append_unique rtl_files [file join $sim_dir $line]
  }
  close $fh

  # FPGA wrapper and UART loader are not part of sim/rtl.f because the simulation
  # top uses the auxiliary loader directly.
  append_unique rtl_files [file join $rtl_dir "uart_rx.v"]
  append_unique rtl_files [file join $rtl_dir "uart_tx.v"]
  append_unique rtl_files [file join $rtl_dir "uart_dmem_loader.v"]
  append_unique rtl_files [file join $rtl_dir "rv32_soc_fpga_demo_top.v"]

  foreach src $rtl_files {
    if {![file exists $src]} {
      error "Missing RTL source: $src"
    }
  }

  set_property include_dirs $rtl_dir [current_fileset]
  set_property verilog_define $defines [current_fileset]
  set read_cmd [list read_verilog -sv]
  foreach src $rtl_files {
    lappend read_cmd $src
  }
  puts "INFO: read_verilog defines=$defines files=[llength $rtl_files]"
  eval $read_cmd

  set_property top $top_name [current_fileset]

  if {$xdc_path ne ""} {
    if {[file pathtype $xdc_path] eq "relative"} {
      set xdc_path [file normalize [file join $repo_root $xdc_path]]
    }
    if {[file exists $xdc_path]} {
      puts "INFO: read_xdc $xdc_path"
      read_xdc $xdc_path
    } else {
      puts "WARNING: VIVADO_XDC does not exist: $xdc_path"
    }
  }

  read_xdc $auto_clock_xdc
  puts "INFO: create_clock clk_i period=${clk_period_ns}ns"

  update_compile_order -fileset sources_1

  synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt -directive $synth_directive
  report_utilization -file [file join $report_dir "post_synth_utilization.rpt"]
  report_utilization -hierarchical -file [file join $report_dir "post_synth_utilization_hier.rpt"]
  report_control_sets -verbose -file [file join $report_dir "post_synth_control_sets.rpt"]
  report_timing_summary -file [file join $report_dir "post_synth_timing_summary.rpt"]
  report_drc -file [file join $report_dir "post_synth_drc.rpt"]
  write_checkpoint -force $post_synth_dcp
}

if {$flow eq "synth"} {
  puts "INFO: synth flow completed."
} elseif {$flow eq "impl" || $flow eq "bit"} {
  if {!$can_reuse_impl} {
    if {$opt_directive ne ""} {
      opt_design -directive $opt_directive
    } else {
      opt_design
    }

    if {$power_opt eq "1"} {
      puts "INFO: running pre-place power_opt_design"
      power_opt_design
    }

    if {$place_directive ne ""} {
      place_design -directive $place_directive
    } else {
      place_design
    }

    if {$power_opt_post_place eq "1"} {
      puts "INFO: running post-place power_opt_design"
      power_opt_design
    }

    if {$phys_opt_directive ne ""} {
      phys_opt_design -directive $phys_opt_directive
    } else {
      phys_opt_design
    }

    if {$route_directive ne ""} {
      route_design -directive $route_directive
    } else {
      route_design
    }

    if {$phys_opt_directive ne ""} {
      phys_opt_design -directive $phys_opt_directive
    } else {
      phys_opt_design
    }
  } else {
    puts "INFO: implementation is already loaded from post-route checkpoint."
  }

  report_route_status -file [file join $report_dir "post_impl_route_status.rpt"]
  report_utilization -file [file join $report_dir "post_impl_utilization.rpt"]
  report_utilization -hierarchical -file [file join $report_dir "post_impl_utilization_hier.rpt"]
  report_control_sets -verbose -file [file join $report_dir "post_impl_control_sets.rpt"]
  report_timing_summary -file [file join $report_dir "post_impl_timing_summary.rpt"]
  report_drc -file [file join $report_dir "post_impl_drc.rpt"]
  report_power -file [file join $report_dir "post_impl_power.rpt"]
  write_checkpoint -force [file join $build_dir "post_route.dcp"]
  copy_reports_to_sim $report_dir $sim_dir $project_name

  set setup_paths [get_timing_paths -max_paths 1 -nworst 1 -setup]
  if {[llength $setup_paths] > 0} {
    set wns [get_property SLACK [lindex $setup_paths 0]]
    puts "INFO: post-route setup WNS=$wns ns"
    if {$wns < 0.0} {
      error "Post-route timing failed: WNS=$wns ns"
    }
  } else {
    puts "WARNING: no setup timing path returned by get_timing_paths"
  }

  if {$flow eq "bit"} {
    set bit_file [file join $report_dir "${top_name}.bit"]
    write_bitstream -force $bit_file
    file mkdir [file join $sim_dir "vivado_bitstreams"]
    file copy -force $bit_file [file join $sim_dir "vivado_bitstreams" "${project_name}.bit"]
    file copy -force $bit_file [file join $sim_dir "vivado_bitstreams" "${project_name}_${top_name}.bit"]
  }
} else {
  error "Unsupported VIVADO_FLOW=$flow. Use synth, impl, or bit."
}

copy_reports_to_sim $report_dir $sim_dir $project_name

puts "INFO: Vivado flow completed successfully."
