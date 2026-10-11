microblaze: fix the hand-written 64-bit signed modulo

The fix below is Ramin Moussavi's, carried in OpenADK as
toolchain/gcc/patches/16.2.0/0010; he has agreed to its being submitted
here.  What I added to it is at the end of this message.

libgcc/config/microblaze/moddi3.S has been in the tree unchanged since the
port landed in 2010 (809201325afb); the only commits touching it since are
copyright-year bumps and the two libgcc reorganizations.  It is wrong for
almost every input, and for an LLONG_MIN dividend it either fails to
terminate or returns nonsense, depending on the byte order.

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
the dividend is already normalized.

Defect 3 is also why the quotient goes.  The original computed it in
r29:r30 and then returned it by mistake; with the return value corrected,
nothing reads it.  Dropping it removes four instructions from the loop
body, two from the setup, and two register pairs from the frame -- sixteen
instructions of code against the original, and 23% of the executed
instructions against keeping it:

                         code size     executed insns over 4701 calls
  before                      60       does not terminate
  keeping the quotient        55       be 3605340   le 3605277
  as sent here                44       be 2777735   le 2777672

The dead comparison into r18 -- whose result was never tested, and which
compared against the dividend's low word rather than the divisor's -- is
dropped too, along with the label that no longer has a reference and the
branch that only existed to jump over it.

Division by zero keeps returning zero, with the reasoning now written down
next to the label: that is what divsi3.S, modsi3.S, udivsi3.S and
umodsi3.S return.  It does not match the hardware-divide path, and that
divergence predates this patch -- MicroBlaze has no remainder instruction,
so GCC implements a % b as a - (a / b) * b, and since idiv by zero yields
a zero quotient, a % 0 evaluates to a on a core with hardware divide.  The
hardware also sets MSR[DZ] and raises a divide exception where the core
implements one and MSR[EE] is set; a software helper can do neither.

The keep-or-skip decision reads the sign bit of a 64-bit subtraction to
settle an unsigned comparison.  That is sound, and the file now says why
where the comparison is: D <= 2^63 because it is the magnitude of a signed
64-bit value, and the loop keeps 0 <= RES < D, so RES - D lies in [-D, D-1]
and is always in signed range, where the sign bit means what the test takes
it to mean.  The same bound is why a 64-bit partial remainder suffices with
no 65th bit.

The comments are rewritten and the registers named.  The operand macros
carry the reference's letter -- OPX and OPD for dividend X and divisor D,
RES for the remainder R -- and the working registers get names too, so the
body reads without a register map.  The labels follow: $La1_Pos and
$La2_Pos said nothing and were not even accurate, since negating LLONG_MIN
leaves it negative, so they become $LaX_Abs and $LaD_Abs with a note that
what the loop needs is the unsigned magnitude, which that bit pattern is.
$LaDIV1 and $LaDIV2 name neither a "div 1" nor a "div 2" and become
$LaNormalize and $LaRecurrence, and $LaMOD_TOO_SMALL becomes
$LaQ_Bit_Is_Zero.

The header had said "modsi3.S ... modulo operation for 64 bit integers";
several comments transcribed the instruction rather than explaining it; one
described the dividend by register number after the halves were renamed;
one claimed to "shift a '1' into the quotient" where the instruction
doubled the quotient to make room for the next bit; and the epilogue
claimed to restore CSRs and the operands when it restores callee-saved
registers.  Trailing whitespace on the touched lines is removed.

The macros resolve at assembly time, so the endianness fix costs nothing at
run time: the two byte orders execute 2777735 and 2777672 instructions over
the 4701-value check, 63 apart in 2.8 million.

Verified on qemu-system-microblaze and qemu-system-microblazeel, machine
petalogix-s3adsp1800.  gcc.c-torture/execute/arith-rand-ll.c aborts on both
byte orders before this patch and passes on both after it.  A separate
4701-value check -- every sign combination, the 32-bit word boundaries,
LLONG_MAX, LLONG_MIN and 4000 random pairs, with the expected values
computed on the host -- gives the same result, as does an 8192-value set
built to drive the partial remainder to 2^63, which is the only place the
signed comparison above could have gone wrong.

The visible symptom that led here: uClibc-ng's gmtime() reduces a 64-bit
time_t with a signed modulo, so on microblazeel every timestamp past 2^31
came back with the wrong seconds field, and some year boundaries were a
day early.

libgcc/
	* config/microblaze/moddi3.S: Name the register-pair halves by
	endianness.  Fix the divisor negation, the result sign and the
	zero paths.  Do not normalize an already-normalized dividend.
	Do not compute the quotient, which is not returned.  Drop the
	dead comparison, the unreferenced label and the branch over it.
	Name the working registers and the labels after the reference
	algorithm, and state the invariant the trial subtraction relies
	on.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
