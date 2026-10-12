	.text
	.globl _start
_start:
	addik	r1, r0, 0x400000	/* give ourselves a stack */
	addik	r3, r0, 42	/* main's return value, as crtinit leaves it */
	addik	r5, r3, 0	/* _start1: pass it to exit() in r5 per the ABI */
	brlid	r15, my_exit
	nop
my_exit:			/* newlib exit(int code): code arrives in r5 */
	addik	r1, r1, -8
	swi	r15, r1, 0
	brlid	r15, call_exitprocs	/* a void helper -- clobbers r3 */
	nop
	lwi	r15, r1, 0
	addik	r1, r1, 8
	/* falls into libgloss _exit; status is still only in r5 */
_exit:
	addik	r3, r5, 0	/* the one-line fix */
	bri	0
call_exitprocs:
	addik	r3, r0, 0	/* returns void; leaves 0 in r3 */
	rtsd	r15, 8
	nop
