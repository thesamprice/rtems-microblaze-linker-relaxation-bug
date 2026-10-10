	.section .vectors, "ax"
	.globl _start
_start:
	brai	_boot
	.text
_boot:
	addik	r1, r0, _stack_top
	brlid	r15, main
	nop
1:	bri	1b
