###################################
#
#  64-bit signed quotient.
#
#  Restoring division: one quotient bit per iteration.  See Koren, Computer
#  Arithmetic Algorithms, section 3.2 (sequential division), eq. 3.11:
#
#      r[i] = 2*r[i-1] - q[i]*D          (with r[0] = X)
#
#  The restore is implicit -- the trial subtraction lands in scratch and is
#  kept only when non-negative.  The quotient sign is the exclusive or of
#  the operand signs; a remainder would instead take the dividend's sign.
#
#  divsi3.S is the 32-bit form of the same algorithm and udivsi3.S the
#  unsigned one.  libgcc's generic __udivmoddi4 is a different algorithm:
#  Knuth's Algorithm D, TAOCP volume 2, section 4.3.1.
#
#######################################

/* An executable stack is *not* required for these functions.  */
#ifdef __linux__
.section .note.GNU-stack,"",%progbits
.previous
#endif

/* A 64-bit value held in a register pair keeps its high word in the
   lower-numbered register on big-endian and in the higher-numbered one on
   little-endian.  Name the halves so that the implementation below is
   independent of endianness.  */
#ifdef __MICROBLAZEEL__
# define OP1_L	r5
# define OP1_H	r6
# define OP2_L	r7
# define OP2_H	r8
# define QUO_L	r3
# define QUO_H	r4
#else
# define OP1_H	r5
# define OP1_L	r6
# define OP2_H	r7
# define OP2_L	r8
# define QUO_H	r3
# define QUO_L	r4
#endif

/* Scratch.  Fixed regardless of byte order: none of these cross the ABI.  */
#define SIGN	r27		/* Sign of the quotient.  */
#define COUNT	r28		/* Loop counter.  */
#define REM_H	r29		/* Running remainder.  */
#define REM_L	r30
#define TRIAL_H	r25		/* Trial subtraction result.  */
#define TRIAL_L	r26
#define ZERO_T	r9		/* Scratch for the zero tests.  */

	.globl	__divdi3
	.ent	__divdi3
__divdi3:
	.frame	r1,0,r15

	# Allocate the stack frame and save callee-saved registers.
	addik	r1,r1,-24
	swi	TRIAL_H,r1,0
	swi	TRIAL_L,r1,4
	swi	SIGN,r1,8
	swi	COUNT,r1,12
	swi	REM_H,r1,16
	swi	REM_L,r1,20

	ADDIK	QUO_L,r0,0	# Clear the quotient.
	ADDIK	QUO_H,r0,0

	# Handle a zero dividend and a zero divisor.
	OR	ZERO_T,OP1_H,OP1_L
	BEQID	ZERO_T,$LaRETURN_HERE	# 0 / n == 0.  The delay-slot OR below
					# only clobbers ZERO_T, dead at the
					# target.
	OR	ZERO_T,OP2_H,OP2_L
	BEQI	ZERO_T,$LaDiv_By_Zero
	BGEId	OP1_H,$La1_Pos
	XOR	SIGN,OP1_H,OP2_H	# Quotient sign: dividend XOR divisor.
					# Both are still un-negated here.
	RSUBI	OP1_L,OP1_L,0		# Negate the dividend magnitude.
	RSUBIC	OP1_H,OP1_H,0
$La1_Pos:
	BGEI	OP2_H,$La2_Pos
	RSUBI	OP2_L,OP2_L,0		# Negate the divisor magnitude.
	RSUBIC	OP2_H,OP2_H,0
$La2_Pos:
	ADDIK	REM_H,r0,0		# Clear the remainder.
	ADDIK	REM_L,r0,0
	ADDIK	COUNT,r0,64		# Initialize the loop count.
	BLTi	OP1_H,$LaDIV2		# Already normalized: use all 64 bits.
					# LLONG_MIN stays negative when negated,
					# so skipping this check would shift its
					# only set bit out below and leave the
					# loop non-terminating.

	# Normalize the dividend by shifting its first set bit into the
	# high bit of OP1_H.
$LaDIV1:
	ADD	OP1_L,OP1_L,OP1_L
	ADDC	OP1_H,OP1_H,OP1_H
	BGEID	OP1_H,$LaDIV1
	ADDIK	COUNT,COUNT,-1
$LaDIV2:
	# Shift the quotient first so the loop tail needs no special case for
	# the final iteration; bit 0 is then free for the bit decided below.
	ADD	QUO_L,QUO_L,QUO_L
	ADDC	QUO_H,QUO_H,QUO_H
	ADD	OP1_L,OP1_L,OP1_L
	ADDC	OP1_H,OP1_H,OP1_H	# Shift the next dividend bit into carry.
	ADDC	REM_L,REM_L,REM_L	# Shift it into the remainder.
	ADDC	REM_H,REM_H,REM_H
	RSUB	TRIAL_L,OP2_L,REM_L	# Trial subtraction.
	RSUBC	TRIAL_H,OP2_H,REM_H
	BLTi	TRIAL_H,$LaDIV_TOO_SMALL
	OR	REM_H,r0,TRIAL_H	# Keep the reduced remainder,
	OR	REM_L,r0,TRIAL_L
	ADDIK	QUO_L,QUO_L,1		# and record the quotient bit.
$LaDIV_TOO_SMALL:
	ADDIK	COUNT,COUNT,-1
	BNEi	COUNT,$LaDIV2
	BGEI	SIGN,$LaRETURN_HERE
	RSUBI	QUO_L,QUO_L,0		# Apply the quotient sign.
	RSUBIC	QUO_H,QUO_H,0
	# Falls through: $LaDiv_By_Zero holds no instructions.
$LaDiv_By_Zero:
	# Division by zero is undefined in C.  Return zero, which is what
	# divsi3.S, modsi3.S, udivsi3.S and umodsi3.S return.
$LaRETURN_HERE:
	# Restore the callee-saved registers and release the stack frame.
	lwi	TRIAL_H,r1,0
	lwi	TRIAL_L,r1,4
	lwi	SIGN,r1,8
	lwi	COUNT,r1,12
	lwi	REM_H,r1,16
	lwi	REM_L,r1,20
	rtsd	r15,8
	addik	r1,r1,24
	.end __divdi3
	.size	__divdi3, . - __divdi3
