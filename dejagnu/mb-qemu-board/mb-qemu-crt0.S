/* Bare-metal startup for qemu-system-microblaze[el], machine
   petalogix-s3adsp1800.  Clears .bss, sets up the stack and small-data
   anchors, runs the init array, calls main and exits with its value.  */

/* An executable stack is not required.  Without this the linker warns
   "missing .note.GNU-stack section implies executable stack" for every test,
   which DejaGnu counts as excess errors and reports as a failure.  gcc emits
   it for compiled objects; a hand-written .S has to say so itself.  */
	.section .note.GNU-stack, "", %progbits
	.previous

	.section .vectors, "ax"
	.globl _start
_start:
	brai	_boot

	.text
	.globl _boot
_boot:
	addik	r1, r0, _stack_top	/* stack */
	addik	r13, r0, _SDA_BASE_	/* small data anchors newlib may use */
	addik	r2, r0, _SDA2_BASE_

	/* zero .bss */
	addik	r5, r0, __bss_start
	addik	r6, r0, __bss_end
1:	cmpu	r18, r5, r6
	bgei	r18, 2f
	swi	r0, r5, 0
	addik	r5, r5, 4
	bri	1b

2:	brlid	r15, __libc_init_array
	nop
	addik	r5, r0, 0		/* argc */
	addik	r6, r0, 0		/* argv */
	brlid	r15, main
	nop
	brlid	r15, exit		/* exit (main's return value) */
	addik	r5, r3, 0
3:	bri	3b
