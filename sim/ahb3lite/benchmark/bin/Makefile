####################################################################
##   ,------.                    ,--.                ,--.          ##
##   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    ##
##   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    ##
##   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    ##
##   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    ##
##                                             `---'               ##
##   Main Simulation Makefile                                      ##
##                                                                 ##
#####################################################################
##                                                                 ##
##             Copyright (C) 2017 ROA Logic BV                     ##
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

all: help

bmarks     = dhrystone
sim        = msim_waves

SIMULATORS = msim ncsim vcs riviera
LINTERS    = $(addsuffix _lint, $(SIMULATORS))
SIMWAVES   = $(addsuffix _waves, $(SIMULATORS))

MS     = -s

ROOT_DIR    = ../../../..
TST_SRC_DIR = $(ROOT_DIR)/../bench/tests/benchmarks
POSTFIX     = .riscv$(XLEN).hex


#####################################################################
#
# Regression variables
#
#####################################################################
XLEN              = 64
DCACHE_SIZE       = 0
ICACHE_SIZE       = 0
RSB_DEPTH         = 4
HAS_U             = 1
HAS_S             = 0
HAS_H             = 0
HAS_RVA           = 0
HAS_RVC           = 1
HAS_RVM           = 1
MULT_LATENCY      = 0

MEM_LATENCY       = 0


#####################################################################
#
## Sources
#
######################################################################
-include Makefile.include

.PHONY: help $(bmarks)

help:
	@echo "Usage: make [sim=<simulator>] <benchmark>"
	@echo "benchmarks: $(bmarks)"
	@echo "dhrystone"

$(bmarks):
	$(MAKE) $(sim)	 							\
	  LOG=$@.log								\
	  PARAMS="DCACHE_SIZE=$(DCACHE_SIZE)					\
	          ICACHE_SIZE=$(ICACHE_SIZE)					\
	          MEM_LATENCY=$(MEM_LATENCY)					\
	          RSB_DEPTH=$(RSB_DEPTH)					\
	          XLEN=$(XLEN)							\
	          MULT_LATENCY=$(MULT_LATENCY)					\
	          HAS_U=$(HAS_U) HAS_S=$(HAS_S) HAS_H=$(HAS_H)			\
	          HAS_RVA=$(HAS_RVA) HAS_RVC=$(HAS_RVC) HAS_RVM=$(HAS_RVM)	\
	          TECHNOLOGY=$(TECHNOLOGY)					\
	          INIT_FILE=\"$(TST_SRC_DIR)/$@$(POSTFIX)\" "


#####################################################################
#
# Misc Variables
#
#####################################################################
INCDIRS:=$(INCDIRS)
DEFINES:=$(DEFINES)

shell=/bin/sh


#####################################################################
#
# OVL
#
#####################################################################
ifeq ($(OVL_ASSERT),ON)
    INCDIRS +=$(STD_OVL_DIR)
    DEFINES +=OVL_ASSERT_ON
    LIBDIRS +=$(STD_OVL_DIR)
    LIBEXT  +=.vlib

    ifeq ($(OVL_INIT_MSG),ON)
        DEFINES +=OVL_INIT_MSG
    endif
endif


#####################################################################
#
# Make Targets
#
#####################################################################
.PHONY: $(SIMULATORS) $(LINTERS) $(SIMWAVES)
$(SIMULATORS): % : %/Makefile $(TB_PREREQ)
	@$(MAKE) $(MS) -C $@ sim				\
	VLOG="$(abspath $(RTL_VLOG) $(TB_VLOG))"		\
	TECHLIBS="$(TECHLIBS)"					\
	LIBDIRS="$(LIBDIRS)"					\
	LIBEXT="$(LIBEXT)"					\
	VHDL="$(abspath $(RTL_VHDL) $(TB_VHDL))"		\
	INCDIRS="$(abspath $(INCDIRS))"				\
	DEFINES="$(DEFINES)"					\
	TOP=$(TB_TOP)						\
	LOG=$(LOG) PARAMS="$(PARAMS)"

$(SIMWAVES): %_waves : %/Makefile $(TB_PREREQ)
	@$(MAKE) $(MS) -C $(subst _waves,,$@) simw		\
	VLOG="$(abspath $(RTL_VLOG) $(TB_VLOG))"		\
	TECHLIBS="$(TECHLIBS)"					\
	LIBDIRS="$(LIBDIRS)"					\
	LIBEXT="$(LIBEXT)"					\
	VHDL="$(abspath $(RTL_VHDL) $(TB_VHDL))"		\
	INCDIRS="$(abspath $(INCDIRS))"				\
	DEFINES="$(DEFINES)"					\
	TOP=$(TB_TOP)						\
	LOG=$(LOG) PARAMS="$(PARAMS)"

$(LINTERS): %_lint : %/Makefile $(TB_PREREQ)
	@$(MAKE) $(MS) -C $(subst _lint,,$@) lint		\
	VLOG="$(abspath $(RTL_VLOG))"				\
	VHDL="$(abspath $(RTL_VHDL))"				\
	INCDIRS="$(abspath $(INCDIRS))"				\
	DEFINES="$(DEFINES)"					\
	TOP=$(RTL_TOP)


.PHONY: bps bps_gui
bps: % : %/Makefile
	@$(MAKE) $(MS) -C $@ $@                                 \
	VLOG="$(abspath $(RTL_VLOG))"                           \
	VHDL="$(abspath $(RTL_VHDL))"                           \
	TOP=$(RTL_TOP)

bps_gui: %_gui : %/Makefile
	@$(MAKE) $(MS) -C $* gui

.PHONY: clean distclean mrproper
clean:
	@for f in $(wildcard *); do				\
		if test -d $$f; then $(MAKE) -C $$f clean; fi	\
	done

distclean:
	@rm -rf $(SIMULATORS) bps Makefile.include $(TB_PREREQ)

mrproper:
	@rm -rf *


#####################################################################
#
# Make simulation structure
#
#####################################################################
Makefile.include:
	@cp ../bin/Makefile.include .

%/Makefile:
	@mkdir -p $*
	@cp ../bin/sims/Makefile.$* $@

$(TB_PREREQ):
	@cp ../bin/$@ $@
