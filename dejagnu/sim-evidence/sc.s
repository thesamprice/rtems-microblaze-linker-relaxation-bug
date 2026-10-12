	.text
	.globl _start
_start:
	addi	r12, r0, 5		/* CB_SYS_write */
	addi	r5, r0, 1		/* fd = 1 */
	addi	r6, r0, msg		/* buf */
	addi	r7, r0, 12		/* len */
	brki	r14, 8
	addi	r3, r0, 0
	bri	0
msg:	.ascii	"sim writes\r\n"
