#####################################################################
##   ,------.                    ,--.                ,--.          ##
##   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    ##
##   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    ##
##   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    ##
##   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    ##
##                                             `---'               ##
##   Regression Test Makefile                                      ##
##                                                                 ##
#####################################################################
##                                                                 ##
##             Copyright (C) 2014-2022 ROA Logic BV                ##
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
# 2017-02-22: Update for new test naming
# 2017-06-07: Added BPS support
# 2017-10-06: Changed Header, Logo, and Copyright notice
#             Added SIM variable
#

all: regression

SIMULATORS = ncsim vcs msim riviera
SIM        = msim_waves
SIMWAVES   = $(addsuffix _waves, $(SIMULATORS))

MS     = -s

ROOT_DIR=../../../..
TST_SRC_DIR=$(ROOT_DIR)/../bench/tests/regression


##########################################################################
#
# Regression variables
#
##########################################################################
#REGRESSION_MEM_LATENCY = 0 1 2 3 4 5 7 8 15
REGRESSION_MEM_LATENCY  = 0 1 2 3 8
#REGRESSION_XLEN        = 32 64
REGRESSION_XLEN         = 64
REGRESSION_RBS_DEPTH    = 0
REGRESSION_ICACHE_SIZE  = 0 4
REGRESSION_DCACHE_SIZE  = 0 4
REGRESSION_MULT_LATENCY = 3 2 1 0


##########################################################################
#
# Tests
#
##########################################################################
XLEN    = 64
HAS_RVC = 1
HAS_U   = 1 
HAS_S   = 0
HAS_H   = 0
HAS_RVA = 0
HAS_FPU = 0
HAS_MMU = 0
HAS_RVM = 1
HAS_DIV = $(HAS_RVM)
CORES   = 1
U_INT_TESTS =	simple							\
		add addi 						\
		and andi 						\
		auipc							\
		beq bge bgeu blt bltu bne				\
		fence_i							\
		jal jalr						\
		lb lbu lh lhu lw 					\
		lui							\
		or ori							\
		sb sh sw						\
		sll slli						\
		slt slti sltiu sltu					\
		sra srai						\
		srl srli						\
		sub							\
		xor xori						\
	$(if $(filter 64, $(XLEN)),					\
 		addiw addw						\
		lwu ld							\
		sd							\
		sllw slliw						\
		sllw slliw						\
		sltu sltiu						\
		sraw sraiw						\
		srlw srliw						\
		subw )
U_RVC_TESTS  =  rvc
U_AMO_TESTS  =	amoadd_w amoand_w amomax_w amomaxu_w			\
		amomin_w amominu_w amoor_w amoxor_w amoswap_w lrsc	\
	$(if $(filter 64, $(XLEN)),					\
  		amoadd_d amoand_d amomax_d amomaxu_d			\
		amomin_d amominu_d amoor_d amoxor_d amoswap_d )
U_MUL_TESTS  =	mul mulh mulhu mulhsu					\
	 $(if $(filter 64, $(XLEN)), mulw )
U_DIV_TESTS  =	div divu rem remu					\
	 $(if $(filter 64,$(XLEN)), divw divuw remw remuw )

#machine mode tests
M_TESTS      =	breakpoint csr illegal ma_addr ma_fetch mcsr sbreak	\
		scall							\
	$(if $(filter 32,$(XLEN)), shamt)

#supervisor mode tests
S_TESTS      =	csr dirty illegal ma_fetch sbreak scall wfi


#User Mode Integer Tests
uitst_lst  =                      $(foreach t, $(U_INT_TESTS),rv$(XLEN)ui-p-$t)
#uitst_lst += $(if $(HAS_RVA) > 0, $(foreach t, $(U_AMO_TESTS),rv$(XLEN)ua-p-$t))
uitst_lst += $(if $(HAS_RVM) > 0, $(foreach t, $(U_MUL_TESTS),rv$(XLEN)um-p-$t))
uitst_lst += $(if $(HAS_DIV) > 0, $(foreach t, $(U_DIV_TESTS),rv$(XLEN)um-p-$t))
uitests    = $(if $(HAS_U)   > 0, $(uitst_lst))

#User Mode RVC Tests
uctst_lst = $(if $(HAS_RVC), $(foreach t, $(U_RVC_TESTS),rv$(XLEN)uc-p-$t))
uctests   = $(if $(HAS_U) > 0, $(uctst_lst))

#Supervisor Mode Tests
sitst_lst = $(S_TESTS)
sitests   = $(if $(HAS_S) > 0, $(foreach t, $(sitst_lst),rv$(XLEN)si-p-$t))

#Machine Mode Tests
mitst_lst = $(M_TESTS)
mitests   = $(foreach t, $(mitst_lst),rv$(XLEN)mi-p-$t)


#All tests
#tests = $(uitests) $(sitests) $(mitests)
tests = $(uitests) $(mitests)


##########################################################################
#
### Functions
#
############################################################################
add_regression    = $(foreach p,$(REGRESSION_$(1)), $(addprefix $(1)$(p)@, $(2)))
add_regression_if = $(if $(filter $(2), $(subst -, , $(1))), $(call add_regression,$(3),$(4)),$(4))

logs = $(call add_regression,DCACHE_SIZE,				\
       $(call add_regression,ICACHE_SIZE,				\
       $(call add_regression,MEM_LATENCY,				\
       $(call add_regression,RBS_DEPTH,					\
       $(call add_regression,XLEN,					\
       $(foreach t,$(tests),						\
         $(call add_regression_if,$t,$(U_MUL_TESTS),MULT_LATENCY,	\
         $t.log								\
         )								\
       )								\
       )								\
       )								\
       )								\
       )								\
       )


regression: $(logs)

%.log:
	$(MAKE) $(SIM) LOG=./log/$(@F)						\
	  PARAMS="DCACHE_SIZE=$(subst DCACHE_SIZE,,$(word 1,$(subst @, ,$*)))		\
	          ICACHE_SIZE=$(subst ICACHE_SIZE,,$(word 2,$(subst @, ,$*)))		\
	          MEM_LATENCY=$(subst MEM_LATENCY,,$(word 3,$(subst @, ,$*))) 		\
	          WRITEBUFFER_SIZE=$(subst RBS_DEPTH,,$(word 4,$(subst @, ,$*)))	\
	          XLEN=$(subst XLEN,,$(word 5,$(subst @, ,$*)))				\
	          MULT_LATENCY=$(subst MULT_LATENCY,,$(word 6,$(subst @, ,$*)))		\
	          HAS_U=$(HAS_U) HAS_S=$(HAS_S) HAS_H=$(HAS_H)				\
		  HAS_RVA=$(HAS_RVA) HAS_RVC=$(HAS_RVC) HAS_RVM=$(HAS_RVM)		\
	          TECHNOLOGY=$(TECHNOLOGY)						\
	          INIT_FILE=\"$(TST_SRC_DIR)/$(lastword $(subst @, ,$*)).hex\" "


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

bluepearl_tcl=bps/roalogic.settings.tcl bps/bluepearl.runme.tcl


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


.PHONY: bps bps_gui
bps: % : %/Makefile $(bluepearl_tcl)
	@$(MAKE) $(MS) -C $@ $@ 				\
	VLOG="$(RTL_VLOG)"					\
	VHDL="$(RTL_VHDL)"					\
	TOP=$(RTL_TOP)

bps_gui: %_gui : %/Makefile
	@$(MAKE) $(MS) -C $* gui TOP=$(RTL_TOP)


.PHONY: clean distclean mrproper
clean:
	@for f in $(wildcard *); do				\
		if test -d $$f; then $(MAKE) -C $$f clean; fi	\
	done

distclean:
	@rm -rf $(SIMULATORS) bps Makefile.include $(TB_PREREQ)

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
	@cp ../bin/sims/Makefile.$* $@

$(bluepearl_tcl):
	@cp ../bin/sims/$(@F) $@

$(TB_PREREQ):
	@cp ../bin/$@ $@
