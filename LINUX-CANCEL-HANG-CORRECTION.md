# CORRECTION (read this first) — the real causes, per Neal Frager / Ramin Moussavi

`LINUX-CANCEL-HANG.md` below concluded the read()-cancel hang was a kernel race in
the interrupts-enabled signal-return window. **That conclusion was wrong** — the
timing sensitivity was the observer effect on a race that does not exist. The
assembly is fine. The real picture (Neal + Ramin; verified here):

1. **Hangs (tst-cancel\*) = missing libgcc signal-frame unwinder.** gcc `4ef64ad1a`
   (Ramin Moussavi) adds `md_unwind_header=microblaze/linux-unwind.h`; without it
   the DWARF unwinder can't step a signal frame and NPTL cancellation stops early.
   Our buildroot GCC 15.3.0 lacked it. **Confirmed working after adding it**:
   `backtrace()` from a signal handler now steps to `_start` (8 frames).

2. **Segfaults (tst-eintr1) = kernel `ret_from_trap` clobbers r4 on rt_sigreturn.**
   Ramin's patch (`Fixes: 791d0a169b91`, LKML 2026-07-27). Vindicates the atomics
   hunch: only r4 is lost, in the `lwx`/`swx` CAS windows `__atomic` emits.
   **Confirmed**: fixed the corrupted `si_pid` the SIGCANCEL handler saw.

3. **Still open (glibc-specific): read()-cancel disabled by the cancel-bridge PC
   check.** With BOTH fixes, cancel-of-blocked-`read()` on glibc still hangs: the
   handler passes pid/si_code/async checks then returns via the
   `framepc >= __syscall_cancel_arch_end` branch — the interrupted read IP is
   at/past glibc's cancel bridge, so the cancel is disabled and the SA_RESTART read
   loops. glibc-specific (Neal's uClibc-ng CI passes with fix 1 alone).

Sam's entry.S argument-save-area patch is a **separate, real boot-fix** (GCC-15
kernels die with r1=0xFFFFFF9C=AT_FDCWD without it); it merely lets the kernel boot
far enough to reach these pre-existing bugs. Tracking: issues #7 (hangs) and #8
(latent correctness). The material below is kept as the investigation trail.
