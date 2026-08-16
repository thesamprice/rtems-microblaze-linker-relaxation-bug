# RESOLVED — MicroBlaze glibc signal/cancellation bugs (read this first)

`LINUX-CANCEL-HANG.md` (the long doc below) concluded the read()-cancel hang was a
kernel race in the interrupts-enabled signal-return window. **That conclusion was
wrong** — the timing sensitivity was the observer effect on a race that does not
exist; the assembly is fine. This file is the corrected, final account.

Neal Frager surfaced the failures (glibc testsuite under QEMU after the MicroBlaze
GCC-15 kernel finally booted). They turned out to be **four distinct, pre-existing
bugs**, none caused by Sam's entry.S argument-save fix — that fix merely lets a
GCC-15 kernel boot far enough to reach them.

## The four bugs and their fixes

1. **Boot death (GCC-15 + stock kernel).** GCC-15's IRA change (`3b9b8d6cfdf5`)
   makes kernel C handlers spill incoming args into the ABI argument-save area;
   stock entry.S calls C with `r1` on live `pt_regs`, so init's first `*at`
   overwrites the saved user SP with `AT_FDCWD` and the kernel panics.
   **Fix: Sam's `microblaze: reserve the ABI argument save area when calling C
   from entry.S`.** Confirmed by a boot A/B: with Romain Naour's
   `TARGET_CALLEE_SAVE_COST` GCC workaround removed (so GCC-15 spills for real),
   stock entry.S dies (`r1=0xFFFFFF9C`), and Sam's reservation boots.

2. **tst-cancel* hangs = missing libgcc signal-frame unwinder.** No
   `md_unwind_header` for `microblaze*-linux*`, so the DWARF unwinder can't step a
   signal frame and NPTL cancellation stops early. **Fix: Ramin Moussavi's gcc
   `4ef64ad1a`** (in gcc 15.3/16.2). Confirmed: our buildroot GCC 15.3.0 lacked it;
   after adding it, `backtrace()` from a handler steps through the signal frame
   (`patches/linux/ramin-0001-...`).

3. **tst-eintr1 segfaults = kernel `ret_from_trap` clobbers r4 on rt_sigreturn.**
   `ret_from_trap` stores r3/r4 into pt_regs unconditionally; for rt_sigreturn that
   clobbers the just-restored r4. Only bites in `lwx`/`swx` CAS windows that keep an
   address in r4. **Fix: Ramin's LKML patch, `Fixes: 791d0a169b91`.** (Vindicated
   the atomics hunch.)

4. **glibc read()-cancel hang = SIGCANCEL handler clobbers its own siginfo.**
   `setup_rt_frame` sets the handler's SP to the frame base, and `struct rt_sigframe`
   has `siginfo` at offset 0 — so **SP == &siginfo**. The handler's ABI spill of its
   siginfo arg across `getpid()` (`swi r6, r1, 40`) lands on `si_code`; the
   `si_code != SI_TKILL` check then fails and the cancel is dropped. Measured
   directly (`si_code -6 -> the si pointer`). **Fix: Sam's
   `microblaze: reserve the ABI argument save area in the signal frame`** — the
   signal-frame analogue of bug #1. Verified: with it + the libgcc unwinder,
   cancel-min cancels on wall-clock.

Plus a latent correctness bug found along the way:

5. **MSR dropped from the signal context.** `setup/restore_sigcontext` never
   touch MSR, so the interrupted carry is lost across signals and a handler cannot
   adjust the resumed flags via `uc_mcontext.regs.msr`. **Fix: Sam's
   `microblaze: preserve the MSR carry flags across signals`** — save MSR, restore
   only `MSR_C|MSR_CC` masked (privileged bits kept from the kernel; same as x86
   `FIX_EFLAGS`). Verified: ucontext-MSR propagation 0/132 -> 130/132, no
   cancel-min regression.

## Patches in this repo

`patches/linux/`:
- `0001-microblaze-reserve-the-ABI-argument-save-area-in-the.patch` — bug #4,
  mailed to Neal + Ramin, Msg-Id `<20260816205752.66769-1-thesamprice@gmail.com>`.
- `0002-microblaze-preserve-the-MSR-carry-flags-across-signals.patch` — bug #5,
  mailed, Msg-Id `<20260816223827.89404-1-thesamprice@gmail.com>`.
- `ramin-0001-libgcc-microblaze-signal-frame-unwinding.patch` — bug #2 (Ramin,
  gcc `4ef64ad1a`), for reference.

Bug #1 (entry.S arg-save) and bug #3 (`ret_from_trap`) are tracked/sent separately.

## Reproducers (`linux-cancel-hang/`)

`repro/`: `cancel-min.c` (read-cancel), `cancel-diag.c`, `pc-probe.c`,
`mb-msr2.c` (ucontext-MSR round-trip, the #5 A/B), `mb-eintr.c` (r4-in-CAS
segfault), `mb-msrtest.c`, `mb-r19test.c`. `canceltrace.c` is the non-perturbing
QEMU TCG plugin used to trace the handler under `-icount`.

## Residual (low priority)

With all fixes, cancel-min cancels on wall-clock. Under `qemu -icount` a tight
timing race can still hang, and any perturbation (even a plugin under icount)
flips it — most likely an icount artifact rather than a real-HW bug. Tracked on
issue #7; wall-clock/real-HW-like timing is solid.
