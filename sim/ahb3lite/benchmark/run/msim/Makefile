#####################################################################
##   ,------.                    ,--.                ,--.          ##
##   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    ##
##   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    ##
##   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    ##
##   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    ##
##                                             `---'               ##
##   Modelsim/Questasim Makefile                                   ##
##                                                                 ##
#####################################################################
##                                                                 ##
##             Copyright (C) 2014-2017 ROA Logic BV                ##
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

#
# ChangeLog
# 20171101: Added 'mfcu' option for Multi-File-Compilation
#


all: sim

#####################################################################
# Make Targets
#####################################################################
SIM_OPTS=-c +notimingchecks

.PHONY: sim simw clean

LOG = $(TOP).log

sim: vlog
	echo "--- Running sim"
	vsim $(SIM_OPTS)							\
	  -l $(LOG) $(TOP)							\
	  -do "run -all; quit"							\
	  $(foreach p, $(PARAMS),-g`echo $p | sed -r 's/(\w+)=([^0-9].*)/\1="\2"/'`)


simw: vlog
	echo "--- Running sim with waveform dump"
	vsim $(SIM_OPTS) 							\
	  -l $(LOG) $(TOP)							\
	  +access +r -wlf $(TOP).wlf						\
	  -do "set WildcardFilter [lsearch -not -all -inline $$WildcardFilter Memory];	\
               log -r /$(TOP)/*;							\
	       log /$(TOP)/dut/core/int_rf/rf;						\
	       log /$(TOP)/dut/dmem_ctrl_inst/genblk1/dcache_inst/cache_memory_inst/tag_out;	\
	       log /$(TOP)/dut/dmem_ctrl_inst/genblk1/dcache_inst/cache_memory_inst/tag_in;	\
	       log /$(TOP)/dut/dmem_ctrl_inst/genblk1/dcache_inst/cache_memory_inst/dat_out;	\
	       log /$(TOP)/dut/dmem_ctrl_inst/genblk1/dcache_inst/cache_memory_inst/way_q_mux;	\
	       run -all;								\
	       quit"				\
	$(foreach p, $(PARAMS),-g`echo $p | sed -r 's/(\w+)=([^0-9].*)/\1="\2"/'`)
	
clean:
	@rm -rf work *.log *.wlf



#####################################################################
## VHDL
#####################################################################


#####################################################################
## Verilog
#####################################################################
.PHONY: vlog

vlog: work $(VLOG) $(VLOG_LIBS)
	echo "--- Running vlog"
	vlog -work work $(VLOG)					\
	-sv -mfcu						\
	$(foreach d,$(DEFINES),+define+$d)			\
	$(foreach d,$(INCDIRS),+incdir+$d)			\
	$(foreach l,$(wildcard $(LIBDIRS)),-y $l) 		\
	+libext$(foreach e,$(LIBEXT),+$e)			\
	$(foreach l,$(wildcard $(TECHLIBS)/*.v),-v $l)


#####################################################################
## libraries
#####################################################################
work:
	vlib $@
