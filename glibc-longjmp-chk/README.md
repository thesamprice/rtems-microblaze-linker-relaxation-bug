# glibc MicroBlaze: `____longjmp_chk` is a stub, so every fortified `longjmp` hangs

Reported by Gopi (native MicroBlaze gdb spins forever when handling errors) and
traced by him to `sysdeps/unix/sysv/linux/microblaze/____longjmp_chk.S`. This
directory holds the confirmation, the mechanism, a reproducer, a fix, and the
test results. It is a glibc bug, unrelated to the binutils relaxation bug the
rest of this repository is about.

## Summary

`____longjmp_chk` is the machine-dependent half of `__longjmp_chk`, which is
what `longjmp`/`siglongjmp` resolve to when a program is compiled with
`_FORTIFY_SOURCE`. On MicroBlaze it has been this since the port landed in 2012
(commit 7756ba9d6d, "MicroBlaze Port", David Holsgrove), unchanged apart from
copyright bumps, and it is identical in the Xilinx/glibc fork:

```asm
ENTRY (__revisit_longjmp_chk)
	rtsd	r15,0
	nop
PSEUDO_END (__revisit_longjmp_chk)
ENTRY (____longjmp_chk)
	rtsd	r15,0
	nop
PSEUDO_END (____longjmp_chk)
```

It never restores the jump buffer. Worse, `rtsd r15,0` returns to the address of
the call instruction itself rather than past its delay slot (`rtsd r15,8` is the
normal MicroBlaze return), so `__longjmp_chk` calls the stub, the stub returns to
the call, and the two instructions ping-pong forever. No crash, no message, 100%
CPU.

Any program built with `-D_FORTIFY_SOURCE=1` or `2` that calls `longjmp` or
`siglongjmp` hangs at the first jump. gdb is such a program: it defines
`_FORTIFY_SOURCE=2` for itself in `gdbsupport/common-defs.h`, and it uses
`longjmp` to get out of readline's callback when a command throws
(`gdb/event-top.c`, `gdb_rl_callback_handler` → `throw_exception_sjlj` →
`longjmp` in `gdbsupport/common-exceptions.cc`). So the first error a native gdb
handles is the last thing it does.

## Evidence

Everything below was produced on 2026-09-01 in an amd64 Debian 12 container
(Docker on an Apple Silicon Mac) with the Bootlin
`microblazeel--glibc--stable-2025.08-1` toolchain (gcc 14.3.0, binutils 2.43.1,
glibc 2.41) and Debian's `qemu-microblazeel` 7.2.

**The shipped binary has the stub.** `evidence/shipped-glibc-2.41-disasm.txt`
is `objdump -d` of the sysroot's `libc.so.6`:

```
0017852c <____longjmp_chk>:
  17852c:	b60f0000 	rtsd	r15, 0
  178530:	80000000 	or	r0, r0, r0
```

and the caller in `__longjmp_chk` (compiled from `debug/longjmp_chk.c`, which is
just `setjmp/longjmp.c` with `__longjmp` renamed to `____longjmp_chk`):

```
  17a6c8:	e874f100 	lwi	r3, r20, -3840     # GOT slot of ____longjmp_chk
  17a6cc:	99fc1800 	brald	r15, r3            # r15 = 0x17a6cc
  17a6d0:	10b60000 	addk	r5, r22, r0        # delay slot: env
```

`rtsd r15,0` jumps to `r15 + 0 = 0x17a6cc`, the `brald` itself.

**It hangs.** `evidence/repro.c` is a plain `setjmp`/`longjmp`. Built with
`-O2 -D_FORTIFY_SOURCE=2` and run under `qemu-microblazeel` it prints
`calling longjmp` and never returns (killed by `timeout` after 15 s). Built with
`-U_FORTIFY_SOURCE` it prints `OK: setjmp returned nonzero after longjmp`.
`evidence/qemu-in_asm-tail.txt` is the tail of a `-d in_asm` trace: the last
translated blocks alternate between the `brald` and the `rtsd`, forever.

**glibc's own tests catch it.** `debug/tst-longjmp_chk`, `tst-longjmp_chk2`
and `tst-longjmp_chk3` are built with `-D_FORTIFY_SOURCE=1` and are the only
tests in a default build that link `__longjmp_chk`. On an unpatched cross build
of glibc master (10ed541ad1, 2026-08-25) run under qemu-user, all three time
out:

```
tst-longjmp_chk:  FAIL: debug/tst-longjmp_chk original exit status 1
    Timed out: killed the child process
tst-longjmp_chk2: FAIL: debug/tst-longjmp_chk2 original exit status 1
    not on alternate stack
     in signal handler
     on alternate stack
    Timed out: killed the child process
tst-longjmp_chk3: FAIL: debug/tst-longjmp_chk3 original exit status 1
    Timed out: killed the child process
```

Nobody has ever run them on this target. glibc's CI for MicroBlaze is
`build-many-glibcs.py`, which only compiles, and the stub predates the
MicroBlaze port's move out of `ports/`.

## Fix

`patches/0001-microblaze-Implement-____longjmp_chk-using-the-gener.patch`,
against glibc master. It deletes the stub and adds
`sysdeps/microblaze/jmpbuf-offsets.h`:

```c
#include <jmpbuf-unwind.h>

/* Helper for generic ____longjmp_chk().  */
#define JB_FRAME_ADDRESS(buf) ((void *) _jmpbuf_sp (buf))
```

With `JB_FRAME_ADDRESS` defined and no arch-specific file in the way, the
sysdeps search picks up the generic `sysdeps/unix/sysv/linux/____longjmp_chk.c`,
exactly as riscv, loongarch, or1k and arc do. That version compares the saved
frame address with the current one, falls back to a `sigaltstack` query when
jumping "up" the stack, and calls `__fortify_fail` otherwise.
`sysdeps/microblaze/jmpbuf-unwind.h` already provides `_jmpbuf_sp`, and
MicroBlaze already has `_STACK_GROWS_DOWN` and `INTERNAL_SYSCALL_CALL`, so
nothing else is needed. `evidence/patched-master-disasm.txt` shows the
generated code: frame compare, `sigaltstack` (`brki r14,8` with r12 = 186),
and the `__fortify_fail` call.

With the patch, same build, same qemu (`evidence/patched-master-test-results.txt`):

```
tst-longjmp_chk:  PASS
tst-longjmp_chk2: PASS   (all three stack cases, including sigaltstack)
tst-longjmp_chk3: PASS   (the bad jump aborts as it should)
```

An alternative would be a hand-written `.S` with `CHECK_SP` like arm or csky.
There is no reason to: the generic C version is what the newer ports use and it
is easier to keep correct.

## Wider test runs

**Fortify-enabled build.** A second build of the patched tree configured with
`--enable-fortify-source=2`, which is how distributions and Buildroot build
glibc and which routes every test's own `longjmp` through the checked path.
`setjmp/` and `debug/` run under qemu-user
(`evidence/fortify-build-test-results.txt`):

| Directory | PASS | FAIL |
|---|---|---|
| `setjmp/` | 12 | 0 |
| `debug/` | 27 | 27 |

Every `setjmp/` test passes, including `bug269-setjmp` and `tst-sigsetjmp`.
The three `tst-longjmp_chk` tests pass again. `debug/tst-fortify` deserves a
note: its `CHK_FAIL_START`/`CHK_FAIL_END` harness catches each expected
`__chk_fail` abort with `sigsetjmp` and a `SIGABRT` handler that `longjmp`s
back, so with fortify on it exercises `__longjmp_chk` from a signal handler
hundreds of times per run. On the unpatched library it would hang at the first
check. Patched, all 18 fortified `_GNU_SOURCE` variants (C and C++, levels 1 to 3,
default, LFS and time64) get through every check and stop at the same place,
line 1722, which is `ptsname_r` on a `posix_openpt` descriptor that qemu-user
does not emulate. The fortify-level-0 variant fails at the same line, and the
12 `nongnu` variants, which skip that block, all pass. So it is not the patch.

The other 8 `debug/` failures are pre-existing or environmental:
`tst-backtrace2` through `6` (MicroBlaze `backtrace` does not walk through
signal frames), `tst-fortify-syslog` (needs the container harness, which cannot
`unshare` here), and `tst-sprintf-fortify-rdonly` and its static twin (qemu-user
runs out of file descriptors).

**Full `make check` on the patched default build.** A first attempt showed
that 933 libm tests abort on the same assertion in `math/libm-test-support.c`:
MicroBlaze is soft-float on the generic `bits/fenv.h`, which defines no `FE_*`
exception macros, and nothing told the test harness, so `test_exceptions`
found no exception class to test and tripped `assert (ran == 1)` before
evaluating anything. Every other soft-float-only port (arc, riscv, loongarch,
or1k) carries a `nofpu/math-tests-exceptions.h` and `math-tests-rounding.h`
for exactly this. `patches/0002-microblaze-libm-tests-nofpu.patch` adds the
MicroBlaze pair. That run was discarded and the full check restarted with both
patches applied (`evidence/full-check-results.txt`, every failure with its
exit status and first line of output). Patch 0003 came out of this run and is
not in it.

| | Count |
|---|---|
| PASS | 4619 |
| FAIL | 588 |
| UNSUPPORTED | 161 |
| XFAIL | 4 |
| total | 5372 |

`math/` is 1162 PASS, 0 FAIL. `setjmp/` and `debug/tst-longjmp_chk*` pass.
The 588 failures by cause:

| Count | Cause |
|---|---|
| 191 | destructors never run, fixed by patch 0003: 111 mtrace `*-mem` leak reports, 72 `tst-dso-ordering`, 8 `elf/*-cmp` |
| 82 | timeouts: the 20 s test-driver limit under qemu on Rosetta, and `tst-printf-format`'s per-conversion watchdog on 309-digit doubles (552 of 576 of those pass) |
| 54 | tests that spawn a child or re-exec `ld.so`: under Rosetta every child loses argv[0] (see below) |
| 38 | hangs: every `LD_AUDIT` and profiling test never finishes under qemu-user, killed at the 10 min cap |
| 31 | container tests: `unshare()` not permitted inside Docker |
| 19 | `debug/tst-fortify*`: stop at `ptsname_r` on a `posix_openpt` fd, fortify level 0 too |
| 13 | `getcontext`/`setcontext`/`swapcontext`: MicroBlaze has only the generic ENOSYS stubs |
| 61 | other qemu-user gaps: pty, `getdents` EOVERFLOW, THP/hugetlb malloc knobs, PI/robust futexes, mqueue/aio, network, gprof on guest output, needs-root |
| 5 | `backtrace()` does not walk signal frames on MicroBlaze (pre-existing) |
| 35 | `nptl/`: `pthread_cancel` and `-fexceptions` cleanup tests (`tst-cancel*`, `tst-cancelx*`, `tst-cleanupx4`, `tst-once*`, `tst-tls3*`, `tst-rwlock*`) fail or abort. Not touched by these patches. Worth a real look: cancellation unwinding on MicroBlaze may be broken. |
| 59 | not yet looked at individually: 26 `elf/` (`circleload1`, `constload1`, `dblload`, `tst-tls-ie*`, `tst-thp-*`, `tst-unwind-main`, ...), 5 `string/` (`test-strncmp`, `test-strnlen`, ...), and a handful in `libio`, `misc`, `posix`, `stdlib`, `stdio-common`, `time` |

A second pass with patch 0003 in the tree would retire the first row and is
the obvious next run. The `nptl/` and `string/` rows are the ones that look
like they could be more MicroBlaze bugs.



## A third bug the suite exposed: destructors never run

Six `elf/` comparison tests (`tst-array1-cmp`, `tst-array2-cmp`,
`tst-array4-cmp`, `tst-initorder-cmp`, `tst-initorder2-cmp`, `order-cmp`) fail
because every "fini" line is missing from the program output, all 111
mtrace-based `*-mem` tests report leaked memory, and the 47 generated
`tst-dso-ordering` tests print "should not return here". One cause:
`sysdeps/microblaze/start.S` passes a null `rtld_fini` to
`__libc_start_main`, so `_dl_fini` is never registered with `atexit`. The
dynamic linker does hand it over, its `_dl_start_user` leaves `_dl_fini - 8`
in r15 before jumping to `_start`, but `_start` never looked. Since glibc 2.34
(commit 035c012e32, which stopped passing `__libc_csu_fini`) that means **no
destructor of any kind runs in a dynamically linked MicroBlaze program**:
`__attribute__ ((destructor))`, `.fini_array`, the `_fini` of every shared
object. Static programs are fine because `call_fini` handles them. Before
2.34 only shared-object destructors were lost.

`evidence/dtor.c` and `evidence/destructors-never-run.txt`: on the shipped
Bootlin glibc 2.41 the destructor runs in the static build and not in the
dynamic one.

`patches/0003-microblaze-pass-dl_fini-to-libc_start_main.patch` makes
`_start` use r15 when it is non-zero. The kernel's `ELF_PLAT_INIT` for
MicroBlaze zeroes every register at exec, and qemu-user does the same, so
zero r15 reliably means "started by the kernel, no rtld_fini". Verified
through glibc's own tests in the fortify tree with only `csu/` rebuilt:
`tst-array1-cmp` and `tst-initorder-cmp` go from FAIL to PASS,
`tst-array1-static-cmp` stays PASS, and the destructor test prints
"destructor ran" dynamically linked.

## Reproducing

`evidence/build.sh`, `evidence/tests.sh` and `evidence/check.sh` are the exact
scripts used, written for a Debian 12 amd64 container with the Bootlin toolchain
unpacked at `/work/tc`. Two things worth knowing before repeating this:

- **Build on a case-sensitive filesystem.** glibc writes `stamp.os` and
  `stamp.oS` side by side. A Docker bind mount from macOS is case-insensitive
  and the build fails late with a garbled `ar` object list. Build in the
  container's own filesystem.
- **qemu-user under Rosetta drops the guest's argv[0].** qemu reads the host
  auxv `AT_FLAGS` to decide whether binfmt_misc launched it with the
  preserve-argv0 flag, and Rosetta (which runs amd64 containers on Apple
  Silicon) sets that bit. Every guest program then sees argc one too small and
  no argv[0], which breaks glibc's test wrapper (`ld.so --library-path DIR
  prog` becomes `ld.so DIR prog`). `evidence/qemu-wrap.sh` compensates by
  passing the program path twice. This is an artifact of the host, not a
  MicroBlaze or glibc problem. On a Linux host it does not happen.

## Status

Patch 0001 sent to Neal Frager (AMD), Cc Gopi Kumar Bulusu, on 2026-09-01 via
`git send-email`, Message-Id `<20260902011602.48056-1-thesamprice@gmail.com>`,
with the patch inline; `reply-to-neal.mbox` is the message as sent. The test
results and all three patches went to Neal, Cc Sam, on 2026-09-02 as a reply
on that thread (`results-to-neal.txt` is the body). Nothing posted to
libc-alpha yet. Every commit carries `Assisted-by: Claude`, no co-author
trailer.

## Who needs to change

- **glibc**: apply the patch (or an equivalent). The commit message in the patch
  is written for libc-alpha.
- **AMD/Xilinx**: their glibc fork has the same stub, and every PetaLinux or
  Buildroot MicroBlaze rootfs built with fortify inherits the hang. Gopi has
  already reported it to AMD.
- **gdb**: nothing. gdb's use of `longjmp` is correct, and its default
  `_FORTIFY_SOURCE=2` is merely what exposes the glibc bug first. Any fortified
  program that longjmps (bash, vim, many others) hits the same wall.
