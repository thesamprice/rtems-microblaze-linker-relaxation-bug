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
#  Restoring division: one quotient bit per iteration, each step comparing
#  the shifted remainder against the divisor and keeping the subtraction
#  only when it does not go negative.  In the notation of Koren, Computer
#  Arithmetic Algorithms, section 3.2 (sequential division), the loop below
#  is
#
#      r[i] = 2*r[i-1] - q[i]*D          (eq. 3.11, with r[0] = X)
#
#  The restore is implicit.  The trial subtraction lands in scratch
#  registers and is copied into the remainder only when it comes out
#  non-negative -- the "retaining a copy of the previous remainder" variant
#  Koren describes, which costs nothing where an add-back would cost an
#  extra operation on about half the iterations.
#
#  Koren also states the rule this routine has to satisfy: the sign of the
#  final remainder is the sign of the dividend, not the exclusive or of the
#  operand signs.  That exclusive or is the quotient's rule.
#
#  Shifting the remainder needs one bit more than the register width.  Here
#  that bit is the carry flag, which is why the shift is a chain of ADD
#  followed by ADDC rather than a shift instruction.
#
#  modsi3.S is the 32-bit form of the same algorithm and udivsi3.S the
#  unsigned one.  The generic C path in libgcc -- __udivmoddi4 through
#  longlong.h -- is a different algorithm: Knuth's Algorithm D, The Art of
#  Computer Programming volume 2, section 4.3.1, which is digit recurrence
#  at radix 2^16 with quotient-digit estimation rather than radix 2 with
#  none.
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
   independent of endianness.

   Koren section 3.2 calls the four values X the dividend, D the divisor,
   Q the quotient and R the remainder.  They live here as

     OP1   X.  The loop consumes it from the top, so once it is running OP1
           holds only the bits of X not yet shifted into the remainder.
     OP2   D.  Never modified after the sign fix-up.
     RES   R.  While the loop runs this is Koren's partial remainder r[i];
           RES:OP1 together are his double-length remainder register.

   Q has no register here -- that is the whole difference from moddi3.S.
   This function returns the remainder, so the quotient the recurrence would
   produce is never read; dropping it takes out eleven instructions.  */
#ifdef __MICROBLAZEEL__
# define OP1_L	r5
# define OP1_H	r6
# define OP2_L	r7
# define OP2_H	r8
# define RES_L	r3
# define RES_H	r4
#else
# define OP1_H	r5
# define OP1_L	r6
# define OP2_H	r7
# define OP2_L	r8
# define RES_H	r3
# define RES_L	r4
#endif

/* The scratch and callee-saved registers, with the value each one holds.
   Unlike the operand pairs above these need no endianness treatment: none of
   them is half of a value passed in or returned through the ABI, so there is
   no high/low to swap.  SIGN, COUNT and TRIAL are callee-saved and so are
   spilled by the prologue below; ZERO_T is caller-saved and is used without
   saving.  */
#define SIGN	r27	/* Sign of X, as the whole high word rather than just
			   its sign bit -- only BGEI reads it, and that tests
			   the sign.  */
#define COUNT	r28	/* Iterations remaining, 64 less whatever
			   normalization skipped.  */
#define TRIAL_H	r25	/* The trial subtraction 2*r[i-1] - D.  */
#define TRIAL_L	r26
#define ZERO_T	r9	/* Scratch for the two zero tests, dead immediately
			   afterwards.  */

	.globl	__moddi3
	.ent	__moddi3
__moddi3:
	.frame	r1,0,r15

	# Allocate the stack frame and save callee-saved registers.
	addik	r1,r1,-16
	swi	TRIAL_H,r1,0
	swi	TRIAL_L,r1,4
	swi	SIGN,r1,8
	swi	COUNT,r1,12

	ADDIK	RES_L,r0,0	# Clear the remainder.
	ADDIK	RES_H,r0,0

	# Handle a zero dividend and a zero divisor.
	OR	ZERO_T,OP1_H,OP1_L
	BEQID	ZERO_T,$LaRETURN_HERE	# 0 % n == 0.  The delay-slot OR below
					# only clobbers ZERO_T, which is dead at
					# the target.
	OR	ZERO_T,OP2_H,OP2_L
	BEQI	ZERO_T,$LaDiv_By_Zero
	# Divide the magnitudes.  Reaching $LaX_Abs means OP1 holds |X| and
	# reaching $LaD_Abs that OP2 holds |D| -- read as unsigned, which is
	# what matters here: negating LLONG_MIN leaves it negative as a signed
	# value, but the bit pattern it leaves is 2^63, and 2^63 is exactly
	# the magnitude the loop needs.
	BGEId	OP1_H,$LaX_Abs
	OR	SIGN,r0,OP1_H		# Save the sign of X.
	RSUBI	OP1_L,OP1_L,0
	RSUBIC	OP1_H,OP1_H,0
$LaX_Abs:
	BGEI	OP2_H,$LaD_Abs
	RSUBI	OP2_L,OP2_L,0
	RSUBIC	OP2_H,OP2_H,0
$LaD_Abs:
	ADDIK	COUNT,r0,64		# One iteration per bit of X.
	# Already normalized, so every one of the 64 bits counts.  LLONG_MIN
	# stays negative when negated, so without this check normalization
	# would shift its only set bit out and never see a clear sign bit,
	# leaving the loop non-terminating.
	BLTi	OP1_H,$LaRecurrence

	# Shift the dividend's first set bit up to the high bit of OP1_H and
	# drop the loop count to match.  This is not Koren's D1-style operand
	# scaling -- it changes no value, it only skips the leading iterations
	# whose quotient bits are known to be zero.
	#
	# Section 3.2 numbers equations rather than steps, so there are no
	# labels in the reference to borrow for any of this; the names below
	# pair Koren's symbol with what has just happened to it.  Resist
	# reaching for Knuth's D1..D8 -- those name the steps of the other
	# algorithm, the one the generic C path uses.
$LaNormalize:
	ADD	OP1_L,OP1_L,OP1_L
	ADDC	OP1_H,OP1_H,OP1_H
	BGEID	OP1_H,$LaNormalize
	ADDIK	COUNT,COUNT,-1
$LaRecurrence:
	# One step of r[i] = 2*r[i-1] - q[i]*D.
	#
	# RES:OP1 together hold Koren's double-length remainder, so shifting
	# the pair left by one bit forms 2*r[i-1]: the dividend's top bit
	# leaves OP1 through the carry flag and enters RES at the bottom.
	# That carry is the "extra bit position in the arithmetic unit" his
	# Example 3.4 notes the shift requires.
	ADD	OP1_L,OP1_L,OP1_L
	ADDC	OP1_H,OP1_H,OP1_H
	ADDC	RES_L,RES_L,RES_L
	ADDC	RES_H,RES_H,RES_H
	# Compare 2*r[i-1] against D, which Koren calls the most complicated
	# step: subtract into scratch and read the sign.  q[i] = 1 when the
	# result is non-negative, 0 otherwise.
	RSUB	TRIAL_L,OP2_L,RES_L
	RSUBC	TRIAL_H,OP2_H,RES_H
	BLTi	TRIAL_H,$LaQ_Bit_Is_Zero	# q[i] = 0.  Nothing to undo: the
					# old remainder was never overwritten,
					# so the restore costs nothing.
	OR	RES_H,r0,TRIAL_H	# q[i] = 1.  Keep 2*r[i-1] - D.
	OR	RES_L,r0,TRIAL_L
$LaQ_Bit_Is_Zero:
	ADDIK	COUNT,COUNT,-1
	BNEi	COUNT,$LaRecurrence
	BGEI	SIGN,$LaRETURN_HERE
	# Koren section 3.3: "the sign of the final remainder must equal that
	# of the dividend".  Not the exclusive or of the operand signs, which
	# is the quotient's rule.
	RSUBI	RES_L,RES_L,0
	RSUBIC	RES_H,RES_H,0
	# Falls through: $LaDiv_By_Zero holds no instructions.
$LaDiv_By_Zero:
	# Division by zero is undefined in C.  Match the other software
	# helpers -- divsi3.S, modsi3.S, udivsi3.S and umodsi3.S -- by
	# returning zero.
	#
	# This differs from the hardware-divide path.  MicroBlaze has no
	# remainder instruction, so GCC implements a % b as
	#
	#     a - (a / b) * b
	#
	# and hardware division by zero produces a zero quotient, making the
	# synthesized remainder a.  Hardware division also sets MSR[DZ] and
	# raises a divide exception where the core implements one and MSR[EE]
	# is set.  A software helper can reproduce none of that.
$LaRETURN_HERE:
	# Restore the callee-saved registers and release the stack frame.
	lwi	TRIAL_H,r1,0
	lwi	TRIAL_L,r1,4
	lwi	SIGN,r1,8
	lwi	COUNT,r1,12
	rtsd	r15,8
	addik	r1,r1,16
        .end __moddi3
	
