# Post-merge audit: reconciling the two MicroBlaze investigations

The `main` branch now carries two lines of work that ran in parallel and overlap
in the exception-handling / cancellation / signal-frame area:

- **the cancellation-hang investigation** (Sam with Neal Frager, Ramin Moussavi,
  Romain Naour): `LINUX-CANCEL-HANG-CORRECTION.md`, `linux-cancel-hang/`,
  `patches/linux/`, `patches/glibc/`. It traces the glibc-testsuite cancellation
  hangs to six distinct bugs across the kernel, gcc/libgcc and glibc.
- **the exception-table / glibc-runtime work** (this session): `patches/binutils/`
  `0006`-`0009`, `patches/gcc/`, `glibc-longjmp-chk/`, `analysis/`.

This file is what an upstream reviewer would want after the merge: which patches
are the same fix, which supersede which, and which decisions can only be settled
on real hardware. It does not re-explain each patch — see the per-patch docs.

## The cancellation investigation is authoritative in its area

`LINUX-CANCEL-HANG-CORRECTION.md` is a measured, multi-party root-cause analysis
that supersedes this session's understanding of the cancellation hangs. Where
the two overlap, prefer its conclusions. This session's cancellation work was
developed under qemu-user without the kernel patches and reached the hangs from
the unwinder side only.

## Overlap zones

### A. gas CFI — RESOLVED

`patches/binutils/0005-microblaze-add-DWARF2-CFI` (from the cancellation branch,
2.5 KB, no test) and `0006-gas-microblaze-cfi-directives` (this session, 5.4 KB)
add the same feature. Kept 0006, deleted 0005: binutils review requires a
testsuite for new functionality (0006 ships `cfi.s/.d/.exp`), and 0006 also
defines `tc_regname_to_dw2regnum` so `.cfi_offset r15` works with register names,
not just numbers. That also clears the duplicate `0005-*` filename.

One thing to carry over: the deleted patch set `DWARF2_LINE_MIN_INSN_LENGTH 4`,
which 0006 does not. That is a `.debug_line` improvement (correct for MicroBlaze's
4-byte instructions), separate from CFI. Worth a small standalone patch rather
than folding it into the CFI one.

### B. libgcc signal-frame unwinder — a SEQUENCE, not a duplicate; needs hardware

Two files touch `libgcc/config/microblaze/linux-unwind.h`:

- `patches/linux/ramin-0001-libgcc-microblaze-signal-frame-unwinding.patch` is
  **Ramin Moussavi's upstream commit `4ef64ad1a`** (gcc 15.3 / 16.2). It *added*
  the unwinder. It is already in gcc master. Its buildroot GCC 15.3.0 lacked it,
  which is why the branch carries it — as the thing to add to an old toolchain,
  not a patch to submit.
- `patches/gcc/0001-libgcc-microblaze-signal-frame-glibc-layout.patch` (this
  session) is a **correction of that same upstream file**. Ramin's version locates
  the sigcontext with `uc = pc - sizeof (ucontext_t); sc = &uc->uc_mcontext` and
  comments "uClibc's ucontext_t matches the kernel's". glibc's `ucontext_t` is
  larger (128-byte `uc_sigmask` vs the kernel's 8), so that arithmetic is wrong
  under glibc; 0001 anchors at `context->cfa` instead.

So they are not competitors: ramin adds (upstream already), 0001 fixes for glibc.
Keep both, reframed that way. But two things a reviewer — and a board — must settle:

1. **Does Ramin's uClibc-form actually work under glibc in the cancellation
   branch's setup?** `LINUX-CANCEL-HANG-CORRECTION.md` reports it fixes the hangs
   there. If that testing was glibc, either the `sizeof(ucontext_t)` discrepancy
   did not bite the specific backtrace tested, or the kernel reserve (below)
   compensated. If it was uClibc, gcc 0001 is still needed for glibc. **Resolve on
   glibc hardware:** unwind out of a signal handler and check the recovered
   registers, not just that a backtrace produces frames.
2. **gcc 0001 interacts with kernel patch #1 (next zone).** Its offset
   `cfa + sizeof(siginfo_t) + 2*long + sizeof(stack_t)` assumes the handler's SP
   is `&siginfo`. Kernel patch #1 deliberately stops that being true.

### C. Kernel signal-frame reserve vs gcc 0001's anchor — DIRECT INTERACTION

`patches/linux/0001-microblaze-reserve-the-ABI-argument-save-area-in-the-signal`
fixes a real bug: because `struct rt_sigframe` puts `siginfo` first, the handler
runs with `r1 == &siginfo`, and a spilling handler (GCC 15's IRA) writes its
argument-save area over `si_code`, dropping the cancel. The fix reserves the
arg-save area **at the base of the signal frame**, so the handler's SP no longer
equals `&siginfo`.

That is exactly the anchor gcc 0001 uses. With the kernel patch applied,
`context->cfa` (the handler's SP) points at the reserved area, and `&siginfo` is
one arg-save-area higher, so gcc 0001's offset is short by that reserve.
**CONFIRMED under qemu-system** (Linux 6.12.9, petalogix-s3adsp1800): gcc 0001
passes on the stock kernel and FAILS on the kernel with patch #1, and adding
exactly the 32-byte reserve flips it (stock then fails). So no single
CFA-relative offset works for both; the anchor is kernel-layout-dependent. The
robust fix, now implemented in `patches/gcc/0001`, anchors from the trampoline
with a kernel-sized ucontext, immune to the front reserve: verified PASS on both
the stock and the reserve kernel. Full evidence in
[sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md).

### D. Cancellation path: asm CFI vs tail-call — pick one for the cancel frame

Both branches make `-fexceptions` cancellation unwind through
`sysdeps/unix/sysv/linux/microblaze/syscall_cancel.S`, differently:

- **This session** (`glibc-longjmp-chk/patches/0005-microblaze-asm-cfi.patch`)
  adds CFI to the asm, saving r15 on the cancel path so the unwinder can step the
  `__syscall_cancel_arch` frame.
- **The cancellation branch** (`patches/glibc/0002-...tail-call __syscall_do_cancel`)
  makes `__syscall_cancel_arch` tail-call `__syscall_do_cancel`, so there is no
  frame to unwind through and no CFI is needed there.

The tail-call is the cleaner fix for the cancel frame and should win *for that
frame*. But 0005 also adds CFI to `start.S`, `dl-trampoline.S`, `_mcount.S`,
`clone.S` and the syscall-error path, which the tail-call does not touch and
which a full `_Unwind_Backtrace` still needs. **Recommendation:** adopt the
tail-call (`patches/glibc/0002`) for the cancel path and drop only the
`syscall_cancel.S` hunk from 0005, keeping the rest of its CFI. Both still need
`patches/glibc/0001` (the syscall_cancel stack-argument-offset fix for
`aio_suspend`/`tst-cancel17`), which is a separate real bug 0005 does not fix and
which edits the same file — so 0001, 0002 and the trimmed 0005 must be staged
together and re-tested as a unit.

## What each upstream submission should be, after reconciliation

| Target | Submit | Note |
|---|---|---|
| binutils | 0003, 0004, 0006, 0007, 0008, 0009 (+ optional `.debug_line` min-insn-length) | 0001, 0002 already landed; 0005 (dwarf2 tiebreak) is arch-neutral, send separately |
| gcc | `gcc/0001` (as a fix to Ramin's file), `gcc/0002` | 0002 depends on binutils 0009; ramin-0001 is already upstream |
| glibc | `glibc/0001`, `glibc/0002`, the trimmed `glibc-longjmp-chk/0005`, and 0001-0004, 0006, 0007 | resolve the `syscall_cancel.S` overlap first |
| linux | the four `patches/linux/` kernel patches | Ramin's `ret_from_trap` r4 fix went to LKML; Sam's reserve/MSR patches are the ABI-correctness fixes |

## Decisions that are yours, not mine

1. **libgcc unwinder (Zone B/C):** whether `gcc/0001` is needed at all under
   glibc, and if so what its offset must be once kernel patch #1 is in. Only a
   glibc board with the kernel patch settles it.
2. **Cancel-path fix (Zone D):** confirm the tail-call supersedes the
   `syscall_cancel.S` CFI hunk, and trim 0005 accordingly.
3. **CFI patch choice (Zone A):** already executed (kept 0006); reversible if you
   prefer the smaller form.
