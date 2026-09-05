<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. -->

> **History (this session).** The patch went through three forms, tested on a real
> kernel under qemu-system (petalogix, Linux 6.12): Ramin's upstream
> `pc - sizeof(ucontext_t)` fails on both a stock and a reserve kernel under
> glibc; a CFA-anchored form fixes the stock kernel but breaks once
> `patches/linux/`'s 32-byte front reserve moves `&siginfo` off the SP; the
> committed form anchors on the trampoline with a **kernel-sized** ucontext and
> PASSes on both. The three-by-two matrix and reproduction are in
> [sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md); the offset-not-size
> principle it turns on is in
> [glibc-vs-uclibc.md](glibc-vs-uclibc.md#how-the-c-library-kernel-and-unwinder-normally-stay-in-sync).


# gcc 0001: locate the MicroBlaze signal frame from the rt_sigreturn trampoline

**Patch:** `patches/gcc/0001-libgcc-microblaze-signal-frame-glibc-layout.patch`
**Target:** `gcc` master (verified against the live file, ~2026-09)
**Files touched:** `libgcc/config/microblaze/linux-unwind.h`
(`microblaze_fallback_frame_state`)
**Status:** independent runtime fix; the gcc-master `libgcc_s` needs it (glibc-longjmp-chk/README.md:314-325)

## What it does
`microblaze_fallback_frame_state` is libgcc's signal-frame unwinder fallback:
when the DWARF walk reaches a kernel-installed signal handler it recovers the
interrupted register file from the kernel's `rt_sigframe`. The upstream code
found the frame by subtracting `sizeof (ucontext_t)` — the C library's type —
from the sigreturn trampoline address. Under glibc `ucontext_t` is 304 bytes
(128-byte `uc_sigmask`) against the kernel `struct ucontext`'s 184, so the
computed `sigcontext` was 120 bytes too low and every recovered register was
garbage. It works only under uClibc, whose `ucontext_t` matches the kernel — the
comment in the upstream file even says so. The committed patch keeps the same
trampoline structure but fixes the size: it anchors on the trampoline (the last
member of the kernel `rt_sigframe`) and computes the sigcontext with a **local
kernel-sized `ucontext`** whose `uc_sigmask` is the kernel `sigset_t` (8 bytes),
not the C library's (128). Because the trampoline is at the *end* of the frame,
this offset is immune to any argument-save area the kernel reserves at the
*front* — the `patches/linux/` reserve — so it is correct on both kernel
layouts. An intermediate CFA-anchored form (`context->cfa + siginfo_t + 2 longs
+ stack_t`) was tried first; it was correct for the stock frame but broke on the
reserve kernel, which is why the trampoline anchor was chosen (see History).

## Upstream audit: is this already fixed?
**NO — AND THIS IS A CORRECTION OF AN EXISTING UPSTREAM FILE, NOT A NEW FILE.**
`libgcc/config/microblaze/linux-unwind.h` **exists in gcc master today** and is
exactly the buggy version this patch rewrites. Fetched live
(`raw.githubusercontent.com/gcc-mirror/gcc/master/…`), upstream master still:

- `#include <sys/ucontext.h>` (the patch switches to `<asm/sigcontext.h>`);
- matches the trampoline `pc[0]/pc[1]` first, then `pc[2]/pc[3]` with `pc += 2`
  (the patch flips the order and drops the `pc += 2`);
- computes `ucontext_t *uc = (ucontext_t *)((_Unwind_Ptr) pc - sizeof
  (ucontext_t)); sc = &uc->uc_mcontext;` — the wrong-size, trampoline-relative
  arithmetic the patch replaces with `context->cfa + …`.

The file's own header is `Copyright (C) 2026`, i.e. it was *added to gcc master
only recently* and shipped broken for glibc from day one; it was evidently
written against a uClibc-style `ucontext_t`. So the patch is a **fix to a
current-master file**, and a reviewer must treat it as a diff against live
upstream, not as introducing a port. The base the patch was diffed against is
byte-identical to what master carries now.

## Why it survived so long unpatched
The file only ever existed in gcc master (never in a released MicroBlaze
toolchain), and its arithmetic happens to be right for a `ucontext_t` whose
`uc_sigmask` is the kernel's 8 bytes — i.e. uClibc, not glibc. Nobody ran a
glibc MicroBlaze program that unwinds *through* a signal frame:
`backtrace()` from a handler, a C++ throw across a signal-interrupted frame, or
`pthread_cancel` unwinding out of a cancelled syscall. The glibc testsuite that
exercises this (`debug/tst-backtrace4/5/6`, `nptl/tst-cancelx4`,
`tst-cleanupx4`) is never run on the target; on it the unwind simply stopped at
the handler instead of crashing, so the bug was silent.

## What a reviewer should sanity-check (this port)
Read `libgcc/config/microblaze/linux-unwind.h` in the patched tree:

- **:62-67** trampoline match. `pc[2] == (0x31800000 | __NR_rt_sigreturn) &&
  pc[3] == 0xb9cc0008` is tried first, then `pc[0]/pc[1]`. `0x31800000` is
  `addik r12, r0, <imm>` (imm = `__NR_rt_sigreturn`), `0xb9cc0008` is
  `brki r14, 0x8`. r15 = trampoline − 8 and the handler returns `rtsd r15, 8`,
  so the return address `pc` sits 8 bytes (two instructions) before the
  trampoline → the trampoline is at `pc[2]/pc[3]`. The `pc[0]/pc[1]` arm covers
  a `pc` that already points at the trampoline. Note the match is now used
  **only to recognise the frame** — `pc` no longer feeds the `sc` computation.
- **the trampoline offset (the part to check hardest).** `tramp` is normalised
  to point at the trampoline, then `sc = &rt->uc.uc_mcontext` where
  `rt = tramp − __builtin_offsetof (struct rt_sigframe, tramp)` and the local
  `struct rt_sigframe` is `{ siginfo_t info; struct kernel_ucontext uc;
  unsigned int tramp[2]; }`. The load-bearing detail is `kernel_ucontext`, which
  ends in `unsigned long uc_sigmask[64 / (8*sizeof(long))]` (the kernel
  `sigset_t`, 8 bytes on this target), **not** the C library's 128-byte one — a
  probe measured the C-library `struct ucontext` at 304 bytes vs the kernel's
  184, and using the wrong size is exactly Ramin's bug. Anchoring from the
  trampoline at the *end* of the frame is what makes the offset independent of
  the front reserve; confirm `uc_sigmask`'s size matches the kernel's `_NSIG`
  (64 → two words) and that `uc_mcontext` is preceded by `uc_flags, uc_link,
  uc_stack` exactly as the kernel `struct ucontext`.
- **:85-89** register recovery: `for i in 0..31: reg[i] = &sc->regs.r0 +
  i*4 − new_cfa`, with `new_cfa = sc->regs.r1` (:79). `struct sigcontext`
  (asm/sigcontext.h) is `{ struct pt_regs regs; … }` and `pt_regs` holds
  r0..r31 consecutively then `pc`, so `&sc->regs.r0 + i*4` walks the 32 GPRs.
- **:96-99** the interrupted PC goes to `DWARF_ALT_FRAME_RETURN_COLUMN` (= 36,
  `gcc/config/microblaze/microblaze.h:185`), one past the 32 hard regs, and
  `fs->retaddr_column` is set to it; `fs->signal_frame = 1` (:100). Column 15
  (r15, `MB_ABI_SUB_RETURN_ADDR_REGNUM`, microblaze.h:142) is recovered as an
  ordinary GPR in the loop.

## How other processors do the same thing
Most arches anchor the sigcontext on `context->cfa` and read `&rt->uc.uc_mcontext`
through a local `struct rt_sigframe`, reading by **offset** (the same in glibc,
uClibc and the kernel), never by `sizeof`. MicroBlaze cannot use that directly,
because its kernel reserve moves the front of the frame off the CFA; **arm** is
the precedent for what MicroBlaze does instead — it dispatches on the restorer
trampoline to cope with its two kernel frame layouts. **aarch64** only ever grows
its frame at the *tail* (SVE/ZA state as chained records inside `uc_mcontext`),
so its CFA anchor never moves and it never needed the trampoline. The
offset-not-size rule, and where MicroBlaze departed from it, are in
[glibc-vs-uclibc.md](glibc-vs-uclibc.md#how-the-c-library-kernel-and-unwinder-normally-stay-in-sync).
The CFA + local-struct comparators below are still the oracle for the *offset*
math the trampoline path also relies on:

- **libgcc/config/or1k/linux-unwind.h:39-54** — the closest analogue. Declares
  `struct rt_sigframe { siginfo_t info; ucontext_t uc; } *rt = context->cfa;`
  then `sc = &rt->uc.uc_mcontext;`, and `new_cfa = sc->regs.gpr[1]`. Same
  shape, same stack-pointer-from-sigcontext step. or1k lets the compiler
  compute `&uc.uc_mcontext`; MicroBlaze spells the offset out (see below).
- **libgcc/config/sh/linux-unwind.h:83-90** — `struct rt_sigframe { siginfo_t
  info; ucontext_t uc; } *rt_ = context->cfa;` → `sc = &rt_->uc.uc_mcontext;`,
  `new_cfa = sc->sc_regs[15]`. Recognises the trampoline by instruction match
  (`0x9305/0xc310/0x00ad`, the `mov #__NR_rt_sigreturn` + `trapa`).
- **libgcc/config/riscv/linux-unwind.h:47-72** and
  **libgcc/config/aarch64/linux-unwind.h:71-114** — both declare the inline
  `rt_sigframe { siginfo_t info; … ucontext uc; }`, take `rt_ = context->cfa`,
  and `sc = &rt_->uc.uc_mcontext`.

**Why MicroBlaze uses explicit arithmetic rather than the struct trick:** the
patched file includes `<asm/sigcontext.h>` (for `struct sigcontext`) but not a
kernel-shaped `ucontext`, so it cannot name `uc.uc_mcontext` through a struct
without pulling in glibc's `ucontext_t` — whose *size* is what broke the old
code. Hard-coding the kernel frame layout (`siginfo_t + 2 longs + stack_t`)
sidesteps any glibc/kernel `ucontext` divergence. The result is equivalent to
the or1k/sh `&uc.uc_mcontext` because `uc_mcontext` precedes the oversized
`uc_sigmask` in the struct, so only the layout *up to* `uc_mcontext` matters,
and the patch reproduces exactly that prefix. A reviewer comparing against
or1k should confirm the prefix `uc_flags, uc_link, uc_stack` = `2*long +
stack_t` matches the kernel `struct ucontext`.

## Same-processor code that does related logic
- **glibc patch 0004** (`glibc-longjmp-chk/patches/0004-microblaze-ucontext.patch`,
  `sysdeps/unix/sysv/linux/microblaze/ucontext_i.sym`) encodes the *same*
  mcontext shape from the other side: `MCONTEXT_PC = offsetof(uc_mcontext) +
  32*4`, i.e. r0..r31 then pc. The unwinder's `&sc->regs.r0 + i*4` for 32 regs
  and `sc->regs.pc` must agree with that, and they do — both assume 32
  consecutive words followed by the PC. This is the cross-patch consistency
  check the reviewer wants: if one says "pc is word 33" the other must too.
- **gcc/config/microblaze/microblaze.h**: `DWARF_ALT_FRAME_RETURN_COLUMN 36`
  (:185), `RETURN_ADDR_OFFSET 8` (:196, the `rtsd r15,8` return), and
  `INCOMING_RETURN_ADDR_RTX` = r15 (:192-193). The unwinder's use of column 36
  for the interrupted PC and its 8-byte trampoline reasoning both derive from
  these; they must stay in step.

## Other cross-checks
- **Kernel sigframe:** `arch/microblaze/kernel/signal.c` `struct rt_sigframe {
  struct siginfo info; struct ucontext_abi uc; unsigned int tramp[2]; }` with
  `setup_rt_frame` doing `regs->r1 = (unsigned long) frame` and writing the two
  trampoline words into `frame->tramp`. That is the authority for both the
  "CFA = frame" claim and the trampoline instructions; the kernel tree was not
  present in the container, so verify these two facts against the running
  kernel's source when reviewing.
- **qemu-user:** places the trampoline on its own page and points r15 8 bytes
  before it, which is why the patch probes `pc[2]/pc[3]` first and why the old
  trampoline-relative subtraction failed there even under uClibc.

## How to verify on real hardware
No qemu/docker. On a MicroBlaze Linux board with the patched `libgcc_s`:

1. **Backtrace through a handler.** Install a `SIGALRM` (or `SIGSEGV`) handler
   that calls `_Unwind_Backtrace` (or `backtrace()`), raise it, and print the
   frame count. Unpatched: the walk stops *at* the handler (e.g. 3 frames).
   Patched: it continues past the signal frame into the interrupted code (e.g.
   6+ frames). This is glibc's `debug/tst-backtrace4`.
2. **Throw across a signal frame** (C++): raise a signal in a leaf, throw from
   the handler, catch in a caller of the interrupted function; the catch is
   reached only if the signal frame unwinds.
3. **Cancellation:** a thread blocked in `read()` that is `pthread_cancel`ed
   must run its cleanup handlers — `nptl/tst-cancelx4` / `tst-cleanupx4`. These
   need the unwinder to step out of the cancelled syscall's signal frame.

Confirm each recovered register by comparing `sc->regs.r1`/`pc` against the
interrupted frame's known sp/return address.
