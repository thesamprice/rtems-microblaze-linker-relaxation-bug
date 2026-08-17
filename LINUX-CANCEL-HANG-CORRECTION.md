# RESOLVED — MicroBlaze glibc signal/cancellation bugs (read this first)

`LINUX-CANCEL-HANG.md` (the long doc below) concluded the read()-cancel hang was a
kernel race in the interrupts-enabled signal-return window. **That conclusion was
wrong** — the timing sensitivity was the observer effect on a race that does not
exist; the assembly is fine. This file is the corrected, final account.

Neal Frager surfaced the failures (glibc testsuite under QEMU after the MicroBlaze
GCC-15 kernel finally booted). They turned out to be **several distinct, pre-existing
bugs**, none caused by Sam's entry.S argument-save fix — that fix merely lets a
GCC-15 kernel boot far enough to reach them. Four kernel/gcc bugs, one latent MSR
correctness bug, and one glibc bug (below).

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

6. **tst-cancel17 (aio_suspend) = glibc `__syscall_cancel_arch` reads stack args
   from the wrong offset.** `sysdeps/unix/sysv/linux/microblaze/syscall_cancel.S`
   loads the cancellable syscall's 5th/6th arguments (its 7th/8th params, passed on
   the stack) from `r1+56`/`r1+60`, but the MicroBlaze ABI puts the 7th stack arg at
   `r1+28` (link word at `r1+0` + six register-arg save slots `r1+4..r1+24`) and the
   8th at `r1+32` — where the compiler-generated callers store them (`__GI___pread`:
   `swi r11,r1,28`). So every cancellable syscall passing args on the stack reads
   uninitialised caller stack. The visible victim is **pread64/pwrite64**, whose 5th
   arg is the high word of the 64-bit offset: a valid offset 0 becomes garbage, so
   `pread64(pipe,..,0)` returns **EINVAL** (kernel `pos<0` check) instead of ESPIPE.
   That defeats the POSIX-AIO ESPIPE→`read()` fallback in `rt/aio_misc.c`, so
   `aio_read` completes immediately with EINVAL and `aio_suspend` returns before it
   can block — nothing to cancel. **Fix: Sam's
   `microblaze: fix syscall_cancel stack-arg offsets`** (`r1+56/60` → `r1+28/32`).
   Isolated with a raw non-cancellable `INTERNAL_SYSCALL_CALL(pread64,..,0,0)` from
   the *same* AIO helper thread returning `-ESPIPE` while the cancellable `__pread`
   returned EINVAL, then disassembling `__GI___pread` vs the stub. **Verified on
   qemu:** with the fix `pread64(pipe,..,0)` returns ESPIPE, the AIO request blocks,
   and the real `nptl/tst-cancel17` binary passes (was failing). Almost certainly a
   latent port bug (the offsets never matched the ABI), independent of GCC-15.

7. **tst-cancelx4/x17 (-fexceptions cancellation) = the cancel-syscall asm is
   unwindable-through only with CFI, which MicroBlaze gas cannot assemble.**
   `__syscall_cancel_arch` reaches `__syscall_do_cancel` with
   `brlid r15, __syscall_do_cancel` — the link overwrites r15 (the return address
   into the syscall wrapper) and makes the hand-written asm a distinct stack frame
   that `_Unwind_ForcedUnwind` must traverse. But MicroBlaze `gas` rejects `.cfi`
   ("CFI is not supported for this target" — binutils 2.45.1), so this asm has no
   `.eh_frame`; every other frame in the chain (`__syscall_do_cancel`, the wrapper,
   the test) does. So the `-fexceptions` forced unwind stops at the asm and cleanup
   handlers never run — **every** early-cancel point in `nptl/tst-cancelx4` failed.
   `__syscall_do_cancel` is `_Noreturn`, so the link is pointless. **Fix: Sam's
   `microblaze: tail-call __syscall_do_cancel` (`brlid r15,` → `brid`)** — the asm
   contributes no frame, `__syscall_do_cancel` (C, with `.eh_frame`) is entered as
   if the wrapper called it, and the unwind flows straight to the cleanup. Verified:
   tst-cancelx4 early-cancel goes from all-fail to all-pass. Residual: the in-time /
   async cancellation points (read/readv/writev/wait*/accept/recv*, and
   tst-cancelx17) still fail — those unwind through the SIGCANCEL **signal frame**
   (Ramin's libgcc `linux-unwind.h`), a separate path still under investigation.

## Patches in this repo

`patches/glibc/`:
- `0001-microblaze-fix-syscall_cancel-stack-arg-offsets.patch` — bug #6, MAILED
  2026-08-16 to Neal (Cc Ramin + Sam).
- `0002-microblaze-tail-call-__syscall_do_cancel-so-fexceptio.patch` — bug #7,
  not yet mailed. Both are glibc patches → libc-alpha / MicroBlaze maintainers.
  Both bugs are still present in glibc git master (HEAD).

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
segfault), `mb-msrtest.c`, `mb-r19test.c`, `mb-aiosusp.c` (the #6 aio_suspend
cancel A/B: prints CANCELED/not-canceled), `mb-preadctx.c` and `mb-aiohelper.c`
(pread-on-pipe probes that isolated #6 to the cancellable path). `canceltrace.c`
is the non-perturbing QEMU TCG plugin used to trace the handler under `-icount`.

## Residual (low priority)

With all fixes, cancel-min cancels on wall-clock. Under `qemu -icount` a tight
timing race can still hang, and any perturbation (even a plugin under icount)
flips it — most likely an icount artifact rather than a real-HW bug. Tracked on
issue #7; wall-clock/real-HW-like timing is solid.
