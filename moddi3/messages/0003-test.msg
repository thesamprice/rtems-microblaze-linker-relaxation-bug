testsuite: cover 64-bit divide and modulo at the extremes of the type

divmod-1.c checks division and modulo at the minimum of signed char and
signed short, using -1 as the divisor.  It cannot be extended to int or long
long, which is worth saying because that is the obvious first thought: char
and short promote to int, so -128 / -1 and -32768 / -1 are evaluated in int
and are representable, while INT_MIN / -1 and LLONG_MIN / -1 are not and so
are undefined -- as is % -1 at the minimum, since C ties the one to the other.
Widening that test means changing the divisor, not just the type, and at that
point it is a different hazard rather than the same one at a larger size.

So nothing covers long long at its extremes with well-defined operands, and
that turns out to matter.

A target whose 64-bit helpers do radix-2 restoring division keeps a partial
remainder in one 64-bit register.  With a divisor close to 2^63 that
remainder can reach 2^63, which is the one point where a keep-or-skip
decision read from the sign bit of a subtraction could disagree with the
unsigned comparison it stands in for.  Reaching it needs a dividend within a
hair of 2^63 at the same time as such a divisor.

No test in the tree pairs those.  Linking an instrumented __moddi3 into all
1685 gcc.c-torture/execute tests and running them, five call it -- 920604-1,
arith-rand-ll, pr33669, pr50865 and pr85582-1 -- and none reaches the state.
Of the runnable tests elsewhere in the testsuite that do 64-bit modulo, three
are arch-neutral and emit the call, and their divisors are 2, 5, -2 and
n - 10000.  pr50865.c comes closest to this ground, being INT64_MIN % 1, and
its divisors are all 1 so its partial remainder never leaves zero.

divmod-2.c pairs them.  The operands are volatile so nothing is folded and
the target's helpers are actually reached.

This is not a MicroBlaze test, though MicroBlaze is where it came up: its
hand-written __moddi3 was wrong for almost every input, and on an unpatched
tree this test hangs on microblaze-elf and aborts on microblazeel-elf.  With
that routine fixed, or with libgcc's generic __moddi3 in its place, it passes
on both byte orders, as it does on the host.

gcc/testsuite/
	* gcc.c-torture/execute/divmod-2.c: New test.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
