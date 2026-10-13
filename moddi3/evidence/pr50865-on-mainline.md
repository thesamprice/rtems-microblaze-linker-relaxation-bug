# pr50865.c on mainline, measured a second time

The cover letter's table says `pr50865.c` hangs big-endian without the fix and
passes with it. Those figures came from the RTEMS 12.4.1 toolchain and
`dejagnu/mb-qemu-board`, which carried its own BSP and a stub libc. This is the
same result from a different compiler, a different libgcc, a different C
library and a different board, which is worth having because the original
measurement had several things in common with itself.

## Setup

- gcc trunk **17.0.0 20260705**, built `--target=microblaze-elf --with-newlib
  --disable-multilib` in a combined tree with newlib and libgloss
- binutils-gdb **2.47.50.20260908** plus `patches/binutils-relax`
- newlib and libgloss from sourceware, unmodified
- `dejagnu/microblaze-qemu`, which takes crt0, linker script, libc and
  syscalls from the toolchain
- stock `qemu-system-microblaze`, `petalogix-s3adsp1800`

So: trunk's own `libgcc.a`, not a fork's and not RTEMS's.

## Result

`make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp=pr50865.c"`

```
PASS: gcc.c-torture/execute/pr50865.c   -O0  (test for excess errors)
FAIL: gcc.c-torture/execute/pr50865.c   -O0  execution test
PASS: ... -O1 ...                              FAIL: -O1  execution test
PASS: ... -O2 ...                              FAIL: -O2  execution test
PASS: ... -O3 -g ...                           FAIL: -O3 -g  execution test
PASS: ... -Os ...                              FAIL: -Os  execution test
PASS: ... -O2 -flto -fno-use-linker-plugin -flto-partition=none ...  FAIL
PASS: ... -O2 -flto -fuse-linker-plugin -fno-fat-lto-objects ...     FAIL

# of expected passes		7
# of unexpected failures	7
```

It compiles cleanly at all seven torture levels and fails execution at all
seven. The failure mode is a hang with no output whatsoever — not an abort, not
a wrong answer — which is the LLONG_MIN non-termination the first patch
describes.

Linking `moddi3/harness/moddi3-fixed.S` ahead of `libgcc.a`, everything else
identical:

| `__moddi3` | guest output |
|---|---|
| trunk's `libgcc.a` | *(nothing; killed on timeout)* |
| `moddi3-fixed.S` ahead of it | `*** EXIT code 0` |

## arith-rand-ll.c, the other test in that table

Same toolchain, same board:

| `__moddi3` | guest output |
|---|---|
| trunk's `libgcc.a` | `*** EXIT code 4242`, then `*** EXIT code 6` |
| `moddi3-fixed.S` ahead of it | `*** EXIT code 0` |

4242 is `testglue.c`'s code for `abort`. Two markers appear because
`__wrap_abort` writes one and does not set `done_exit_message`, so the
`__wrap__exit` it eventually reaches writes a second; `check_for_board_status`
regsubs greedily and takes the last, reporting 6. Either way it fails, and the
fix makes it pass.

So both entries in the cover letter's table reproduce on mainline, with the
same two failure modes it names — `pr50865.c` hangs, `arith-rand-ll.c` aborts.

## The rest of the set, for context

Eight tests, seven torture levels each, trunk's libgcc unmodified:

| test | execution |
|---|---|
| `20010221-1.c` | 8 PASS |
| `990208-1.c` | 7 PASS |
| `loop-2b.c` | 8 PASS |
| `memcpy-1.c` | 8 PASS |
| `printf-1.c` | 7 PASS |
| `arith-rand-ll.c` | **8 FAIL** |
| `pr50865.c` | **7 FAIL** |
| `pr28982b.c` | UNSUPPORTED |

53 compiles, none with excess errors. Every failure is `__moddi3`; nothing
else in the set fails. `pr28982b.c` being UNSUPPORTED is DejaGnu reading its
`dg-require-effective-target`, which an ad-hoc runner gets wrong — the earlier
hand-rolled harness reported it as a failure for want of stack.

## Why it is worth a line on the list

`pr50865.c` has been in GCC's testsuite since PR middle-end/50865 in 2011. It
fails on trunk MicroBlaze today, at every optimisation level, by hanging. The
reason nobody noticed is the one the DejaGnu work is about: MicroBlaze has had
no execution testing, so an in-tree test that catches this has been unable to
report it for fifteen years.

The marker in that table is DejaGnu's own `*** EXIT code N`, written by
`testglue.c` through libgloss's `write()` and parsed by
`check_for_board_status`. Getting that far needed
`patches/binutils-relax/0001`, without which the wrapper's `__wrap_exit`
resolves before its own first instruction and no test can report anything.
