# Running the GCC testsuite on MicroBlaze under QEMU

A DejaGnu board that gives MicroBlaze **execution** testing, not just
compilation testing.

This exists because of a remark on gcc-patches: MicroBlaze has no GDB
simulator, which is what GCC testing normally uses, and an attempt at QEMU
**user-mode** testing "failed miserably" — so MicroBlaze gets compile-only
coverage and no validation that the binaries actually work.

The distinction that makes this work is **system** emulation rather than user
mode. User mode has to emulate the Linux syscall ABI; system mode needs a CPU
and a UART. `petalogix-s3adsp1800` is an upstream QEMU machine, and that is
the whole dependency.

## What it needs

- `qemu-system-microblaze` and/or `qemu-system-microblazeel`, **stock
  upstream** — no fork, no patches. Verified against upstream QEMU.
- A MicroBlaze cross compiler with newlib. Developed against an RTEMS 7
  toolchain (`microblaze-rtems7-gcc` 12.4.1); nothing here is RTEMS specific
  beyond that being the newlib it was tested with.
- DejaGnu (tested with 1.6.3).

No GDB simulator, no RTEMS kernel, no board bring-up.

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

**QEMU cannot return a guest exit status.** `exit()` prints `*** EXIT n ***`
and `mb-qemu-run` reads it, then stops QEMU from outside. Nothing is asked of
the machine model but a UART — which is why this works on stock upstream QEMU,
where `petalogix-s3adsp1800` has no shutdown device.

DejaGnu gets `dg-options` and `dg-require-effective-target` right for free,
which an ad-hoc runner does not; that was another ten false failures and a
batch of tests reported as failing when they should have been UNSUPPORTED.

One further trap, not of the board's making: run a testsuite that matches your
compiler. GCC master's testsuite against a GCC 12 compiler fails by
construction on tests added for post-12 fixes.

## Why newlib rather than a minimal libc

`mb-qemu-newlib.c` supplies the three things RTEMS's newlib expects RTEMS to
provide and bare metal does not: the reentrancy pointer (`__getreent`), the
mutex primitives its stdio locks against, and `malloc`. Everything else comes
from `-lc`.

The alternative was a hand-rolled libc, which costs about 35 tests to link
failures and gets `printf-1` wrong. Using the real newlib means the suite
exercises the C library that actually ships.

## Status

The board runs, compiles, links, executes and reports correct pass/fail from
real exit status. Spot-validated on `pr50865.c`, `arith-rand-ll.c`,
`printf-1.c`, `memcpy-1.c`, `pr28982b.c` (all pass) and `pr111151.c`
(correctly fails — a genuine GCC 12 constant-folding bug, fixed upstream after
12 and not backported).

Tracked in issue #36, along with posting a baseline to `gcc-testresults`.
