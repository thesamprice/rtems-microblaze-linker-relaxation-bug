###################################
# 
#  Copyright (C) 2009-2026 Free Software Foundation, Inc.
#
#  Contributed by Michael Eager <eager@eagercon.com>.
#
#  This file is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the
#  Free Software Foundation; either version 3, or (at your option) any
#  later version.
#
#  GCC is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
#  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
#  License for more details.
#
#  Under Section 7 of GPL version 3, you are granted additional
#  permissions described in the GCC Runtime Library Exception, version
#  3.1, as published by the Free Software Foundation.
#
#  You should have received a copy of the GNU General Public License and
#  a copy of the GCC Runtime Library Exception along with this program;
#  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see
#  <http://www.gnu.org/licenses/>. 
#
#  moddi3.S
#
#  64-bit signed remainder.
#
#  Binary restoring division, one quotient bit per iteration:
#
#      r[i] = 2*r[i-1] - q[i]*D          (r[0] = X)
#
#  Each step shifts one dividend bit into the partial remainder and
#  subtracts the divisor, keeping the result only when it does not go
#  negative.  The restore is implicit: the trial subtraction lands in
#  scratch and is copied back only when kept, so a rejected step costs
#  nothing.  The shift needs one bit more than the register width, which is
#  the carry flag -- hence the ADD/ADDC chain rather than a shift.
#
#  The operands are reduced to unsigned magnitudes first, and the remainder
#  takes the sign of the dividend alone, not the exclusive or of the operand
#  signs -- that is the quotient's rule.
#
#  Koren, Computer Arithmetic Algorithms, section 3.2 is the reference.
# 
#######################################


/* An executable stack is *not* required for these functions.  */
#ifdef __linux__
.section .note.GNU-stack,"",%progbits
.previous
#endif

/* A 64-bit value passed in a register pair keeps its high word in the
   lower-numbered register on big-endian and the higher-numbered one on
   little-endian, so name the halves and let the body read the same either
   way.  Letters are Koren's: X dividend, D divisor, R remainder.

     OPX   X.  The loop consumes it from the top, so once it is running OPX
           holds only the bits of X not yet shifted into the remainder.
     OPD   D.  Not modified after the sign fix-up.
     RES   R, the return value; during the loop the partial remainder r[i],
           with RES:OPX the double-length remainder register.  */
#ifdef __MICROBLAZEEL__
# define OPX_L	r5
# define OPX_H	r6
# define OPD_L	r7
# define OPD_H	r8
# define RES_L	r3
# define RES_H	r4
#else
# define OPX_H	r5
# define OPX_L	r6
# define OPD_H	r7
# define OPD_L	r8
# define RES_H	r3
# define RES_L	r4
#endif

/* Working registers.  A pair only needs the endianness treatment above when
   it crosses an ABI boundary; these do not, so the halves are fixed.  What
   does matter is instruction order: low half first, since ADD and RSUB set
   the carry ADDC and RSUBC consume.

     r9        scratch for the two zero tests.  An argument register, so
               caller-saved -- free to clobber, nothing to spill.
     r25:r26   the trial subtraction 2*r[i-1] - D, high word in r25
     r27       the sign of X, kept as the whole high word because only BGEI
               reads it and that tests the sign
     r28       iterations remaining, 64 less whatever normalization skipped
     r29:r30   the quotient.  Dead -- this function returns the remainder --
               but the recurrence produces it.  Dropping it would save
               eleven instructions.

   r25 through r30 are callee-saved, hence the spills below.  */

	.globl	__moddi3
	.ent	__moddi3
__moddi3:
	.frame	r1,0,r15

	# Allocate the stack frame and save callee-saved registers.
	addik	r1,r1,-24
	swi	r25,r1,0
	swi	r26,r1,4
	swi	r27,r1,8	# Sign of X.
	swi	r28,r1,12	# Iterations remaining.
	swi	r29,r1,16	# Q, high word.
	swi	r30,r1,20	# Q, low word.

	ADDIK	RES_L,r0,0	# Clear the remainder.
	ADDIK	RES_H,r0,0

	# Handle a zero dividend and a zero divisor.
	OR	r9,OPX_H,OPX_L
	BEQID	r9,$LaRETURN_HERE	# 0 % n == 0.  The delay-slot OR below
					# only clobbers r9, which is dead at
					# the target.
	OR	r9,OPD_H,OPD_L
	BEQI	r9,$LaDiv_By_Zero
	# Reduce to unsigned magnitudes.  Negating LLONG_MIN leaves it negative
	# as a signed value, but the bit pattern is 2^63, which is the
	# magnitude the loop wants -- so "Abs" holds when read as unsigned.
	BGEId	OPX_H,$LaX_Abs
	OR	r27,r0,OPX_H		# Save the sign of X.
	RSUBI	OPX_L,OPX_L,0
	RSUBIC	OPX_H,OPX_H,0
$LaX_Abs:
	BGEI	OPD_H,$LaD_Abs
	RSUBI	OPD_L,OPD_L,0
	RSUBIC	OPD_H,OPD_H,0
$LaD_Abs:
	ADDIK	r29,r0,0		# Clear Q.
	ADDIK	r30,r0,0
	ADDIK	r28,r0,64		# One iteration per bit of X.
	# Already normalized: all 64 bits count.  Skipping this check would
	# hang on LLONG_MIN, whose magnitude has only the top bit set --
	# normalization would shift it out and never see a clear sign bit.
	BLTi	OPX_H,$LaRecurrence

	# Skip the dividend's leading zero bits, dropping the loop count to
	# match.  This changes no value; it only passes over iterations whose
	# quotient bits are known to be zero.
$LaNormalize:
	ADD	OPX_L,OPX_L,OPX_L
	ADDC	OPX_H,OPX_H,OPX_H
	BGEID	OPX_H,$LaNormalize
	ADDIK	r28,r28,-1
$LaRecurrence:
	# Form 2*r[i-1]: shift the RES:OPX pair left one bit, so the dividend's
	# top bit leaves OPX through the carry and enters RES at the bottom.
	# Order matters -- the carry flows low half to high.
	ADD	OPX_L,OPX_L,OPX_L
	ADDC	OPX_H,OPX_H,OPX_H
	ADDC	RES_L,RES_L,RES_L
	ADDC	RES_H,RES_H,RES_H
	# Subtract D into scratch and read the sign: q[i] = 1 when the result
	# is non-negative.  BLTi is a signed test settling an unsigned
	# comparison, which holds because D <= 2^63 and the loop keeps
	# 0 <= RES < D, so RES - D lands in [-D, D-1] -- always in signed
	# range, where the sign bit is the sign of the true difference.  That
	# bound is also why RES needs no 65th bit.
	RSUB	r26,OPD_L,RES_L
	RSUBC	r25,OPD_H,RES_H
	BLTi	r25,$LaQ_Bit_Is_Zero	# q[i] = 0; RES still holds r[i-1], so
					# there is nothing to restore.
	OR	RES_H,r0,r25		# q[i] = 1.  Keep 2*r[i-1] - D.
	OR	RES_L,r0,r26
	ADDI	r30,r30,1
	ADDC	r29,r29,r0
$LaQ_Bit_Is_Zero:
	ADDIK	r28,r28,-1
	BEQi	r28,$LaLOOP_END
	ADD	r30,r30,r30		# Shift Q up to make room for q[i-1].
	ADDC	r29,r29,r29
	BRI	$LaRecurrence
$LaLOOP_END:
	BGEI	r27,$LaRETURN_HERE
	# The remainder takes the sign of the dividend, not the exclusive or
	# of the operand signs -- that is the quotient's rule.
	RSUBI	RES_L,RES_L,0
	RSUBIC	RES_H,RES_H,0
	# Falls through: $LaDiv_By_Zero holds no instructions.
$LaDiv_By_Zero:
	# Division by zero is undefined in C.  Return zero, as divsi3.S,
	# modsi3.S, udivsi3.S and umodsi3.S do.  Note this does not match a
	# core with hardware divide, where a % b is a - (a / b) * b and a
	# zero quotient makes the remainder a; that divergence predates this
	# file and is discussed in the commit message.
$LaRETURN_HERE:
	# Restore the callee-saved registers and release the stack frame.
	lwi	r25,r1,0
	lwi	r26,r1,4
	lwi	r27,r1,8
	lwi	r28,r1,12
	lwi	r29,r1,16
	lwi	r30,r1,20
	rtsd	r15,8
	addik r1,r1,24
        .end __moddi3
	
