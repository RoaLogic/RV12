#################################################################
##                                                             ##
##    ██████╗  ██████╗  █████╗                                 ##
##    ██╔══██╗██╔═══██╗██╔══██╗                                ##
##    ██████╔╝██║   ██║███████║                                ##
##    ██╔══██╗██║   ██║██╔══██║                                ##
##    ██║  ██║╚██████╔╝██║  ██║                                ##
##    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝                                ##
##          ██╗      ██████╗  ██████╗ ██╗ ██████╗              ##
##          ██║     ██╔═══██╗██╔════╝ ██║██╔════╝              ##
##          ██║     ██║   ██║██║  ███╗██║██║                   ##
##          ██║     ██║   ██║██║   ██║██║██║                   ##
##          ███████╗╚██████╔╝╚██████╔╝██║╚██████╗              ##
##          ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝ ╚═════╝              ##
##                                                             ##
##    RISC-V Makefile 			                       ##
##                                                             ##
#################################################################
##                                                             ##
##     Copyright (C) 2015 ROA Logic BV                         ##
##                                                             ##
##   This confidential and proprietary software is provided    ##
##  under license. It may only be used as authorised by a      ##
##  licensing agreement from ROA Logic BV.                     ##
##  No parts may be copied, reproduced, distributed, modified  ##
##  or adapted in any form without prior written consent.      ##
##  This entire notice must be reproduced on all authorised    ##
##  copies.                                                    ##
##                                                             ##
##     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ##
##  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED  ##
##  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS  ##
##  FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR     ##
##  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,        ##
##  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES   ##
##  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE  ##
##  GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR       ##
##  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF ##
##  LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT ##
##  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT ##
##  OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE        ##
##  POSSIBILITY OF SUCH DAMAGE.                                ##
##                                                             ##
#################################################################
#
# 2017-11-15: Modification for perl script
#
# Run perl script for full test case
#
# Single test
# Edit variables according to test and run: make
#
# Single test from command line 
# run: make TESTS=rv64ui-p-addi XLEN=64 ICACHE_SIZE=1
# 

all: parameters

SIMULATORS = ncsim vcs silos icarus riviera
LINTERS    = $(addsuffix _lint, $(SIMULATORS))
SIMWAVES   = $(addsuffix _waves, $(SIMULATORS))

MS     = -s

ROOT_DIR=../../../..
TST_SRC_DIR=$(ROOT_DIR)/../bench/regression
LOG_DIR=./log/

##########################################################################
#
# Simulation variables
#
##########################################################################

# Regression variables
XLEN 		= 32	
DCACHE_SIZE 	= 1
ICACHE_SIZE 	= 1
MEM_LATENCY	= 0
WRITEBUFFER_SIZE= 0
MULT_LATENCY 	= 0

# CPU variables
HAS_U		= 1
HAS_S		= 1
HAS_H		= 0
HAS_AMO		= 0
HAS_FPU		= 0
HAS_MMU		= 0
HAS_RVC		= 1
HAS_MUL		= 1
HAS_DIV		= 1
CORES		= 1
TECHNOLOGY	= GENERIC
PC_INIT		= 00000000
TESTS		= rv32ui-p-simple

##########################################################################
#
### Functions
#
##########################################################################
		 
params="DCACHE_SIZE=$(DCACHE_SIZE)\
	ICACHE_SIZE=$(ICACHE_SIZE)		 \
	MEM_LATENCY=$(MEM_LATENCY)		 \
	WRITEBUFFER_SIZE=$(WRITEBUFFER_SIZE)	 \
	XLEN=$(XLEN)				 \
	MULT_LATENCY=$(MULT_LATENCY)		 \
	HAS_U=$(HAS_U)			 	 \
	HAS_S=$(HAS_S) 			 	 \
	HAS_H=$(HAS_H)			 	 \
	HAS_AMO=$(HAS_AMO) 			 \
	HAS_RVC=$(HAS_RVC) 			 \
	HAS_MULDIV=$(HAS_MUL)			 \
	CORES=$(CORES)			 	 \
	TECHNOLOGY=$(TECHNOLOGY)		 \
	INIT_FILE=\"$(TST_SRC_DIR)/$(TESTS).hex\" "


log_file="./log/DCACHE_SIZE$(DCACHE_SIZE)@ICACHE_SIZE$(ICACHE_SIZE)@MEM_LATENCY$(MEM_LATENCY)@WRITEBUFFER_SIZE$(WRITEBUFFER_SIZE)@XLEN$(XLEN)@MULT_LATENCY$(MULT_LATENCY)@$(TESTS).log"

parameters:	
		$(MAKE) riviera_waves LOG=$(log_file) PARAMS=$(params)

	


##########################################################################
#
# Includes
#
##########################################################################
-include Makefile.include


##########################################################################
#
# libraries
#
##########################################################################
RTL_LIBS =


##########################################################################
#
# Misc Variables
#
##########################################################################
INCDIRS:=$(INCDIRS)
DEFINES:=$(DEFINES)

shell=/bin/sh


##########################################################################
#
# OVL
#
##########################################################################
ifeq ($(OVL_ASSERT),ON)
    INCDIRS+=$(STD_OVL_DIR)
    DEFINES+=OVL_ASSERT_ON
    LIBDIRS+=$(STD_OVL_DIR)
    LIBEXT +=.vlib

    ifeq ($(OVL_INIT_MSG),ON)
        DEFINES:=OVL_INIT_MSG
    endif
endif


##########################################################################
#
# Make Targets
#
##########################################################################
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


.PHONY: clean distclean mrproper
clean:
	@for f in $(wildcard *); do				\
		if test -d $$f; then $(MAKE) -C $$f clean; fi	\
	done

distclean:
	@rm -rf $(SIMULATORS) Makefile.include $(TB_PREREQ)

mrproper:
	@rm -rf *


##########################################################################
#
# Make simulation structure
#
##########################################################################
Makefile.include:
	@cp ../bin/Makefile.include .

%/Makefile:
	@mkdir -p $*
	@cp ../bin/Makefile.$* $@

$(TB_PREREQ):
	@cp ../bin/$@ $@



