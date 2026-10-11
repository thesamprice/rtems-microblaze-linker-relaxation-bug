microblaze: use the generic __moddi3 instead of the assembly one

ALTERNATIVE to the previous patch -- apply one or the other, not both.
This one applies to an unpatched tree, not on top of 1/2.

MicroBlaze is the only target in the tree with a hand-written assembly
moddi3: visium supplies a C one and bpf excludes the helper, every other
target uses the generic libgcc2.c version.  Since that assembly turned out
to be wrong for almost every input, the obvious question is whether it
should exist at all.

Drop it and stop excluding _moddi3.  __udivmoddi4, which the generic
__moddi3 calls, is not in LIB2FUNCS_EXCLUDE, so nothing else is needed.

This is the change Xilinx's own GCC already carries.  Both their 4.8.3 and
13.3.0 trees have _moddi3 out of LIB2FUNCS_EXCLUDE and moddi3.S out of
LIB2ADD, so the vendor toolchain has been using the generic C version rather
than this file; 4.8.3 deletes it outright.
This removes 121 lines of assembly no other port has an equivalent of, and
removes the endianness hazard entirely: the C version reads the halves
through a union rather than by register number.

The cost is size and speed.  Measured on qemu-system-microblaze and
qemu-system-microblazeel over 4701 values, counting executed instructions
exactly with -icount 0, against the assembly as 1/2 leaves it:

                       code size      executed insns
  assembly __moddi3        55      be 3605340  le 3605277
  generic C at -O2         62      be 3995016  le 3988505
    + __udivmoddi4     be 1030
                       le 1028
    total              be 1092       +10.8%      +10.6%
                       le 1090

So the assembly is about 20 times smaller and about 10% faster, roughly 82
instructions per call.  The size figure is the worst case: __udivmoddi4 is
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

Correctness is otherwise equal -- both pass
gcc.c-torture/execute/arith-rand-ll.c on both byte orders, where the
unpatched tree aborts.

libgcc/
	* config/microblaze/moddi3.S: Delete.
	* config/microblaze/t-microblaze (LIB2FUNCS_EXCLUDE): Do not
	exclude _moddi3.
	(LIB2ADD): Remove moddi3.S.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
