# MicroBlaze toolchain patches: per-patch analysis

Reviewer-facing analysis for every patch in this repository. Each patch has its
own file following [`TEMPLATE.md`](TEMPLATE.md): what it does, whether upstream
already carries an equivalent fix, why the gap survived so long, the code a
reviewer should sanity-check, how other processors implement the same logic, and
how to verify the fix on real MicroBlaze hardware without the qemu/docker harness.

The patches span three trees. Base commits: binutils `6f24afa` (2026-08-31),
gcc the `microblaze-fixes` branch tip `95e1193`, glibc `10ed541` (2026-08-25).
Upstream was re-checked against binutils master `193340ad3` and gcc/glibc master
on 2026-09-04.

## Upstream audit summary

Two patches are already upstream and need no further action; the rest are
genuinely still open. gcc 0001 is special: it corrects a file that already
exists upstream.

| Patch | Upstream status |
|---|---|
| binutils 0001 (relaxation OOB miscompile) | **LANDED** upstream 2026-08-13; present in the base commit |
| binutils 0002 (discarded sections) | **LANDED** upstream 2026-08-13; present in the base commit |
| binutils 0003 (pr24511 xfail) | open (testsuite only; needs a `#noxfail` first) |
| binutils 0004 (`BFD_RELOC_8`/`16`) | open (`md_apply_fix` still has no 8/16 case) |
| binutils 0005 (addr2line determinism) | open (arch-neutral; not submitted) |
| binutils 0006 (gas CFI) | open |
| binutils 0007 (`.eh_frame` static reloc) | open |
| binutils 0008 (canonical PLT) | open (master still zeroes `st_value`) |
| binutils 0009 (PC-relative relocs) | open |
| gcc 0001 (signal-frame unwinder) | **corrects an existing upstream file** that is only right for uClibc, not glibc |
| gcc 0002 (PC-relative EH encodings) | open (master still `DW_EH_PE_aligned`) |
| glibc 0001-0007 | all open; the MicroBlaze port has never had its testsuite run |

The headline: **the linker-relaxation miscompile that this repository was opened
to track (binutils 0001) is fixed in binutils master.** So is the discarded-section
bug (0002). The remaining work is the exception-handling and glibc-runtime series.

## binutils

| Patch | Summary | Doc |
|---|---|---|
| 0001 | relaxation: don't index the locals-only symbol cache with a global symbol index (silent -O2 miscompile) | [relax-symbol-oob](binutils-0001-relax-symbol-oob.md) |
| 0002 | neutralise relocations against discarded linkonce sections | [discarded-sections](binutils-0002-discarded-sections.md) |
| 0003 | widen the pr24511 testsuite xfail to all MicroBlaze targets | [pr24511-xfail](binutils-0003-pr24511-xfail.md) |
| 0004 | write the value for `BFD_RELOC_8` / `BFD_RELOC_16` fixups | [reloc-8-16](binutils-0004-reloc-8-16.md) |
| 0005 | `addr2line` determinism: tie-break by DIE offset, not heap pointer | [dwarf2-tiebreak](binutils-0005-dwarf2-tiebreak.md) |
| 0006 | gas: accept `.cfi_*` directives for MicroBlaze | [gas-cfi-directives](binutils-0006-gas-cfi-directives.md) |
| 0007 | bfd: apply the relocation statically when the `.eh_frame` editor deletes it | [eh-frame-static-reloc](binutils-0007-eh-frame-static-reloc.md) |
| 0008 | bfd: keep the PLT address of address-taken functions (canonical PLT) | [canonical-plt](binutils-0008-canonical-plt-pointer-equality.md) |
| 0009 | gas + bfd: `sym - .` across sections, `R_MICROBLAZE_32_PCREL` | [pcrel-data-relocs](binutils-0009-pcrel-data-relocs.md) |

## gcc

| Patch | Summary | Doc |
|---|---|---|
| 0001 | libgcc: fix the MicroBlaze signal-frame unwinder for glibc's `ucontext_t` layout | [signal-frame-glibc-layout](gcc-0001-signal-frame-glibc-layout.md) |
| 0002 | PC-relative `.eh_frame` encodings instead of `DW_EH_PE_aligned` | [pcrel-eh-encodings](gcc-0002-pcrel-eh-encodings.md) |

## glibc

| Patch | Summary | Doc |
|---|---|---|
| 0001 | `____longjmp_chk`: use the generic version (the stub hung every fortified longjmp) | [longjmp-chk-stub](glibc-0001-longjmp-chk-stub.md) |
| 0002 | libm tests: tell the harness soft-float has no exceptions/rounding | [libm-tests-nofpu](glibc-0002-libm-tests-nofpu.md) |
| 0003 | `start.S`: pass `_dl_fini` so destructors run in dynamic programs | [pass-dl-fini](glibc-0003-pass-dl-fini.md) |
| 0004 | implement `getcontext`/`setcontext`/`swapcontext`/`makecontext` | [ucontext](glibc-0004-ucontext.md) |
| 0005 | CFI on the hand-written assembly (configure-gated) | [asm-cfi](glibc-0005-asm-cfi.md) |
| 0006 | use the generic unwinder-based `backtrace()` | [generic-backtrace](glibc-0006-generic-backtrace.md) |
| 0007 | terminate `ld.so`'s own `.eh_frame` | [ldso-eh-frame](glibc-0007-ldso-eh-frame.md) |

## Running on real hardware

See [HARDWARE-TESTING.md](HARDWARE-TESTING.md): how to build the patched
binutils, gcc and glibc natively on a Linux host and exercise each fix on a
MicroBlaze board, without the qemu-user / Docker test harness used during
development. [TEST-PLAN.md](TEST-PLAN.md) is the checklist version: which
suites to run in which order, the exact `make check` targets, and a sample
DejaGnu board file and glibc test-wrapper for driving the tests onto real
hardware.
