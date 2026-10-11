testsuite: cover 64-bit divide and modulo at the extremes of the type

Nothing in the testsuite does 64-bit signed divide or modulo with both
operands near the extremes of the type.  divmod-1.c covers the same ground
for signed char and signed short, and cannot be widened: it divides by -1,
which is fine there only because those types promote to int, while
INT_MIN / -1 and LLONG_MIN / -1 are not representable and so undefined.

That gap matters for any target whose 64-bit helpers do radix-2 restoring
division.  The partial remainder lives in one 64-bit register, and a divisor
near 2^63 can drive it to 2^63 -- the one point where a keep-or-skip decision
taken from the sign bit of a subtraction could disagree with the unsigned
comparison it stands in for.  Reaching it needs a dividend near 2^63 at the
same time, and no test in the tree pairs the two: of the five
gcc.c-torture/execute tests that call __moddi3, none reaches that state, and
the three runnable arch-neutral tests elsewhere that call it divide by 2, 5,
-2 or n - 10000.  pr50865.c comes closest, being INT64_MIN % 1, but its
divisors are all 1 so its partial remainder never leaves zero.

divmod-2.c pairs them, in three operand pairs plus the divide equivalents.
The file comment carries the reasoning, including why none of it is
undefined -- every quotient is -1, 0 or 1, and -1 is never a divisor.  It is
silent under -fsanitize=undefined.

MicroBlaze is where this came up, its hand-written __moddi3 being wrong for
almost every input, but the test is not target specific: unpatched it hangs
on microblaze-elf and aborts on microblazeel-elf, and it passes with that
routine fixed, with libgcc's generic __moddi3, and on the host.

gcc/testsuite/
	* gcc.c-torture/execute/divmod-2.c: New test.

Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude (Anthropic)
