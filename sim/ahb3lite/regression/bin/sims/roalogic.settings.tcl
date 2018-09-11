#####################################################################
##   ,------.                    ,--.                ,--.          ##
##   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    ##
##   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    ##
##   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    ##
##   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    ##
##                                             `---'               ##
##   BluePearl Software Settings File                              ##
##                                                                 ##
#####################################################################
##                                                                 ##
##             Copyright (C) 2018 Roa Logic BV                     ##
##             www.roalogic.com                                    ##
##                                                                 ##
##   This source file may be used and distributed without          ##
##   restriction provided that this copyright statement is not     ##
##   removed from the file and that any derivative work contains   ##
##   the original copyright notice and the associated disclaimer.  ##
##                                                                 ##
##      THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY        ##
##   EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED     ##
##   TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS     ##
##   FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR OR     ##
##   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,  ##
##   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT  ##
##   NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;  ##
##   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)      ##
##   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN     ##
##   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR  ##
##   OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS          ##
##   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.  ##
##                                                                 ##
#####################################################################


################################################
## Project Options
################################################
if {![info exists BPS::project_rel_to_dir] } {
    set BPS::project_rel_to_dir {.}
}
if {![info exists BPS::project_results_dir] } {
    set BPS::project_results_dir [file join $BPS::project_rel_to_dir {bluepearl.results}]
}


################################################
## Message Severity Level
################################################

#should latch inference be an error?


################################################
## Configuration
################################################

#file extensions
set vhdl_ext {.vhdl .vhd .vho .hdl}
set system_verilog_ext {.sv .psl}
set verilog_ext {.v .veri .ver .vg .tf}
set verilog_header_ext {.vh .svh .h}

#Exclude non-overflow constant assignments from mismatched bit assignment checks
set mba_exclude_all_arith true

#CDC setup
set cdc_limit 1000
set cdc_on_static_control_registers true
set constant_phase_cdc all
set check_cdc_from_primary_inputs true
set check_cdc_from_unclocked_primary_inputs false
set check_cdc_to_primary_outputs true

#RAM Inference
set enable_ram_inferencing true
set minimum_ram_size 0
set allow_ram_resets true
set allow_asynch_rams true
set allow_rams_from_sv_structures true
set allow_rams_in_loops true


BPS::set_sdc_format synopsys
set_hierarchy_separator /

#TODO: check below settings
set add_reset_to_converted_implicit_fsms false
set allow_entity_single_arch_file false
set analyze_cyclic_signals false
set assume_one_muxed_clock_active true
set assume_reset_only_init false
set assume_state_retention_clock_gating false
set auto_create_black_boxes false
set auto_derived_clock_domains true
set auto_detect_clock_domains false
set automate_module_library_search_path false
set autosortsv true
set autosortvhdl true
set check_xilinx_objects false
set clock_buses {}
set clock_detection_enabled_via_dffs true
set clock_detection_enabled_via_latches false
set constant_driven_muxes_driving_dff_are_synch_reset true
set control_logic false
set convert_implicit_fsms false
set cyclic_controlled_gates false
set dang_report_design true
set dang_report_module true
set def_systemverilog SYS_VERILOG
set def_verilog VERILOG_2001
set def_vhdl VHDL_2008
set default_message_limit 25
set dff_mapping_file {}
set disable_translate_off false
set distributed_control false
set enable_fsm_based_mcp_analysis true
set enable_mcp_sequential_analysis true
set enable_setreset_detection true
set enable_setreset_detection_latches false
set enable_stagedreset_detection true
set expand_fsm_on_out_of_bounds true
set expand_fsm_to_state_var_size true
set fanout_limit 8
set force_disable_ace false
set gatelevel_verilog_ext .gv
set gates2muxes false
set generate_cdc_messages_beyond_limit true
set ignore_clock_domain_specs false
set ignore_constant_controlled_false_paths false
set ignore_files {}
set ignore_suffixes {}
set include_ansi_file_search true
set include_asynch_synch_reset_analysis false
set include_default_prev_assign false
set internally_gated_signal_is_primary_reset false
set ite_depth 3
set liberty_files {}
set libmap {}
set librescan false
set limit_end_points false
set max_bus_width 32
set max_columns 72
set max_iterations_between_updates 100
set max_lines_per_module 80
set max_loop_limit 10000
set max_module_name_length 200
set max_seconds_between_updates 5
set maxfanout_clock 8
set maxfanout_dff 8
set maxfanout_port 8
set maxfanout_setreset 8
set maximum_number_expanded_fsm_states 1024
set mba_constant_size_strict false
set mba_exclude_arith false
set mba_exclude_const false
set mba_exclude_count false
set mba_exclude_inc false
set mba_exclude_optimized false
set mba_ignore_variable_vs_integer false
set mcp_data_stability false
set mea_report_missing_else_only false
set module_library_search_path {}
set multiple_cycle_learning false
set multiply_controlled_end_points false
set mux_select_input_is_primary_for_synch_reset false
set no_state_retention_requirement_on_end_points false
set noauto_bb_port_direction true
set output_of_muxed_clock_as_internal_clock false
set path_analysis true
set path_analysis_all_paths false
set path_analysis_dff2dff 30
set path_analysis_dff2port 20
set path_analysis_port2dff 20
set path_analysis_port2port 20
set propagate_constant_constraints false
set pulse_control false
set reset_false_paths off
set sdc_write_add_reg_suffix true
set sdc_write_check_dff_paths true
set sdc_write_check_memory_paths true
set sdc_write_check_po_paths true
set sdc_write_combine_constraints false
set sdc_write_comment_out_hierarchy_separator true
set sdc_write_create_clocks false
set sdc_write_default_clock_period 20
set sdc_write_default_input_delay 0
set sdc_write_default_output_delay 0
set sdc_write_expand_vector_q true
set sdc_write_gen_get_nets false
set sdc_write_generate_functional_exceptions true
set sdc_write_generate_io_delays false
set sdc_write_generate_separate_files false
set sdc_write_generate_set_clock_groups true
set sdc_write_generate_through_exceptions true
set sdc_write_insert_newline false
set sdc_write_mcp_synchronous_clocks true
set sdc_write_split_buses true
set sdc_write_supply_max_to_io_delays true
set sdc_write_supply_min_to_io_delays false
set sdc_write_use_bus_aliases false
set sdc_write_use_source_clock_in_generated_clocks true
set shorten_long_module_names false
set single_domain true
set stop_after_error 2147483647
set stop_loading_on_sdc_errors true
set storage_message_limit 10000
set suppress_cdc_from_scr true
set treat_empty_module_as_black_boxes false
set unitname_max_length 200
set user_clockcell_files {}
set user_greycell_files {}
set user_max_comb_levels 20
set veri_cu_mode default
set veri_lib_dirs {}
set veri_lib_files {}
set veri_synthesize_real_as_integer false
set veri_y_suffixes .v
set xilinx_glbl false

BPS::set_assertion_format SVA -enabled false
BPS::set_assertion_format PSL -enabled true
BPS::set_mcp_setup_and_hold_time -disabled


################################################
## Report Options
################################################
set report_all_unnamed_gen_stmts false			;#report all unnamed generate statements
set report_aln_sub true					;#report nets for proper active low naming
set report_aln_top true					;#report top level ports for proper active low naming
set report_dangling_tie_nets false
set report_equiv_clock_cdcs true		
set report_fpa_cdc off					;#generate clock-to-clock false paths
set report_fsm_default_state_transitions true		;#report default state transitions
set report_library_cells false				;#don't report library cells
set report_muxed_clocks_as_gated_clocks false
set report_on_previously_assigned false
set report_rego_sub true				;#modules should have registered outputs
set report_rego_top true
set report_rstname_sub false				;#report all nets for proper reset naming
set report_rstname_top true				;#report top level for proper reset naming
set report_staged_reset asynch				;#report reset chain through DFFs
set report_synch_reset match
set report_unnamed_blocks_sub false
set report_unnamed_blocks_top false
set report_unnamed_loop true				;#Name all loops
set report_unnamed_loop_end true
set report_unnamed_loop_exit true
set report_unnamed_loop_next true
set report_unnamed_nongen_blocks true
set report_unnamed_nongen_blocks_end false
set report_unnamed_nongen_blocks_sub true
set report_unnamed_nongen_blocks_top true
set report_unnamed_process_end false

BPS::set_report -all false				;#disable all reports
BPS::set_report -ace true				;#Enable Advanced Clock Environment report
BPS::set_report -clock true				;#Enable clock reports
BPS::set_report -gated_clock true
BPS::set_report -equivalent_clock true
BPS::set_report -counter true				;#Enable counter reports
BPS::set_report -cyclic_signals false
BPS::set_report -cyclic_registers false
BPS::set_report -dff true
BPS::set_report -fsm true
BPS::set_report -ite true
BPS::set_report -latch true
BPS::set_report -module true
BPS::set_report -net true
BPS::set_report -ram true
BPS::set_report -reset true
BPS::set_report -clock_domain_crossings true
BPS::set_report -runtime true
BPS::set_report -sloc true

BPS::set_log_options -paths false
BPS::set_log_options -systeminfo false
BPS::set_log_options -timestamp_messages false
BPS::set_log_options -mustfixsummary false
BPS::set_log_options -wontfixsummary false


################################################
## Enabled Load Checks
################################################
set rl_pkg_lst [list rl_lint rl_signoff rl_full_chip]

proc BPS::add_packages {args} {
  foreach p {args} {
    BPS::add_package $p
  }
}

proc BPS::add_check_to_packages {check args} {
  #parameters
  #check = name of check
  #args  = name of packages to add check to

  foreach p {args} {
    BPS::add_check_to_package $p -check $check
  }
}

BPS::set_check_enabled * -enabled false						;#disable all checks
BPS::add_packages rl_pkg_lst							;#add RoaLogic packages

BPS::add_check_to_packages ACCESS_GLOBAL_VAR rl_pkg_lst				;#functions should not access primary signals
BPS::add_check_to_packages AMBIG_IFIFELSE rl_pkg_lst				;#avoid abiguous if-if-else statements
BPS::add_check_to_packages AVOID_FULL_CASE rl_pkg_lst				;#prevent full_case
BPS::add_check_to_packages AVOID_PARALLEL_CASE pkg_lst				;#prevent parallel_case
BPS::add_check_to_packages BIT_PART_SEL_EVENT pkg_lst				;#no bit-parts in sensitivity lists
BPS::add_check_to_packages BUFPROC pkg_lst					;#non-blocking statement in an always_comb block
BPS::add_check_to_packages CCLP pkg_lst						;#detect zero/infinite loops
BPS::add_check_to_packages CKGT pkg_lst						;#no clock gating (in RTL)
BPS::add_check_to_packages CLKEXPR pkg_lst					;#no always@(posedge clk1|clk2)
BPS::add_check_to_packages CLPR pkg_lst						;#no combinational loops
BPS::add_check_to_packages COND_EXPR_MULTI_BIT pkg_lst				;#no multi-bit variables in IF (should be |bus or &bus)
BPS::add_check_to_packages CONSTANT_CASE_EXPR pkg_lst				;#detect case(constant)
BPS::add_check_to_packages CONSTANT_NONCLOCK_NET pkg_lst			;#constant drives clock
BPS::add_check_to_packages CONSTRUCT_HEADER rl_signoff				;#use construct headers on tasks/functions
BPS::add_check_to_packages CSL pkg_lst						;#detect incomplete sensitivity lists
BPS::add_check_to_packages DANG pkg_lst						;#detect dangling nets
BPS::add_check_to_packages DANG_PIN pkg_lst					;#detect dangling ports
BPS::add_check_to_packages DCI pkg_lst						;#detect duplicate case items
BPS::add_check_to_packages EMPTY_CASE pkg_lst					;#detect case without items
BPS::add_check_to_packages EMPTY_MODULE pkg_lst					;#detect empty modules/functions
BPS::add_check_to_packages EPNC pkg_lst						;#explicit port naming
BPS::add_check_to_packages ETB pkg_lst						;#detect empty 'then' block
BPS::add_check_to_packages EVENTLIST_CONSTANT pkg_lst				;#detect always blocks that never get triggered
BPS::add_check_to_packages EXPLICIT_INSTANTIATION_PARAM_NAMING pkg_lst		;#explicitly parameter naming
BPS::add_check_to_packages FILE_HEADER rl_signoff				;#use file headers (TODO)
BPS::add_check_to_packages FOREIGN_LANGUAGE_KWD pkg_lst				;#prevent keywords from other languages
BPS::add_check_to_packages FORLOOP_ITER_NONINT pkg_lst				;#detect use of non-integer loop variables
BPS::add_check_to_packages FSM [list rl_signoff rl_full_chip]			;#enable statemachine analysis
BPS::add_check_to_packages FSM_BOUNDS pkg_lst					;#check size of state variables
BPS::add_check_to_packages GIC pkg_lst						;#no gate instances in the RTL
BPS::add_check_to_packages GRST pkg_lst						;#don't gate resets
BPS::add_check_to_packages ICKGT pkg_lst					;#report internally generated gated clocks
BPS::add_check_to_packages IGCK pkg_lst						;#report internally generated clocks
BPS::add_check_to_packages IMPLICIT_DECL pkg_lst				;#report implicit wire declarations
BPS::add_check_to_packages INT_TRI pkg_lst					;#no internal tri-states
BPS::add_check_to_packages INVALID_COMPARISON pkg_lst				;#detect always true/false assignments
BPS::add_check_to_packages ITE_DEPTH pkg_lst					;#report if-then-else depth
BPS::add_check_to_packages LATCH_CREATED pkg_lst				;#no latches
BPS::add_check_to_packages LHS_INPUT_PORT pkg_lst				;#no assignments to input ports
BPS::add_check_to_packages MBA pkg_lst						;#Mismatching Bit Assignments
BPS::add_check_to_packages MCA pkg_lst						;#Missing case statement assignment
BPS::add_check_to_packages MCI_NO_DEFAULT pkg_lst				;#Missing case item for non-full/no-default case
BPS::add_check_to_packages MCIS pkg_lst						;#Case expression size mismatch
BPS::add_check_to_packages MCVS pkg_lst						;#Constant size mismatch
BPS::add_check_to_packages MDR pkg_lst						;#Multiple drivers
BPS::add_check_to_packages MECKM pkg_lst					;#Mixed clock-edges
BPS::add_check_to_packages MIXED_ASSIGNS pkg_lst				;#Mixed blocking/non-blocking assignments
BPS::add_check_to_packages MOS pkg_lst						;#Check mismatched logical operations
BPS::add_check_to_packages MOS_TERNARY pkg_lst					;#Check mismatched ?: operations
BPS::add_check_to_packages MULTI_CLK pkg_lst					;#only 1 clock per module
BPS::add_check_to_packages MULT_MODS rl_signoff					;#only 1 module per file
BPS::add_check_to_packages NBA pkg_lst						;#check correct use of non-blocking assignment
BPS::add_check_to_packages NEGATIVE_ASSIGN pkg_lst				;#check for negative assignments
BPS::add_check_to_packages NON_CONSTANT pkg_lst					;#check for non-constant errors
BPS::add_check_to_packages NOT_SYNTHESIZABLE pkg_lst				;#check for non-synthesizeable constructs
BPS::add_check_to_packages NO_ALIAS_DECLS pkg_lst				;#No alias statements (anyone ever use this?!)
BPS::add_check_to_packages NO_DELAY pkg_lst					;#No timing
BPS::add_check_to_packages NO_INITIAL pkg_lst					;#No initial statements (doesn't work in ASIC)
BPS::add_check_to_packages NO_MACROMODULES pkg_lst				;#No macromodule
BPS::add_check_to_packages NO_REF pkg_lst					;#Report single reference signals (declared but not used)
BPS::add_check_to_packages NO_SET_RESETS pkg_lst				;#Report ambiguous reset generation
BPS::add_check_to_packages NO_SYNCH_DEASSERT_RST rl_full_chip			;#Require two-stage reset (chip-level only)
BPS::add_check_to_packages NO_TABS pkg_lst					;#Don't use tabs
BPS::add_check_to_packages PAREN_UNARY pkg_lst					;#Check for ambiguous logical/reduction operator sequence
BPS::add_check_to_packages POSEDGE pkg_lst					;#Use only posedge clocks
BPS::add_check_to_packages POTENTIAL_FSM pkg_lst				;#Flag funky FSM description



#naming convention
BPS::set_check_enabled NAME_ANALYSIS_CLOCKS -enabled true			;#use clock naming convention
BPS::set_check_enabled NAME_ANALYSIS_INSTANCES -enabled true			;#use instance naming convention
BPS::set_check_enabled NAME_ANALYSIS_MODULES -enabled true			;#use module naming convention
BPS::set_check_enabled NAME_ANALYSIS_PORTS -enabled true			;#use port naming rules
BPS::set_check_enabled NAME_ANALYSIS_RESETS -enabled true			;#use reset naming convention



################################################
## Enabled Analyze Checks
################################################
BPS::set_check_enabled ANALYZE_MULTIBIT_DOUBLE_REG_SYNCH -enabled true

BPS::set_check_enabled CHECK_FAST_TO_SLOW_CDC -enabled true
BPS::set_check_enabled CHECK_MIXED_CLOCK_EDGE_USAGE -enabled true
BPS::set_check_enabled CHECK_MIXED_TO_DATA_CAPTURES -enabled true
BPS::set_check_enabled CHECK_NEG_TO_MIXED_DATA_CAPTURES -enabled true
BPS::set_check_enabled CHECK_NEG_TO_POS_DATA_CAPTURES -enabled true
BPS::set_check_enabled CHECK_POS_TO_MIXED_DATA_CAPTURES -enabled true
BPS::set_check_enabled CHECK_POS_TO_NEG_DATA_CAPTURES -enabled true
BPS::set_check_enabled CHECK_SYNCH_FANOUT -enabled true
BPS::set_check_enabled CLK_SYN_REG_BOUNDARY -enabled true
BPS::set_check_enabled COMB_LEVELS -enabled true
BPS::set_check_enabled LTH_DRIVES_DFF -enabled true
BPS::set_check_enabled MCP -enabled true
BPS::set_check_enabled MEA -enabled true
BPS::set_check_enabled MEB -enabled true
BPS::set_check_enabled MIA -enabled true
BPS::set_check_enabled MIXED_CLK_GATING -enabled true
BPS::set_check_enabled MIXED_EDGE_CLOCK_SOURCE -enabled true
BPS::set_check_enabled OCI -enabled true
BPS::set_check_enabled REGI_SYNCH -enabled true
BPS::set_check_enabled REGO_SYNCH -enabled true
BPS::set_check_enabled REPORT_ON_ALL_CDCS -enabled true
BPS::set_check_enabled REPORT_ON_CONTROL_SYNCH_CLOCK_SIGNAL -enabled true
BPS::set_check_enabled REPORT_ON_DOUBLE_REG_SYNCH -enabled true
BPS::set_check_enabled REPORT_ON_GRAY_CODE_DOUBLE_REG_SYNCH -enabled true
BPS::set_check_enabled REPORT_ON_MEM_SYNCH_CELL -enabled true
BPS::set_check_enabled REPORT_ON_SYNCH_USER_GREY_CELL -enabled true
BPS::set_check_enabled REPORT_ON_UNSYNCH_CDC -enabled true
BPS::set_check_enabled REPORT_ON_USER_SYNCH_CELL -enabled true
BPS::set_check_enabled REPORT_SINGLE_BITCHANGE_PROVED -enabled true
BPS::set_check_enabled RESET_MIXED_EDGES -enabled true
BPS::set_check_enabled RRW -enabled true
BPS::set_check_enabled RST_MULT -enabled true
BPS::set_check_enabled SYNCH_DATA_CONVERGES -enabled true
BPS::set_check_enabled SYNCH_DATA_GLITCH -enabled true
BPS::set_check_enabled TERM_STATE -enabled true
BPS::set_check_enabled UBA -enabled true
BPS::set_check_enabled UNR -enabled true
BPS::set_check_enabled UNREACHABLE_STATE -enabled true

################################################
## Enabled Dependent Checks
#################################################
# 'MULTIPLE_SYNCHRONIZATION' is dependent on the following check(s): 'MULTIPLE_SYNCHRONIZATION'.
BPS::set_check_enabled MULTIPLE_SYNCHRONIZATION -enabled true

################################################
## Logging Options
################################################
BPS::clear_log_package_summary
BPS::set_memorystateinterval 0

################################################
## Naming Analysis Settings
################################################
BPS::reset_naming_options
# Check 'NAME_ANALYSIS_REGISTERS' is disabled
#     BPS::set_naming_option -type DFFs -regex .*_reg -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'NAME_ANALYSIS_CLOCKS' is disabled
#     BPS::set_naming_option -type {Internal Clocks} -regex {${PARENT_CLOCK}.*} -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'NAME_ANALYSIS_CLOCKS' is disabled
#     BPS::set_naming_option -type {Clocks - Active Low} -regex .*_n -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'NAME_ANALYSIS_RESETS' is disabled
#     BPS::set_naming_option -type {Resets - Active Low} -regex .*_n -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'NAME_ANALYSIS_SETS' is disabled
#     BPS::set_naming_option -type {Sets - Active Low} -regex .*_n -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'NAME_ANALYSIS_CLOCKENABLE' is disabled
#     BPS::set_naming_option -type {Clock Gating/Enabling Signals - Active Low} -regex .*_n -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'STATE_VAR_NAME' is disabled
#     BPS::set_naming_option -type {FSM State Name - Next State} -regex (.*_next)|(.*_ns) -disallowed_regex {} -case_insensitive false -use_full_path false -run_parent_analysis true
# Check 'IDENTIFY_STATIC_CONTROL_REGISTERS' is disabled
#     BPS::set_naming_option -type {Identify - Static Control Registers} -regex (.*_cfg)|(config.*) -disallowed_regex {} -case_insensitive true -use_full_path false
BPS::set_naming_option -type {Identify - Top Level Clocks} -regex (.*ck.*)|(.*clk.*)|(.*clock.*) -disallowed_regex (.*first.*)|(.*burst.*)|(.*enable_clk.*) -case_insensitive true -use_full_path false
BPS::set_naming_option -type {Identify - Internal Clocks} -regex (.*ck.*)|(.*clk.*)|(.*clock.*) -disallowed_regex (.*first.*)|(.*burst.*)|(.*enable_clk.*) -case_insensitive true -use_full_path false
# Check 'IDENTIFY_SET_SIGNALS' is disabled
#     BPS::set_naming_option -type {Identify - Set Signals} -regex (_sn)|(preset)|(set)|(sn)|(.*set)|(set.*) -disallowed_regex (.*first.*)|(.*burst.*)|(.*enable_clk.*) -case_insensitive true -use_full_path false
# Check 'IDENTIFY_RESET_SIGNALS' is disabled
#     BPS::set_naming_option -type {Identify - Reset Signals} -regex (_rn)|(clear)|(clr)|(reset)|(rn)|(rst)|(.*clear.*)|(.*clr.*)|(.*reset.*)|(.*rst.*)|(.*clr)|(.*reset)|(.*rst)|(clear.*)|(clr.*)|(reset.*)|(rst.*) -disallowed_regex (.*first.*)|(.*burst.*)|(.*enable_clk.*) -case_insensitive true -use_full_path false
# Check 'IDENTIFY_DANGLING_SIGNALS' is disabled
#     BPS::set_naming_option -type {Exclude Dangling Signals} -regex .*_nc -disallowed_regex {} -case_insensitive false -use_full_path false
# Check 'IDENTIFY_DANGLING_PINS' is disabled
#     BPS::set_naming_option -type {Exclude Dangling Pins} -regex .*_nc -disallowed_regex {} -case_insensitive false -use_full_path false
# Check 'IDENTIFY_TIE_NETS' is disabled
#     BPS::set_naming_option -type {Identify - Tie Nets} -regex (TIE_HI_.*)|(TIE_LO_.*) -disallowed_regex {} -case_insensitive true -use_full_path false

################################################
## Assignment Options
################################################
set mca_report_all false
set mia_report_all false
set mea_report_all false
set meb_report_all false
set etb_report_all false
set uba_report_clocked_blocks false
set mdr_report_bidir false
set mdr_report_wired false

################################################
## Waivers
################################################

BPS::clear_all_waivers
if {[file exists [file join $BPS::project_rel_to_dir ./waivers.xml]]} {
    BPS::load_waivers_file [file join $BPS::project_rel_to_dir ./waivers.xml]
}
