<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# bfd 0014: relaxation measures `st_size` from the new symbol value

**Patch:** `patches/binutils/0014-microblaze-relax-st_size-from-old-value.patch`
**Target:** `binutils-gdb` at `6d71cb48957` (`2026-09-08`), on top of 0013
**Files touched:** `bfd/elf32-microblaze.c`, `ld/testsuite/ld-microblaze/relax-size.{s,ld,d}`
**Status:** fix written, test A/B'd, `ld` suite clean; not yet sent upstream

A **third** relaxation defect, in the same two loops as
[0013](binutils-0013-relax-wrap-double-adjust.md) but independent of it: that
one corrupts symbol *values* under `--wrap`, this one corrupts symbol *sizes*
and needs no `--wrap` at all.

## The defect

`bfd/elf32-microblaze.c:2334-2336` (and the global twin below it) read:

```c
isym->st_value -= calc_fixup (isym->st_value, 0, sec);
if (isym->st_size)
  isym->st_size -= calc_fixup (isym->st_value, isym->st_size, sec);
```

`calc_fixup (start, size, sec)` with non-zero `size` sums the deletions in
`[start, start + size)` (`:1805-1823`). The span needing correction is the one
the symbol occupied *before* relaxation, so `start` has to be the old value.
The first line has already lowered it, so the window slides down by the
accumulated shift and counts the deletions of a span the symbol never covered.

Two conditions are needed for it to show, which is presumably why it went
unnoticed:

1. deletions **ahead of** the symbol — this is what shifts the window; and
2. a deletion **inside** the symbol, within that shift of its end — this is
   what then falls outside the window.

A function ending in a relaxable `IMM` + `BRI` pair satisfies (2) with a shift
of 8, i.e. two earlier deletions.

## Measured

`ld/testsuite/ld-microblaze/relax-size.s`: `a1` and `a2` each lose an `IMM` at
their own first instruction; `f` is four instructions, 16 bytes, ending in
`IMM` + `BRI`.

| symbol | in the object | `--no-relax` | `--relax`, before | `--relax`, after |
|---|---|---|---|---|
| `a1` | 0x14 | 0x14 | 0x10 | 0x10 |
| `a2` | 0x14 | 0x14 | 0x10 | 0x10 |
| `f` | 0x10 | 0x10 | **0x10** | 0x0c |

`a1` and `a2` are the control: their deletions sit inside the window either
way. `f`'s code really is twelve bytes after relaxation —

```
90000020 <f>:
90000020:	30600001 	addik	r3, r0, 1
90000024:	30630001 	addik	r3, r3, 1
90000028:	b8000014 	bri	20
9000002c <t1>:
```

— so a size of 16 overlaps `t1`. `objdump --disassemble=f` duly prints `t1`'s
first instruction as part of `f`.

## What other backends do

Unlike [0013](binutils-0013-relax-wrap-double-adjust.md), this one is **not**
inherited. `calc_fixup()` exists in no other `bfd/*.c` file, so the range-query
form of the mistake is only possible here.

`elfnn-riscv.c:4148-4160` is the closest thing to a precedent, and it names the
trap outright:

> If the symbol *spans* the bytes we just deleted (i.e. its *end* is in the
> moved bytes but its *start* isn't), then we must adjust its size.
>
> This test needs to use the original value of `st_value`, otherwise we might
> accidentally decrease size when deleting bytes right before the symbol. But
> since deleted relocs can't span across symbols, we can't have both a
> `st_value` and a `st_size` decrease, so it is simpler to just use an else.

RISC-V's `else` is sound *for RISC-V*: it deletes one site of `count` bytes at
`addr`, and a single deletion cannot both move a symbol and shrink it. That
reasoning does not carry over. `calc_fixup()` accumulates every deletion in the
section, so one relaxation pass can shift a symbol (deletions ahead of it) and
shrink it (deletions inside it) at the same time — `f` in the test does exactly
that. So the fix saves the old value rather than restructuring into an `else`;
an `else` here would silently stop correcting sizes whenever a symbol had moved.

Twelve backends adjust a *symbol's* size while relaxing: m10300, avr, m32c,
microblaze, msp430, nds32, pru, rl78, rx, v850, xtensa and riscv. cr16, crx,
ft32, sh and loongarch decrement only `sec->size`, never a symbol's — an
earlier draft of this note had that backwards, from counting `->size -=`
matches without checking what was on the left.

Of the ones that do, the three spot-checked besides riscv all avoid the
ordering trap structurally, the same way:

- `elf32-msp430.c:1874-1878` — `else if`, so the size test only runs when the
  value test did not.
- `elf32-pru.c:1291-1298` — likewise, in the `else` arm.
- `elf32-avr.c:2158-2165` — captures `symval` and `symend` *before* adjusting,
  then tests those.

So MicroBlaze is the outlier: it is the only one of the four examined that
performs both adjustments unconditionally and in sequence, which is what lets
the second read a value the first has already changed. The remaining eight
were not examined.

## Severity

Lower than 0013. Nothing executes differently: `st_size` on a function symbol
feeds debuggers, `nm -S`, `objdump --disassemble=`, and anything deriving
function bounds from the symbol table — so the effect is wrong attribution
rather than wrong code. It is worth fixing in the same series because it is
three lines and in the same hunk a reviewer is already reading for 0013.

## Verification

- `make check RUNTESTFLAGS=microblaze.exp` in `ld`: 5 passes with both fixes.
  Reverting only the `st_size` hunk and rebuilding gives
  `FAIL: MicroBlaze relaxation measures st_size from the old symbol value`
  and 4 passes, with 0013's test still passing — so each test catches its own
  bug and neither masks the other.
- Full `ld` suite with both fixes: 482 expected passes, 15 expected failures,
  **0 unexpected failures** (481 with 0013 alone, the difference being this
  patch's test).
