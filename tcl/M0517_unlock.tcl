#-----------------------------------------------------------------------------
# Support function to Unlocks NuMicro M051x microcontrolers
#   for use with OpenOCD TCL
#
#  Copyright (c) 2015 Sasa Mihajlovixc
#
#-----------------------------------------------------------------------------
# openocd -f interface/stlink-v2.cfg -f target_M0517_win.cfg -f M0517_flash.tcl
# openocd -f interface/stlink-v2.cfg -f target_M0517_linux.cfg -f M0517_flash.tcl
# -s V:\tmp\openocd-0.8.0\bin
# -f M0517_unlock.tcl -f M0517_flash.tcl
# source M0517_flash.tcl
# source M0517_unlock.tcl
#
#-----------------------------------------------------------------------------

# based on:
#
# https://github.com/hackocopter/SWD-Hacking/blob/master/Nulink-Logs/Chip%20erase%20sequence.txt
# https://gist.github.com/TheLastMutt/d1c1948acaace7444c1c#file-mini51-cfg-L1
#
# https://github.com/hackocopter/SWD-Hacking/blob/master/KEIL-Flashtools/Mini51flashtools.ini
# Ported from KEIL to OpenOCD tcl language and added some comments.
# The chip erase sequence got reverse engineered using a Nulink programmer, a logic analyzer
# and custom SWD log parser software.
# Info here:
# https://github.com/hackocopter/SWD-Hacking
# https://www.mikrocontroller.net/topic/309185 (German forum)
 
proc mrw {adr} {
	set v ""
	mem2array v 32 $adr 1
	return $v(0)
}

proc UnlockFlash {} {
	halt
	mww 0x50000100 0x59
	mww 0x50000100 0x16
	mww 0x50000100 0x88
}
 
proc ISP_Write {adr dat} {
#	mww 0x5000c000 0x31
	mww 0x5000c00c 0x21
	mww 0x5000c004 $adr
	mww 0x5000c008 $dat
	mww 0x5000c010 1
	while {[mrw 0x5000c010] != 0} {
		puts "."
	} 
	if { [expr {[mrw 0x5000c000] & 0x40}] } {
		puts "ISP Error"
		return
	}
#	mww 0x5000c000 0x30
} 

proc ISP_Read {adr} {
	mww 0x5000c000 0x31
	mww 0x5000c00c 0x00
	mww 0x5000c004 $adr
	mww 0x5000c010 1
	while {[mrw 0x5000c010] != 0} {
		puts "."
	}
	set out [mrw 0x5000c008]
#	mww 0x5000c000 0x30
	return $out
}

   
proc ErasePage {adr} {
	mww 0x5000c000 0x31
	mww 0x5000c00c 0x22
	mww 0x5000c004 $adr
	mww 0x5000c010 1
	while {[mrw 0x5000c010] != 0} {
		puts "."
	}
	if { [expr {[mrw 0x5000c000] & 0x40}] } {
		puts "ISP Error"
		return
	}	 
#	mww 0x5000c000 0x30
}
 
proc WriteConf {} {
	UnlockFlash
	ErasePage 0x300000
	ISP_Write 0x300000 0xF8FFFFFF
#	ISP_Write 0x300004 0x1F000
	puts "User config written"
}

proc ReadConf {} {
	puts "Reading User Config. registers"
	UnlockFlash
	set conf0 [ISP_Read 0x300000]
	set conf1 [ISP_Read 0x300004]
	set id [mrw 0x50000000]
	puts [format "Config0 (0x00300000):0x%X" $conf0]
	puts [format "Config1 (0x00300004):0x%X" $conf1]
	puts [format "Device ID :0x%X" $id]
	if {[expr {($conf0 & 2)}]} {
		puts "Flash is not locked!"
	} else {
		puts "Flash is locked!\n  to erase whole chip perform:"
		puts "  => EraseChip"
		puts "  => WriteConf"
	}
}
 
proc EraseChip {} {
	UnlockFlash
	set conf0 [ISP_Read 0x300000]
	if {[expr {$conf0 & 2}]} {
		puts "Flash is not locked!"
		return
	}
	puts "Flash is locked!"
	mww 0x5000c000 0x31
	mww 0x5000c01c 0x01
	if { [expr {[mrw 0x5000c000] & 0x40}] } {
		puts "ISP Error"
		return
	}
	if {[mrw 0x5000c010] != 0} {
		puts "ISP error Busy"
		return
	}
	# Erase-Chip
	mww 0x5000c00c 0x26
	mww 0x5000c004 0
	puts "Chip erase..."
	mww 0x5000c010 1
	while {[mrw 0x5000c010] != 0} {
		puts "."
	} 
	if { [expr {[mrw 0x5000c000] & 0x40}] } {
		puts "ISP Error"
		return
	}
#	mww 0x5000c000 0x30

	set t_adr 0x00000000
	if {[ISP_Read $t_adr] == 0xffffffff } {
		set err "Erased!"
	} else {
		set err "Erase Error!"
	}
	puts [format "APROM: $err: ($t_adr):0x%X" [ISP_Read $t_adr]]

	set t_adr 0x00100000
	if {[ISP_Read $t_adr] == 0xffffffff } {
		set err "Erased!"
	} else {
		set err "Erase Error!"
	}
	puts [format "LDROM: $err: ($t_adr):0x%X" [ISP_Read $t_adr]]

	set t_adr 0x0030000
	if {[ISP_Read $t_adr] == 0xffffffff } {
		set err "Erased!"
	} else {
		set err "Erase Error!"
	}
	puts [format "Config: $err: ($t_adr):0x%X" [ISP_Read $t_adr]]
	
	mww 0x5000c01c 0
}

