<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# bfd 0013: relaxation adjusts a wrapped symbol's value twice

**Patch:** `patches/binutils/0013-microblaze-relax-wrap-double-adjust.patch`
**Target:** `binutils-gdb` at `6d71cb48957` (`2026-09-08`), which already carries
`a639e0adaf2` (the `sh_info` bounds fix) — this is a **second, independent**
relaxation defect, not a variant of that one
**Files touched:** `bfd/elf32-microblaze.c`, `ld/testsuite/ld-microblaze/relax-wrap.{s,ld,d}`, `ld/testsuite/ld-microblaze/relax-wrap-support.s`
**Status:** fix written, reproducer reduced, `ld` suite clean; not yet sent upstream

## How it was found

Not by looking for it. Converting `dejagnu/mb-qemu-board` from its own
`*** EXIT n ***` marker to DejaGnu's standard `needs_status_wrapper`
protocol, every execution test came back with status 2 — no marker printed.
The glue linked, `__wrap_main` called `main` and then `__wrap_exit` correctly,
and `write` worked (a `main` that called it printed fine). `__wrap_exit`
itself produced nothing.

Its first instruction was the reason:

```
900006c8 <__wrap_exit>:
900006c8:	b60f0008 	rtsd	r15, 8      <- returns immediately
900006cc:	80000000 	or	r0, r0, r0
900006d0:	3021ffbc 	addik	r1, r1, -68 <- the real prologue
```

The symbol sat eight bytes before its own function. `-Wl,--no-relax` put it
back.

## Root cause

`bfd/elf32-microblaze.c:2339-2355` adjusts the global symbols defined in the
section being relaxed by walking `elf_sym_hashes (abfd)` by index:

```c
sym_hash = elf_sym_hashes (abfd)[sym_index];
if (... && sym_hash->root.u.def.section == sec)
  sym_hash->root.u.def.value -= calc_fixup (sym_hash->root.u.def.value, 0, sec);
```

With `--wrap SYMBOL`, a reference to `SYMBOL` resolves to `__wrap_SYMBOL`. An
object that both **defines** `__wrap_SYMBOL` and **refers to** `SYMBOL` has two
symbol table entries whose `elf_sym_hashes` slots point at the same
`elf_link_hash_entry`. The loop therefore reaches it twice and subtracts the
fixup twice.

Instrumenting the loop shows it directly, on `gcc-testglue.o`:

```
MBRELAX   glob[3]  __wrap_exit   value=0xd4  fixup=8  -> 0xcc
MBRELAX   glob[9]  __wrap_abort  value=0x2e4 fixup=32 -> 0x2c4
MBRELAX   glob[11] __wrap_abort  value=0x2c4 fixup=32 -> 0x2a4
MBRELAX   glob[14] __wrap_exit   value=0xcc  fixup=8  -> 0xc4
```

`__wrap_exit` ends 8 low, `__wrap_abort` 32 low. Comparing symbol values
against the real prologues in the linked image agrees exactly:

| symbol | binding | symbol value | real prologue | error |
|---|---|---|---|---|
| `write_int` | local | 0x90000604 | 0x90000604 | — |
| `__wrap_exit` | global | 0x900006c8 | 0x900006d0 | 8 low |
| `__wrap__exit` | global | 0x900007cc | 0x900007cc | — |
| `__wrap_abort` | global | 0x900008a8 | 0x900008c8 | 32 low |
| `__wrap_main` | global | 0x90000910 | 0x90000910 | — |

The true shifts are a monotonic `-44, -52, -64, -76, -88`; the symbol values
got `-44, -60, -64, -108, -88`. A shrink-only transformation cannot produce a
non-monotonic shift, which is what first showed something was wrong.

Locals are unaffected: the local loop at `:2328-2338` walks `isymbuf`, one
entry per symbol, with no aliasing.

## The fix

`bfd/elf32-ft32.c:923-945` already carries exactly this guard, with a comment
naming `--wrap` as the cause. The patch copies it: before adjusting, scan the
slots already visited and skip the entry if it appears among them. The scan
runs only when `link_info->wrap_hash != NULL`, so non-`--wrap` links are
untouched.

### This is a known defect elsewhere, with a named fix

Not a new bug — a bug other backends have already had and fixed. Traced by
`git log -S "we don't want to adjust" -- bfd/`:

| commit | date | backend | what |
|---|---|---|---|
| `e3f9830cf4a` | 2004-12-14 | crx | guard present from the port |
| `3d3d428f048` | 2007-06-29 | cr16 | guard present from the port |
| `81b42bcab16` | 2017-11-01 | ft32 | guard arrives with FT32B relaxation |
| **`7f02625eb48`** | **2018-02-02** | **riscv** | **"RISC-V: Fix --wrap and relaxation conflict", PR ld/22756** |
| `1b6fccd28db` | 2022-12-01 | loongarch | guard present when relaxation was added |

`7f02625eb48` is the direct precedent: same bug, same cause, and the comment
block is textually identical to the one this patch adds. `elf32-m32c.c:458`
solves the same problem differently, via `unwrap_hash_lookup()`.

### Why MicroBlaze missed it

Provenance, not reasoning. MicroBlaze relaxation arrived with the port
(`7ba29e2a41a`, 2009-08-06, "Add support for Xilinx MicroBlaze processor"),
and its symbol-adjustment loops follow `bfd/elf32-sh.c`, which has no guard to
this day. The guard already existed in crx and cr16 in 2009, but there was no
reason to go looking for it.

Of the backends that adjust global symbols while deleting bytes, cr16, crx,
ft32, loongarch and riscv have the guard; sh, m10200, m10300, avr, h8300,
ip2k, m68hc11, msp430, pru, rl78, rx, v850, mips and microblaze do not. **Only
microblaze was tested.** Most of the others adjust against a per-deletion
window (`value > addr && value < toaddr`) rather than an accumulated fixup,
which may or may not mask the problem, so no claim is made about them.

### Why it is worse here than it was on RISC-V

`calc_fixup()` is unique to this backend (`grep` across `bfd/*.c` finds it
nowhere else). Other backends delete one site at a time and subtract a fixed
`count`, so a double adjustment costs that one count — 4 bytes. MicroBlaze
builds a relax table for the whole section and subtracts the *total* of every
deletion ahead of the symbol, so the second subtraction is as large as the
first: 8 bytes for `__wrap_exit`, 32 for `__wrap_abort`.

## Why it matters beyond this repo

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so every
MicroBlaze link relaxes by default.

DejaGnu's `testglue.c` has precisely the triggering shape — it defines
`__wrap_exit` and calls `exit`, defines `__wrap_abort` and calls `abort`. It
is what GCC links into every execution test on a board that sets
`needs_status_wrapper`, and it prints the `*** EXIT code N` line that
`remote.exp`'s `check_for_board_status` parses. On MicroBlaze that wrapper
has never worked: `__wrap_exit` lands on the previous function's closing
`ADDIK r1, r1, 28`, so it releases 28 bytes of someone else's frame and falls
through. No marker is printed, and `check_for_board_status` reports 2 for
every test.

That is a plausible part of why MicroBlaze has no upstream execution testing:
the standard mechanism for getting a test's exit status off a bare-metal
target is broken on this target, silently, and in a way that looks like the
board's fault.

## Reproducer

`ld/testsuite/ld-microblaze/relax-wrap.d` reduces it to eight instructions:
one deleted IMM, `__wrap_foo` defined after it, and a call to `foo` from the
same object. `relax-wrap-support.s` holds the forward branch target in a
separate section — within one section the assembler resolves the branch itself
and emits no IMM, so there is nothing to delete and nothing to adjust. That
detail cost one wrong first attempt.

Measured:

| linker | `__wrap_foo` lands on |
|---|---|
| ld 2.36.1 (RTEMS 7 toolchain) | `addik r1, r1, 28` — previous function's epilogue |
| ld 2.46.50.20260624 | same |
| ld 2.47.50.20260908 (with `a639e0adaf2`) | same |
| ld 2.47.50.20260908 + this patch | `addik r3, r0, 42` — its own first instruction |

## Verification

- `make check RUNTESTFLAGS=microblaze.exp` in `ld`: 4 passes with the patch.
  Reverting only `bfd/elf32-microblaze.c` and rebuilding gives 3 passes and
  `FAIL: MicroBlaze relaxation adjusts a wrapped symbol only once` — so the
  test detects the bug it was written for, and the three existing
  `relax-addend` tests are unaffected either way.
- Full `ld` suite with the patch: 481 expected passes, 15 expected failures,
  **0 unexpected failures**. A without-patch run of the *full* suite was not
  done; only `microblaze.exp` was run both ways.
- Reading these two loops for this bug turned up a third, independent defect
  in the `st_size` line beside it — see
  [0014](binutils-0014-relax-st_size-from-old-value.md).
- End to end: a guest calling `exit (7)` prints `*** EXIT code 7` with the
  patched linker and nothing at all without it.
- `dejagnu/mb-qemu-board` on the standard protocol gives the same verdicts as
  the old bespoke marker on the six-test validation set — five pass,
  `pr111151.c` fails its execution test — with 21 `*** EXIT code` markers
  parsed and none of the old format left.
