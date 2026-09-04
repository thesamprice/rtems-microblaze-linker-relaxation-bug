# Signal-frame unwinder test (gcc patch 0001) on qemu-system

Validates `libgcc/config/microblaze/linux-unwind.h` — Ramin Moussavi's upstream
unwinder and gcc patch 0001's glibc correction on top of it — by checking that
`_Unwind_Backtrace` from a signal handler steps THROUGH the signal frame back
into the interrupted call chain.

## Why qemu-system, not the build harness

The build harness runs tests under **qemu-user** (`qemu-microblazeel`), which
emulates signal delivery itself: there is no guest kernel, so your
`patches/linux/` signal-frame patches have no effect and the frame layout is
qemu's, not the kernel's. It is not a faithful test of this patch. **qemu-system**
(`qemu-system-microblazeel -M petalogix-s3adsp1800`) boots a real kernel, runs the
real `setup_rt_frame`, and honours the kernel patches — the correct environment,
and the same one your `LINUX-CANCEL-HANG-CORRECTION.md` investigation used. A
physical board is not required.

## Files

- `sigunwind.c` — the test. A fault (default) or `SIGALRM` (`MODE=alrm`) is raised
  from `leaf()` inside `outer()->mid()->leaf()`; the handler runs
  `_Unwind_Backtrace` and prints `RESULT: PASS` iff `leaf`, `mid`, `outer` and
  `main` are all recovered in order past the signal frame.
- `build-test.sh` — cross-compiles it static (so it carries the patched libgcc).
- `run-qemu-system.sh` — wraps the test in a one-file initramfs, boots your
  kernel with it as init, and reports PASS/FAIL from the serial log.

## Build and run

```sh
# 1. build with the PATCHED toolchain (the one from harness/run.sh)
CC=microblazeel-linux-gnu-gcc analysis/sigframe-test/build-test.sh

# 2. boot it under your petalogix kernel
KERNEL=path/to/simpleImage.s3adsp1800 analysis/sigframe-test/run-qemu-system.sh
```

`RESULT: PASS` means the signal frame was unwound correctly for this kernel and C
library. `RESULT: FAIL` prints the captured frames and which markers were
missing, so you can see where the walk stopped.

## The two comparisons this is for

### A. Does the kernel arg-save reserve shift the offset?

gcc 0001 locates the sigcontext at `cfa + sizeof(siginfo_t) + 2*long +
sizeof(stack_t)`, assuming the handler's SP is `&siginfo`. `patches/linux/0001`
(reserve the ABI arg-save area in the signal frame) deliberately stops that from
being true. Boot the **same** test binary under both kernels:

| kernel | expectation |
|---|---|
| stock (no reserve) | PASS if gcc 0001's offset is right for the stock frame |
| + `patches/linux/0001` | if this FAILs while stock PASSes, the reserve shifts `&siginfo` and gcc 0001's offset must add the reserve size |

This is the interaction flagged in `../MERGE-AUDIT.md` zone C.

### B. Is gcc 0001 needed under glibc, or does Ramin's stock unwinder suffice?

Build the test twice: once with a stock gcc 15.3/16.x (Ramin's unwinder, the
`uc = pc - sizeof(ucontext_t)` form), once with the patched gcc (0001). Run both
under the same kernel and glibc:

| libgcc | expectation under glibc |
|---|---|
| stock (Ramin's) | if it FAILs, `sizeof(ucontext_t)` is wrong for glibc and 0001 is needed |
| + gcc 0001 | should PASS |

If Ramin's already PASSes under glibc in your image, 0001 may be moot for glibc
and can be dropped — settle it here.

## Notes

- **Fault vs SIGALRM.** The default fault mode puts the interrupted PC inside
  `leaf` itself, the stronger test. `MODE=alrm` raises `SIGALRM` instead; the
  interrupted PC then lands in `raise()` and `leaf` is its caller. Use `alrm` if
  your setup maps a zero page (qemu-user does, so the fault mode there reports
  "handler never ran"; on a real kernel the fault mode works).
- **Built-in initramfs.** If your kernel bakes in its own initramfs it may ignore
  `-initrd`; then bake `sigunwind` into your rootfs and run it there, and read the
  same `RESULT:` line off the console.
- **Smoke check.** Under qemu-user the `alrm` build already PASSes (the unwinder
  was developed there), but that does not exercise the kernel frame or the reserve
  patch — which is the whole reason to run it under qemu-system.
