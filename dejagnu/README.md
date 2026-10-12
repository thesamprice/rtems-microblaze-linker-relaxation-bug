# Running the GCC testsuite on MicroBlaze under QEMU

A DejaGnu board that gives MicroBlaze **execution** testing, not just
compilation testing.

This exists because of a remark on gcc-patches: that MicroBlaze has no GDB
simulator, which is what GCC testing normally uses, and that an attempt at
QEMU **user-mode** testing "failed miserably" — so MicroBlaze gets
compile-only coverage and no validation that the binaries actually work.

The premise turned out to be wrong in one respect and right in another.
**MicroBlaze does have a GDB simulator**, in `binutils-gdb/sim/microblaze/`,
maintained by the MicroBlaze maintainer — see [`sim-evidence/`](sim-evidence/),
which builds it and measures exit-status propagation. But it implements 107
instructions, so it cannot cover hard float, `mulh*`, `pcmp*` or `lwx/swx`,
and the last of those is emitted at *default* flags. System emulation is
still what covers the full ISA.

What actually blocks the standard mechanism is a linker bug: relaxation
mis-places `__wrap_*` symbols, so DejaGnu's own status wrapper never prints
its marker. See [`LIBGLOSS-BSP.md`](LIBGLOSS-BSP.md) and
[`../analysis/binutils-0013-relax-wrap-double-adjust.md`](../analysis/binutils-0013-relax-wrap-double-adjust.md).

The distinction that makes this work is **system** emulation rather than user
mode. User mode has to emulate the Linux syscall ABI; system mode needs a CPU
and a UART. `petalogix-s3adsp1800` is an upstream QEMU machine, and that is
the whole dependency.

## What it needs

- `qemu-system-microblaze` and/or `qemu-system-microblazeel`, **stock
  upstream** — no fork, no patches. Verified against upstream QEMU.
- A MicroBlaze cross compiler with newlib. `microblaze-elf` is the natural
  one; `build-support.sh` probes the C library rather than assuming, so an
  RTEMS toolchain works too (see below).
- DejaGnu (tested with 1.6.3).

No GDB simulator needed, no RTEMS kernel, no board bring-up.

## Using it

```sh
# once per toolchain
cd mb-qemu-board && CC=microblaze-rtems7-gcc ./build-support.sh

# then, from wherever you run runtest
cp ../site.exp.example ./site.exp     # and edit the paths in it
export MB_QEMU=/path/to/qemu-system-microblaze
runtest --tool gcc --target_board=mb-qemu \
        --srcdir /path/to/gcc/gcc/testsuite --objdir . execute.exp
```

For little-endian, point `MB_QEMU` at `qemu-system-microblazeel` and use
`--target_board=mb-qemu/-mlittle-endian`; the board picks the matching support
objects.

In a configured GCC build tree the usual form works too:

```sh
make check-gcc RUNTESTFLAGS="--target_board=mb-qemu execute.exp"
```

## What is in here

| | |
|---|---|
| `mb-qemu.exp` | the board description |
| `mb-qemu-run` | runs QEMU and converts the guest's status into an exit code |
| `mb-qemu-crt0.S` | startup: stack, `.bss`, init array, `main`, `exit` |
| `mb-qemu-newlib.c` | the glue newlib needs on bare metal |
| `mb-qemu.ld` | 64 MB at `0x90000000`, 4 MB stack |
| `build-support.sh` | builds the two objects the board links in |
| `site.exp.example` | for testing an installed cross compiler |

## The three things that are easy to get wrong

Each of these produced a pile of convincing false failures before it was
found, so they are worth stating plainly.

**Do not compile the tests `-ffreestanding`.** It gives `main` no special
status, so GCC stops emitting the C99 implicit `return 0` on falling off the
end of it — which most execute tests do instead of calling `exit`. The return
register then holds the last computed value and the test looks like it failed
with a plausible-looking code. This was 13 false failures. The board compiles
hosted; only the runtime objects are built `-ffreestanding`.

**Give it a real stack.** At 256 KB, `pr28982b` and `memcpy-1` hang. 4 MB is
what `mb-qemu.ld` uses.

**QEMU cannot return a guest exit status.** The board sets
`needs_status_wrapper`, so GCC links DejaGnu's `testglue.c`, which wraps
`exit`/`_exit`/`abort`/`main` and writes `*** EXIT code N` through
`write(1, ...)`; `check_for_board_status` in DejaGnu's `remote.exp` parses it.
`mb-qemu-run` only has to stop QEMU once that line appears, because the real
`exit` spins on bare metal. Nothing is asked of the machine model but a UART —
which is why this works on stock upstream QEMU, where `petalogix-s3adsp1800`
has no shutdown device.

This is the standard protocol rather than a marker of our own, but it needs a
linker that does not mis-place `__wrap_*` symbols while relaxing.
`build-support.sh` probes for that and adds `--no-relax` when it finds it; the
fix is `../patches/binutils-relax/0001-*.patch`.

DejaGnu gets `dg-options` and `dg-require-effective-target` right for free,
which an ad-hoc runner does not; that was another ten false failures and a
batch of tests reported as failing when they should have been UNSUPPORTED.

One further trap, not of the board's making: run a testsuite that matches your
compiler. GCC master's testsuite against a GCC 12 compiler fails by
construction on tests added for post-12 fixes.

## Which newlib, and what the glue is for

Everything comes from `-lc`. `mb-qemu-newlib.c` adds only what a given newlib
leaves to the board, and `build-support.sh` **probes** for that by test-linking
and reading the undefined symbols, rather than assuming:

| | vanilla newlib (`microblaze-elf`) | RTEMS newlib |
|---|---|---|
| syscalls (`_write_r`, `_sbrk`, …) | board | board |
| `malloc` family | libc | board — RTEMS expects the kernel heap |
| `__getreent` | libc | board |
| `_Mutex_*` | not used | board — RTEMS stdio locks against them |

So on `microblaze-elf` the glue is just the syscall layer, which is the normal
amount for a bare-metal board.

Honest status: it is **developed and tested against an RTEMS 7 toolchain**
(`microblaze-rtems7-gcc` 12.4.1), because that is the MicroBlaze toolchain to
hand. The probe is written so a vanilla newlib needs less of the glue, not
more, but that path has not been exercised. If you are standing this up on
`microblaze-elf` and the probe guesses wrong, `build-support.sh` prints what it
decided.

The alternative considered and rejected was a hand-rolled libc: it costs about
35 tests to link failures and gets `printf-1` wrong. Using a real newlib means
the suite exercises a C library that actually ships.

### What other GCC testers use

The convention for `*-sim` boards is newlib plus **libgloss**, which supplies
the crt0 and syscall layer per board — `aarch64-sim.exp`, for instance, is
little more than `libgloss_link_flags`, `newlib_link_flags` and
`-specs=rdimon.specs`.

Whether libgloss has a MicroBlaze BSP is worth checking before adopting this
crt0: if it does, the board should use it and `mb-qemu-crt0.S` plus most of
`mb-qemu-newlib.c` can go. I could not confirm it either way from here —
sourceware's web git is behind Anubis and there is no newlib source on this
machine.

## Status

The board runs, compiles, links, executes and reports correct pass/fail from
real exit status. Spot-validated on `pr50865.c`, `arith-rand-ll.c`,
`printf-1.c`, `memcpy-1.c`, `pr28982b.c` (all pass) and `pr111151.c`
(correctly fails — a genuine GCC 12 constant-folding bug, fixed upstream after
12 and not backported).

Tracked in issue #36, along with posting a baseline to `gcc-testresults`.
