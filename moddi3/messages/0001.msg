microblaze: fix the hand-written 64-bit signed modulo

The fix below is Ramin Moussavi's, carried in OpenADK as
toolchain/gcc/patches/16.2.0/0010; he has agreed to its being submitted
here.  What I added to it is at the end of this message.

libgcc/config/microblaze/moddi3.S has been in the tree unchanged since the
port landed in 2010 (809201325afb); the only commits touching it since are
copyright-year bumps and the two libgcc reorganizations.  It is wrong for
almost every input, and does not terminate for LLONG_MIN on either
endianness.

Four defects:

1. The register pair order is hard-coded for big-endian.  A 64-bit value
   passed in a register pair keeps its high word in the lower-numbered
   register on big-endian and in the higher-numbered one on little-endian,
   but the file treats r5 as the dividend's high word and r7 as the
   divisor's unconditionally.  On microblazeel it therefore operates on
   both operands with their halves swapped.  microblazeel support arrived
   in 4.8 (76ef61fbd9ed) and this file was never adjusted.

2. "Make Divisor Positive" negated the high word into r9 instead of r7,
   so a negative divisor kept its high word.  r9 had just been used as the
   scratch for the zero test.

3. The result sign came from the dividend XOR the divisor; a remainder
   takes the sign of the dividend alone.  Worse, both the sign fix-up and
   the "result is zero" paths wrote r29:r30 -- the quotient, which this
   function does not return -- while the return value is r3:r4.  The zero
   paths also branched in before r3:r4 were cleared, so 0 % v returned
   whatever the caller happened to leave in those registers.

4. The normalization loop looks for a set MSB after shifting, so a
   dividend of LLONG_MIN -- whose negation stays negative -- shifts its
   only set bit out on the first pass and the loop never terminates.

Name the halves with macros picked by __MICROBLAZEEL__ so one file serves
both, clear the remainder before the early exits, take the sign from the
dividend, negate the divisor's own high word, and skip normalization when
the dividend is already normalized.  The dead comparison into r18 (whose
result was never tested, and which compared against the dividend's low
word rather than the divisor's) is dropped, along with the label that no
longer has a reference and the branch that only existed to jump over it.

Division by zero keeps returning zero, with the reasoning now written down
next to the label: that is what divsi3.S, modsi3.S, udivsi3.S and
umodsi3.S return.  It does not match the hardware-divide path, and that
divergence predates this patch -- MicroBlaze has no remainder instruction,
so GCC implements a % b as a - (a / b) * b, and since idiv by zero yields
a zero quotient, a % 0 evaluates to a on a core with hardware divide.  The
hardware also sets MSR[DZ] and raises a divide exception where the core
implements one and MSR[EE] is set; a software helper can do neither.

While here, the comments are tidied and the algorithm is named.  The file
implements restoring division -- Koren, Computer Arithmetic Algorithms,
section 3.2, eq. 3.11 -- with the restore done by keeping a copy of the
previous remainder rather than adding the divisor back, the variant Koren
describes as avoiding the restore penalty.  The loop body, the
normalization step and the sign fix-up each carry an annotation naming the
part of that section they correspond to, so the two can be read side by
side.  That reference also states the property defect 3 above violated: a
remainder takes the sign of the dividend.  The header notes that libgcc's
generic path (__udivmoddi4 via longlong.h) is a different algorithm --
Knuth's Algorithm D, TAOCP volume 2 section 4.3.1 -- so the two are not
comparable step for step.

The rest of the tidy-up: the header said "modsi3.S ... modulo
operation for 64 bit integers", several comments transcribed the
instruction rather than explaining it, one still described the dividend by
register number after the halves were renamed, and the epilogue claimed to
restore CSRs and the operands when it restores callee-saved registers.
Trailing whitespace on the touched lines is removed.  Stripping every
comment from the result leaves .text byte-identical on both byte orders,
so none of the comment work reached the instruction stream.

The macros resolve at assembly time, so the endianness fix costs nothing at
run time: over a 4701-value check the two byte orders execute 3605340 and
3605277 instructions, 63 apart in 3.6 million.  The routine is five
instructions smaller than before, 55 against 60.

Verified on qemu-system-microblaze and qemu-system-microblazeel, machine
petalogix-s3adsp1800.  gcc.c-torture/execute/arith-rand-ll.c aborts on both
byte orders before this patch and passes on both after it.  A separate
4701-value check -- every sign combination, the 32-bit word boundaries,
LLONG_MAX, LLONG_MIN and 4000 random pairs, with the expected values
computed on the host -- gives the same result.  Traced under a QEMU TCG
plugin, that check reaches 55 of 55 instructions and 17 of 18 conditional
branch outcomes on both byte orders; the one outcome it misses is the
branch to the divide-by-zero label, which the vectors deliberately exclude.

The visible symptom that led here: uClibc-ng's gmtime() reduces a 64-bit
time_t with a signed modulo, so on microblazeel every timestamp past 2^31
came back with the wrong seconds field, and some year boundaries were a
day early.

libgcc/
	* config/microblaze/moddi3.S: Name the register-pair halves by
	endianness.  Fix the divisor negation, the result sign and the
	zero paths.  Do not normalize an already-normalized dividend.
	Tidy the comments.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
