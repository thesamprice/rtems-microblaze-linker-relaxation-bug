/* Minimal MicroBlaze sim test: exit with a chosen code.
   The sim's protocol (sim/microblaze/interp.c + sim/testsuite/microblaze/
   testutils.inc) is: put the code in r3, then bri 0 (0xb8000000) halts. */
	.text
	.globl _start
_start:
	addi	r3, r0, EXITCODE
	bri	0
