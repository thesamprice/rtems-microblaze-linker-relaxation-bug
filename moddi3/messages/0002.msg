microblaze: use the generic __moddi3 instead of the assembly one

ALTERNATIVE to the previous patch -- apply one or the other, not both.
This one applies to an unpatched tree, not on top of 1/2.

Hand-writing this helper is close to unique.  ia64 is the only other target
with a moddi3 in assembly, and its reason does not transfer -- lib1funcs.S
builds it out of the FP divide sequence from the Intel optimization guide.
visium supplies a C version, pa rebuilds the generic one for a 32-bit word,
and arm/symbian, avr, bpf and nds32-mculib exclude the helper outright.  No
other port hand-writes radix-2 soft division.  Since this one turned out to
be wrong for almost every input, the obvious question is whether it should
exist at all.

Drop it and stop excluding _moddi3.  __udivmoddi4, which the generic
__moddi3 calls, is not in LIB2FUNCS_EXCLUDE, so nothing else is needed.

Xilinx already did this, twelve years ago.  Commit 7090a49d007 in their GCC
fork, 2014-04-18, by Nagaraju Mekala -- "[Patch, microblaze] Removed moddi3
routinue" -- deletes the file, with the whole message being "Using the default
moddi3 function as the existing implementation has many bugs".  Its
t-microblaze hunk is identical to the one below.  It was never submitted
upstream, so both their 4.8.3 and 13.3.0 trees have been on the generic path
while upstream kept the routine.

This removes 121 lines of assembly no other port has an equivalent of, and
removes the endianness hazard entirely: the C version reads the halves
through a union rather than by register number.

The cost is size and speed.  Measured on qemu-system-microblaze and
qemu-system-microblazeel over 4701 values, counting executed instructions
exactly with -icount 0, against the assembly as 1/2 leaves it:

                       code size      executed insns
  assembly __moddi3        44      be 2777735  le 2777672
  generic C at -O2         62      be 3995016  le 3988505
    + __udivmoddi4     be 1030
                       le 1028
    total              be 1092       +43.8%      +43.6%
                       le 1090

So the assembly is about 25 times smaller and runs about 30% fewer
instructions, some 258 per call.  The size figure is the worst case: __udivmoddi4 is
shared, so a program that already does 64-bit unsigned division links it
anyway and the generic __moddi3 then costs only 62 instructions.

The two also differ for x % 0, which is undefined either way.  The assembly
returns zero, matching the port's other software helpers.  The generic
version returns the low word of the dividend -- 0x123456789abc % 0 gives
0x9abc -- because libgcc2.c does "d0 = 1 / d0" to provoke a hardware trap,
and on MicroBlaze that is a call to __udivsi3, which itself returns zero
for a zero divisor, so no trap occurs and the algorithm runs on with d0
still zero.  For reference, neither matches the hardware-divide path: with
idiv available GCC implements a % b as a - (a / b) * b, so a % 0 gives a.

Correctness is otherwise equal.  Both pass
gcc.c-torture/execute/arith-rand-ll.c on both byte orders, where the
unpatched tree aborts, and both answer all 8192 of a corner-case set that
drives the assembly's partial remainder to 2^63 -- every pair there has
LLONG_MIN as the dividend, which is where the unpatched routine either hangs
or returns nonsense.

libgcc/
	* config/microblaze/moddi3.S: Delete.
	* config/microblaze/t-microblaze (LIB2FUNCS_EXCLUDE): Do not
	exclude _moddi3.
	(LIB2ADD): Remove moddi3.S.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
