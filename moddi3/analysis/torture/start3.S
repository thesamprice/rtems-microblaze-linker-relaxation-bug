	.section .vectors, "ax"
	.globl _start
_start:
	brai	_boot
	.text
_boot:
	addik	r1, r0, _stack_top
	# Zero .bss -- torture tests rely on static storage starting at zero.
	addik	r5, r0, __bss_start
	addik	r6, r0, __bss_end
1:	cmpu	r18, r5, r6
	bgei	r18, 2f
	swi	r0, r5, 0
	addik	r5, r5, 4
	bri	1b
2:	brlid	r15, main
	addik	r5, r0, 0		# argc = 0 in the delay slot
	brlid	r15, exit		# main returned: exit(its value)
	addik	r5, r3, 0
3:	bri	3b
