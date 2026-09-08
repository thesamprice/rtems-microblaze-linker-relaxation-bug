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
| **SUPERSEDED** | replaced by someone else's version of the same fix; kept under `superseded/` for the record |
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
| 0001 | libgcc signal-frame unwinder: trampoline anchor, kernel-sized ucontext | READY — corrects Ramin's upstream `4ef64ad1a`; fixes a live glibc bug; layout-independent, so it is unaffected by the kernel's front reserve (MERGE-AUDIT zones B/C, sigframe-test/FINDINGS.md) |
| ramin-0002 | libgcc `moddi3.S`: 64-bit signed modulo wrong for nearly every input since 2010, hangs on little-endian | READY — Ramin's, carried from OpenADK (`toolchain/gcc/patches/16.2.0/0010`), applies to gcc master; not yet on gcc-patches, **his to submit** |
| landed/ramin-0001 | Ramin's libgcc unwinder | **LANDED** — gcc master + releases/gcc-15 (`4ef64ad1a`, 2026-06); OpenADK carries it for 12.5/15.3/16.2 |
| 0002 | PC-relative `.eh_frame` encodings | READY (needs binutils 0009) |
| local-0001 | `microblaze.h` `TARGET_DEFAULT` + default cpu → hardware | **LOCAL** — a hardware-target toolchain default, not upstream (`patches/gcc/local-0001-...`, [hardware-build.md](hardware-build.md)) |

Note: the `ramin-*` patches are **not ours to submit**. `landed/ramin-0001` is
Ramin Moussavi's upstream unwinder commit, kept only as the thing to add to an
old toolchain (gcc 0001 is the correction on top of it); `ramin-0002` is his
moddi3 fix, carried here so a toolchain build picks it up until he sends it.

Third-party MicroBlaze gcc/gdb work that is **already upstream** (patchwork
still shows these as "new", but they are committed): Gopi's PR118280 atomics
(`7894c00982`, 2025-09-19, committed by Michael Eager), Gopi's PR103383
bswap16 length fix (`9e3e6ceb3b`, 2026-04-02), Gopi's native-Linux gdb support
(binutils-gdb `d62f64e17b3`, 2026-05-07), and Neal's cpu-version-check fix
(`strverscmp` is in `microblaze.cc`). Nothing to carry for any of them.

## glibc  → `libc-alpha`

`patches/glibc/`, one series in apply order. Until 2026-09-08 this was two
folders from two investigations (`glibc-longjmp-chk/patches/` and the
cancellation branch's `patches/glibc/`); they were merged, renumbered, and
the cancel-path overlap (MERGE-AUDIT zone D) resolved by dropping the
`syscall_cancel.S` hunk from the CFI patch. Old numbers in brackets.

| # | what | status |
|---|---|---|
| 0001 | `____longjmp_chk` via the generic version (the fortified-longjmp hang) | READY (sent to Neal 2026-09-01) |
| 0002 | libm tests: soft-float has no exceptions/rounding | READY (sent 2026-09-02; correct even for hard-float, the FPU has no fenv) |
| 0003 | `start.S`: pass `_dl_fini` so destructors run | READY (sent 2026-09-02) |
| 0004 | implement `getcontext`/`setcontext`/`swapcontext`/`makecontext` | READY |
| 0005 [cancel 0001] | fix `__syscall_cancel_arch` stack-arg offsets (aio_suspend) | READY (sent 2026-08-16) |
| 0006 [cancel 0002] | tail-call `__syscall_do_cancel` so `-fexceptions` cancellation unwinds | READY |
| 0007 [EH 0005] | CFI on the asm (configure-gated on binutils 0006) | READY — `syscall_cancel.S` hunk dropped, 0006 covers that frame |
| 0008 [EH 0006] | use the generic unwinder-based `backtrace()` | READY |
| 0009 [EH 0007] | terminate `ld.so`'s own `.eh_frame` | READY |

Apply in number order: 0003 and 0007 both touch `start.S`; 0005, 0006 and
(formerly) 0007 touch `syscall_cancel.S`; 0004 and 0008 touch the linux
`Makefile`.

## Linux kernel  → `LKML` / `linux-microblaze`

Nothing left to submit. **Ramin Moussavi's series** (2026-08-21) covers
everything our four kernel patches did, and it is **LANDED** in Michal Simek's
MicroBlaze tree (`git.monstr.eu/linux-2.6-microblaze.git` branch `next`,
committed 2026-09-01) and merged into linux-next on 2026-09-07
(`5172f7bae34d`). Not yet in a Linus release; expect it in the next merge
window. The series is kept under `patches/linux/landed/` (copies from OpenADK
`target/linux/patches/7.2/`) and our originals under `patches/linux/superseded/`.

| # | what | replaces | linux-next commit |
|---|---|---|---|
| 0002 | wire up `sigaltstack` (was `sys_ni_syscall`) | — | `730e01d93249` |
| 0003 | 28-byte ABI argument-home gap at the front of `rt_sigframe` | our 0001 (32-byte `arg_save[8]`) | `c5947d28c209` |
| 0004 | `ret_from_trap_no_rval`: rt_sigreturn skips the r3/r4 stores | our 0004 (trampoline variant) | `da6829138a39` |
| 0005 | restore the pre-2011 `PTO` offset below `pt_regs` (GCC-15 boot death) | our 0003 (`C_ARG_SIZE` r1 lowering) | `c35d40a3efd2` |
| 0006 | preserve MSR carry across signals | our 0002 — same patch, authored by Sam Price | `ca35dd21a5f8` |

gcc 0001 anchors on the trampoline at the *end* of the frame, so the change
from a 32-byte to a 28-byte front gap does not affect it.

## RTEMS  → RTEMS

`patches/rtems/`.

| # | what | status |
|---|---|---|
| landed/0001 (FDT) | build without `BSP_MICROBLAZE_FPGA_USE_FDT` | **LANDED** — Sebastian Huber's identical fix, RTEMS `91401c423f`, 2026-08-17 |

The two linker-relaxation patches (disable `-Wl,--no-relax` in `abi.yml`, and
the matching re-enable) were **deleted on 2026-09-08**: the miscompile is fixed
in binutils master (0001/0002 landed 2026-08-13), so an RTEMS-side workaround
is the wrong fix. The proper change is in the **RTEMS Source Builder**:
`rtems/config/7/rtems-microblaze.bset` still pins
`tools/rtems-xilinx-binutils-2.36` (binutils 2.36 + ten meta-xilinx
rel-v2021.1 patches). Point it at a binutils that carries the upstream fix
(master after 2026-08-13; the RSB already has `rtems-binutils-head` and
`rtems-binutils-git-1` configs) and relaxation, and the `-O2` build, work
without any BSP change. Check the Xilinx-only patches (wdc.ext insns, address
extension, bit-field insns) against upstream first — most landed via Neal
Frager's 2023 binutils series.

## The overlaps to resolve first

Reconciliations, detailed in [MERGE-AUDIT.md](MERGE-AUDIT.md):

- **A. gas CFI** — resolved: kept binutils 0006, removed the branch's duplicate.
- **B/C. libgcc unwinder** — gcc 0001 (trampoline anchor) supersedes both Ramin's
  form (broken under glibc) and the earlier CFA form (broken by the kernel's
  front reserve, now Ramin's Linux 0003). It passes on both stock and reserve kernels; verified in
  [sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md).
- **D. cancellation path** — resolved 2026-09-08: the tail-call (now glibc 0006)
  handles the cancel frame and the `syscall_cancel.S` hunk was dropped from the
  CFI patch (now glibc 0007); the arg-offset fix (glibc 0005) precedes both.

## Build / apply order for a working toolchain

1. **binutils** master + `patches/binutils/000[3-9]` (+ 0010). Build gas/ld.
2. **gcc** on that binutils + `patches/gcc/0001`,`0002` (0002 needs binutils
   0009). Build with objdump on `PATH`.
3. **glibc** with that gcc + `patches/glibc/000[1-9]` in order.
4. **Linux** from linux-next (or a stable kernel plus `patches/linux/landed/`)
   for a board/qemu-system run; gcc 0001 is layout-independent, so it works
   with or without the signal-frame change (FINDINGS.md).

`harness/run.sh` automates 1-3; [hardware-build.md](hardware-build.md) adds the
hardware flag set.

## Sending: the numbering reviewers see

The file numbers under `patches/<repo>/` are this repo's bookkeeping (gaps
where things landed, `ramin-`/`local-` prefixes). Reviewers never see them.
`tools/make-outbox.sh` turns each still-open set into a mailing-list series:
it checks the upstream base out in a throwaway worktree, `git am`s the
patches in order (so each is verified to apply on top of the previous one),
and `git format-patch`es them back out with `[PATCH n/N]` subjects and a
`[PATCH 0/N]` cover letter filled from `patches/<repo>/0000-cover-letter.txt`.
The result is committed under `outbox/`:

| series | files | base it was generated on |
|---|---|---|
| `outbox/binutils/` | cover + 7 (repo 0003, 0004, 0006-0010) | binutils master `d715260f420` |
| `outbox/binutils-dwarf2/` | 1 (repo 0005, arch-neutral, own thread) | same |
| `outbox/gcc-0001/`, `outbox/gcc-0002/` | 1 each, no cover letter | gcc master `5792827ef` |
| `outbox/glibc/` | cover + 9 (repo 0001-0009) | glibc master `04e750e7` |

Send with `git send-email --to=<list> outbox/<series>/*.patch`; the cover
letter goes first and the rest thread under it. Regenerate after editing any
patch or cover letter. Kernel and RTEMS have nothing to send.

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
