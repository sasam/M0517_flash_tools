#-----------------------------------------------------------------------------
# Support function to Flash NuMicro M051x microcontrolers
#  for use with OpenOCD TCL
#
#  Copyright (c) 2015 Sasa Mihajlovixc
#
#-----------------------------------------------------------------------------
#
# openocd -f interface/stlink-v2.cfg -f target_M0517_win.cfg -f M0517_flash.tcl
# openocd -f interface/stlink-v2.cfg -f target_M0517_linux.cfg -f M0517_flash.tcl
# -s V:\tmp\openocd-0.8.0\bin
# -f M0517_unlock.tcl -f M0517_flash.tcl
# source M0517_flash.tcl
# source M0517_unlock.tcl
# FlashAprom (cheali-charger.bin|cheali-charger.hex)
##
#

##
# register allocation
# --------------------
# r0  arg0 & return
# r1  arg1 
# r2  arg2
##

proc getFileType {Filename} {
	if {[file extension $Filename] == ".hex"} {
		return "ihex"
	} else {
		return "bin"
	}
}

proc FlashAprom { Filename } {
	set fl_base_adr 0
	set fl_bank 0
	
	set SRAM_BUF 0x20000120
	set PGM_FILE NU_M051x.bin
	set SRAM_SEK 7

	set BUF_SIZE [expr $SRAM_SEK*512]

	set f_size [expr [lindex [ocd_test_image $Filename $fl_base_adr] 3]]
	set f_type [getFileType $Filename]
	set f_35k [expr ($f_size / $BUF_SIZE)]
	set f_05k [expr ($f_size % $BUF_SIZE)]
	set f_sec [expr ((($f_size + 511) & ~511)/512)]
	
	set time_start [clock seconds]

	puts "Image: $Filename, type: $f_type; Size=$f_size; Sectors:$f_sec; FlashProces:($f_size;$BUF_SIZE,$f_35k;$f_05k,1)"
	
	puts ">>>>     Load FlashPgm to SRAM: $PGM_FILE => 0x20000000"
	reset init
	load_image $PGM_FILE 0x20000000
	
	puts ">>>>     FlashInit:"
	reg sp 0x20001000 
	reg pc 0x20000000
   	resume
   	wait_halt
	set r0 [expr [lindex [ocd_reg 0] 2]]
	if { $r0 != 0 } { 
		puts "ERROR:: Not able to unlock"
	} 
	puts ">>>>     FlashInit stop:"

	set time_init [clock seconds]
	puts "time init: [expr $time_init - $time_start] sec"
	
# r0	//address of 1. sector for erease
# r1	//number od sectors to erease
	puts ">>>>     EreaseFlash: start"	
	puts "     FLASH sector addr: [format 0x%08x $fl_base_adr]"
	puts "     sectors to erease: [format 0x%08x $f_sec]"
   	 
	reg r0 [format 0x%08x $fl_base_adr]
	reg r1 [format 0x%08x $f_sec]
	reg sp 0x20001000
    reg pc 0x20000058
	resume
	wait_halt
	
	set r0 [expr [lindex [ocd_reg 0] 2]]
	if { $r0 != 0 } { 
		puts "ERROR:: Not able to erease"
	} 
	puts ">>>>    FlashErease: stop"

	set time_brisi [clock seconds]
	puts "time erease: [expr $time_brisi - $time_init] sec"
	
#r0 :: fl_adr   // destination address for image flash block
#r1 :: sn       // flash block size (bytes)
#r2 :: SRAM_BUF // source address for image flash block (data for flash)
	puts ">>>>   FLASH image: $Filename to [format 0x%08x $fl_base_adr]"		

	set fl_sec $fl_bank
	set fl_adr $fl_base_adr
	set fl_end_adr [expr $fl_base_adr + $f_size]

	while {$fl_adr < $fl_end_adr} {
		set s [expr $fl_end_adr - $fl_adr]
		if {$s > $BUF_SIZE} {
			set s $BUF_SIZE
		}
		set sn [expr (($s+511) & ~511)]
		set dn [expr ($sn/512)]
		
		puts ">> Flash Sector: $fl_sec-[expr ($fl_sec + $dn -1)] => [format 0x%08x $fl_adr] ($s)"
#		puts "     SRAM load : $Filename => $SRAM_BUF"
#		puts "     FLASH addr: reg r0 [format 0x%08x $fl_adr]"
#		puts "     SIZE  addr: reg r1 [format 0x%08x $sn]"
#		puts "     BUFFR addr: reg r2 $SRAM_BUF"
  		          
		load_image $Filename [expr ($SRAM_BUF - $fl_adr)] $f_type $SRAM_BUF $BUF_SIZE
		
		reg r0 [format 0x%08x $fl_adr]
		reg r1 [format 0x%08x $sn]
		reg r2 $SRAM_BUF
		reg sp 0x20001000
		reg pc 0x200000ae
		resume
		 
		wait_halt
		set r0 [expr [lindex [ocd_reg 0] 2]]
		if { $r0 != 0 } { 
			puts "ERROR:: FlashImage"
		} 
		set fl_adr [expr $fl_adr + $s]
		set fl_sec [expr $fl_sec + $dn]			
	}
	puts ">>>>   FLASH image: stop"
	
	puts ">>>>    Verify: verify_image $Filename $fl_base_adr" 	
	verify_image $Filename $fl_base_adr
	
	set time_stop [clock seconds]
	
	puts "time write: [expr $time_stop - $time_brisi] sec"
	puts "time summary: [expr $time_stop - $time_start] sec"
	
}




