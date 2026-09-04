# Running the patch series on real MicroBlaze hardware

The development harness (`../harness/`) builds the three trees and runs glibc's
`make check` under `qemu-microblazeel` in Docker, because that is what was
available. On a Linux host with a real `microblazeel-linux-gnu` board you do not
need any of that: build the cross-toolchain natively and run the tests on the
board. This guide covers the build and the per-fix smoke tests that do not
depend on the full testsuite.

## 1. Build the patched toolchain

The order is binutils, then gcc, then glibc, each built against the previous.
The harness script `../harness/run.sh` already encodes the exact configure lines
and the ordering fixes; on a Linux host you can run it without qemu, or run the
same steps by hand. The pieces that matter regardless of host:

- **binutils** with `patches/binutils/0006`..`0009` (and `0001`..`0004` for the
  relaxation and reloc fixes). Configure `--target=microblazeel-linux-gnu`.
- **gcc** with `patches/gcc/0001`..`0002`, built with the patched `as`/`ld` on
  `PATH`. objdump must be on `PATH` at configure time or gcc will not enable
  read-only exception tables (`HAVE_LD_RO_RW_SECTION_MIXING`), and the
  `.eh_frame` improvement from `patches/gcc/0002` will not show.
- **glibc** with the seven `glibc-longjmp-chk/patches/`, compiled by that gcc.
  Point glibc's configure `CC` at the new gcc so it picks up the new
  `libgcc_s`, crt files and `objcopy`/`readelf`.

A native Linux host removes two workarounds the harness needed and that do NOT
apply to you: the `qemu-wrap.sh` argv[0] shim (a Rosetta artifact) and the
`--init` orphan-reaper. Ignore both.

## 2. Run glibc's testsuite on the target

glibc's `make check` runs each test through `$(test-wrapper)`. On real hardware
set the wrapper to run the binary on the board rather than under qemu — for
example an ssh wrapper that copies the test and its libraries to the target and
executes them, or run natively on the board if it has enough storage. The result
format matches `../glibc-longjmp-chk/evidence/full-check-results-*.txt`, so a
board run diffs cleanly against the qemu runs recorded there. The
emulation-speed timeouts and the qemu-user gaps documented in
`../glibc-longjmp-chk/README.md` will not occur on hardware, so expect the
timeout and audit/PI-futex buckets to clear.

## 3. Per-fix smoke tests

Each patch's analysis file has a "How to verify on real hardware" section with a
minimal reproducer. The highest-signal ones, all runnable as ordinary programs
on the board:

- **glibc 0001 (fortified longjmp):** a `-D_FORTIFY_SOURCE=2` program that
  `longjmp`s out of a signal handler returns instead of hanging. Native `gdb`
  on the board no longer loops on its own error handling (the original report).
- **glibc 0003 (destructors):** a dynamically linked program with a
  `__attribute__((destructor))` prints its destructor message at exit.
- **glibc 0004 (ucontext):** a `makecontext`/`swapcontext` program switches
  contexts instead of failing with `ENOSYS`.
- **glibc 0005 (cancellation unwinding):** a thread cancelled while blocked runs
  its `pthread_cleanup_push` handler and the process neither aborts nor hangs.
- **gcc 0002 + binutils 0006/0007/0009 (exception tables):** compile a
  `-fexceptions` PIC object, link a shared object, and confirm with `readelf`
  that `.eh_frame` is read-only (`readelf -S`, flags `A` not `WA`), has an
  `.eh_frame_hdr` search table (`readelf -l` shows `GNU_EH_FRAME`), and carries
  no `R_MICROBLAZE_REL` in `.eh_frame` (`readelf -r`). Then run a C++
  `throw`/`catch` across that DSO on the board.
- **binutils 0008 (canonical PLT):** a non-PIC program where
  `&strlen == dlsym(RTLD_DEFAULT, "strlen")` now holds.
- **binutils 0001 (relaxation miscompile):** the original RTEMS signature, or
  any `-O2 -ffunction-sections --gc-sections` link whose `R_MICROBLAZE_64`
  relocation with a non-zero addend now resolves to the right address. See
  `../ANALYSIS.md`.

## 4. What hardware confirms that qemu could not

Three things the qemu runs could only partially show and that a board settles:

1. The **signal-frame unwinder** (gcc 0001) against the real kernel sigframe,
   not qemu's trampoline page.
2. The **timeout and futex** buckets: PI/robust futexes, `pthread` timeouts and
   the audit tests that hang under qemu-user should pass on hardware.
3. The **exception-table** path end to end: a real C++ program throwing through
   a shared library, using the new `.eh_frame_hdr` binary search rather than the
   linear FDE walk.
