################################################
# Automatically created by Blue Pearl Visual Verification Environment Version 2018.1.46263 05/01/2018 12:57. Windows (64-bit). on Tue Jul 10 11:58:09 2018
################################################
##
#Exit Code:
#   0: Success
# 102: Command returned a TCL Error
##
#run load
#run analyze
###-generate_module_database
if {[catch {BPS::run analyze -forceload -generate_module_database} runOK] } {
    set exitCode 102
} else { #no exception thrown in command
    if { $runOK } {
        set exitCode 0
    } else {
        set exitCode 102
    }
}
if {$exitCode != 0} {
    puts "Warning: Results from BPS::run '$runOK'"
    puts "Warning: Command returned an error, please see messages above for more detail."
}
exit $exitCode

