# How the MicroBlaze patches are organized

This repository accumulated fixes from two investigations that overlap:

- **the linker-relaxation / exception-handling / glibc-runtime work** (the
  original relaxation bug, then the EH tables and glibc port gaps), and
- **the cancellation-hang investigation** (Sam with Neal Frager, Ramin Moussavi,
  Romain Naour): the read()-cancel hangs traced to kernel, gcc/libgcc and glibc
  bugs.

They touch five upstreams — **binutils, gcc, glibc, Linux, RTEMS** — so the
patches are grouped by the tree they apply to, not by which investigation found
them. This file is the map: where each patch goes, its status, and what depends
on what.

## Status legend

| mark | meaning |
|---|---|
| **LANDED** | merged upstream; kept only for the record |
| **READY** | applies to current upstream, tested, submit as-is |
| **RECONCILE** | overlaps another patch; resolve before submitting (see MERGE-AUDIT.md) |
| **LOCAL** | a build/BSP configuration change, not for upstream |
| **HW-DECISION** | correct only for a specific hardware/kernel; the target decides |

## binutils  → `binutils@sourceware.org`

`patches/binutils/` (landed ones under `landed/`). Apply order 0003-0010; the
still-open series is verified clean on master `193340ad3`
([REWORK.md](REWORK.md)), and the MicroBlaze gas/ld/binutils suites pass with it
(ld and binutils clean, gas clean of MicroBlaze-attributable failures).

| # | what | status |
|---|---|---|
| 0001 | relaxation: locals-cache OOB miscompile | **LANDED** 2026-08-13 (`landed/`) |
| 0002 | neutralise relocations against discarded sections | **LANDED** 2026-08-13 (`landed/`) |
| 0003 | widen the pr24511 xfail to all MicroBlaze | READY (needs a `#noxfail` first) |
| 0004 | write the value for `BFD_RELOC_8`/`16` | READY |
| 0005 | `addr2line` DIE-offset tie-break (arch-neutral) | READY (send separately) |
| 0006 | gas `.cfi_*` directives | READY (superseded the merge branch's CFI patch, MERGE-AUDIT zone A) |
| 0007 | apply the relocation the `.eh_frame` editor keeps | READY |
| 0008 | canonical PLT / pointer equality | READY |
| 0009 | `sym - .` across sections, `R_MICROBLAZE_32_PCREL` | READY (gcc 0002 depends on it) |
| 0010 | exclude `microblazeel-*` from the gas diff1 test | READY (testsuite only) |

## gcc  → `gcc-patches`

`patches/gcc/`.

| # | what | status |
|---|---|---|
| 0001 | libgcc signal-frame unwinder: trampoline anchor, kernel-sized ucontext | **RECONCILE** — corrects Ramin's upstream `4ef64ad1a`; fixes a live glibc bug; interacts with Linux 0001 (MERGE-AUDIT zones B/C, sigframe-test/FINDINGS.md) |
| 0002 | PC-relative `.eh_frame` encodings | READY (needs binutils 0009) |
| (local) | `microblaze.h` `TARGET_DEFAULT` + default cpu → hardware | **LOCAL** — a hardware-target toolchain default, not upstream ([hardware-build.md](hardware-build.md)) |

Note: `patches/linux/ramin-0001-libgcc-...` is **not ours to submit** — it is
Ramin Moussavi's upstream commit (gcc 15.3/16.2), carried only as the thing to
add to an old toolchain. gcc 0001 is the correction on top of it.

## glibc  → `libc-alpha`

Two sets that overlap on the cancellation path — reconcile before submitting.

`glibc-longjmp-chk/patches/` (EH/runtime, this repo's main glibc work):

| # | what | status |
|---|---|---|
| 0001 | `____longjmp_chk` via the generic version (the fortified-longjmp hang) | READY |
| 0002 | libm tests: soft-float has no exceptions/rounding | READY (correct even for hard-float; the FPU has no fenv) |
| 0003 | `start.S`: pass `_dl_fini` so destructors run | READY |
| 0004 | implement `getcontext`/`setcontext`/`swapcontext`/`makecontext` | READY |
| 0005 | CFI on the asm (configure-gated) | **RECONCILE** — drop the `syscall_cancel.S` hunk if the tail-call (glibc-branch 0002) wins; keep the rest (MERGE-AUDIT zone D) |
| 0006 | use the generic unwinder-based `backtrace()` | READY |
| 0007 | terminate `ld.so`'s own `.eh_frame` | READY |

`patches/glibc/` (cancellation branch):

| # | what | status |
|---|---|---|
| 0001 | fix `__syscall_cancel_arch` stack-arg offsets (aio_suspend) | READY (real bug, edits the same file as 0005) |
| 0002 | tail-call `__syscall_do_cancel` so `-fexceptions` cancellation unwinds | **RECONCILE** — supersedes 0005's cancel-path CFI hunk |

## Linux kernel  → `LKML` / `linux-microblaze`

`patches/linux/`.

| # | what | status |
|---|---|---|
| 0001 | reserve the ABI arg-save area in the **signal** frame (siginfo clobber) | **HW-DECISION** — changes the signal-frame layout gcc 0001 anchors to (MERGE-AUDIT zone C) |
| 0002 | preserve MSR carry across signals | READY |
| 0003 | reserve the ABI arg-save area in **entry.S** (GCC-15 boot death) | READY |
| 0004 | `ret_from_trap`: don't clobber r4 on rt_sigreturn | READY — this is Ramin's LKML fix (`Fixes: 791d0a169b91`) |

## RTEMS  → RTEMS

`patches/rtems/`.

| # | what | status |
|---|---|---|
| 0001 | disable linker relaxation (the `-Wl,--no-relax` workaround) | applied workaround for the pre-fix toolchain |
| 0002 | re-enable linker relaxation | **HW-DECISION** — apply only once the RTEMS toolchain carries binutils 0001, else the miscompile returns |
| 0001 (FDT) | build without `BSP_MICROBLAZE_FPGA_USE_FDT` | independent BSP fix |

Housekeeping: `patches/rtems/` has two files named `0001-*` (the disable-relax
and the FDT fix). Renumber one when tidying.

## The overlaps to resolve first

Reconciliations, detailed in [MERGE-AUDIT.md](MERGE-AUDIT.md):

- **A. gas CFI** — resolved: kept binutils 0006, removed the branch's duplicate.
- **B/C. libgcc unwinder** — gcc 0001 (trampoline anchor) supersedes both Ramin's
  form (broken under glibc) and the earlier CFA form (broken by Linux 0001's
  reserve). It passes on both stock and reserve kernels; verified in
  [sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md).
- **D. cancellation path** — adopt the tail-call (glibc-branch 0002) and drop the
  `syscall_cancel.S` hunk of glibc EH 0005; keep the rest of its CFI. Both need
  glibc-branch 0001 (the arg-offset fix), which edits the same file.

## Build / apply order for a working toolchain

1. **binutils** master + `patches/binutils/000[3-9]` (+ 0010). Build gas/ld.
2. **gcc** on that binutils + `patches/gcc/0001`,`0002` (0002 needs binutils
   0009). Build with objdump on `PATH`.
3. **glibc** with that gcc + `glibc-longjmp-chk/patches/000[1-7]` (and the
   cancellation set after the zone-D reconciliation).
4. **Linux** with `patches/linux/` for a board/qemu-system run; gcc 0001 must
   match whether Linux 0001 is in (FINDINGS.md).

`harness/run.sh` automates 1-3; [hardware-build.md](hardware-build.md) adds the
hardware flag set.

## The synthesis docs

| doc | what it is for |
|---|---|
| [README.md](README.md) | per-patch analysis index + upstream audit summary |
| [REWORK.md](REWORK.md) | re-check against current upstream; what's landed vs open |
| [MERGE-AUDIT.md](MERGE-AUDIT.md) | reconciling the two investigations (the overlaps) |
| [sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md) | the libgcc unwinder finding, tested on qemu-system |
| [glibc-vs-uclibc.md](glibc-vs-uclibc.md) | why the C library matters; RTEMS/FreeRTOS use Newlib |
| [hardware-build.md](hardware-build.md) | hardware-accelerated build; the toolchain-default patch |
| [TEST-PLAN.md](TEST-PLAN.md) / [HARDWARE-TESTING.md](HARDWARE-TESTING.md) | how to run the suites on real hardware |
| [audit-ground-truth.md](audit-ground-truth.md) | the raw file:line upstream checks |
