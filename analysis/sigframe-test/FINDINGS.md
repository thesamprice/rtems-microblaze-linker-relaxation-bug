# Finding: gcc 0001's signal-frame offset is kernel-layout-dependent

Ran `sigunwind` (built with the patched gcc, so it carries gcc 0001's
CFA-anchored unwinder) under `qemu-system-microblazeel -M petalogix-s3adsp1800`
on a Linux 6.12.9 kernel built two ways: stock, and with `patches/linux/`
applied (the arg-save-reserve that puts `unsigned long arg_save[8]` at the front
of `struct rt_sigframe`, moving `&siginfo` 32 bytes off the handler's SP).

| libgcc offset | stock kernel | patched kernel |
|---|---|---|
| gcc 0001 as committed (`cfa + sizeof(siginfo_t) + uc-head`) | **PASS** (12 frames, full chain) | **FAIL** (4 frames, stops at the signal frame) |
| gcc 0001 `+ 8*sizeof(long)` (i.e. + the 32-byte reserve) | **FAIL** (3 frames) | **PASS** (12 frames) |

Adding exactly the reserve size flips the result, so no single CFA-relative
offset works for both kernels. gcc 0001 is correct for the **stock** kernel and
breaks once your reserve patch is in.

## Why, from the kernel source

Stock `arch/microblaze/kernel/signal.c`:

```c
struct rt_sigframe {
	struct siginfo   info;      /* SP points here: SP == &info */
	struct ucontext  uc;
	unsigned long    tramp[2];  /* rt_sigreturn trampoline, at the END */
};
```

gcc 0001 anchors at `context->cfa` (the handler's SP) and adds the siginfo and
the ucontext head to reach `uc_mcontext`. That is right only while `SP == &info`.
`patches/linux/0001` inserts `arg_save[8]` before `info`, so `SP == &arg_save`
and `&info == SP + 32` — the anchor is short by 32.

## The robust direction (not implemented here)

The trampoline sits at the END of the frame, and the kernel sets
`regs->r15 = frame->tramp - 8`, so the unwound return address is a fixed
distance from `uc` **regardless of the front reserve**. Ramin's original
upstream form anchored there (`uc = pc - sizeof(ucontext_t)`); its only bug was
using glibc's `sizeof(ucontext_t)` (large) instead of the kernel's. Anchoring
from the trampoline with the **kernel's** `struct ucontext` size (from
`<asm/ucontext.h>`) would be immune to the reserve and correct for glibc.

The catch, and why gcc 0001 chose the CFA instead: the same `setup_rt_frame` can
place the trampoline on a **separate fixed page** rather than in the frame
(`address += (unsigned long)frame->tramp & ~PAGE_MASK`), in which case
`pc - sizeof(uc)` does not land in the frame. Whether that path is ever taken
depends on the kernel config. So neither anchor is universally safe; the choice
is the kernel maintainer's, which is why this is left as a finding rather than a
rewrite of gcc 0001.

## Reproduce

```sh
# two kernels
CROSS_COMPILE=microblazeel-buildroot-linux-gnu- ./build-kernel.sh stock   && cp linux-6.12.9/vmlinux vmlinux-stock
CROSS_COMPILE=microblazeel-buildroot-linux-gnu- ./build-kernel.sh patched && cp linux-6.12.9/vmlinux vmlinux-patched
# test built with the patched gcc (MODE=alrm is the reliable trigger under emulation)
CC=/opt/gcc17/bin/microblazeel-linux-gnu-gcc MODE=alrm ./build-test.sh
KERNEL=vmlinux-stock   ./run-qemu-system.sh   # PASS
KERNEL=vmlinux-patched ./run-qemu-system.sh   # FAIL, stops at the signal frame
```

## Resolution: anchor on the trampoline (implemented)

gcc 0001 was rewritten to anchor on the trampoline instead of the CFA. The
trampoline is the last member of the kernel's `rt_sigframe`, so the sigcontext
is a fixed distance *below* it, independent of any arg-save area reserved at the
front. The distance is computed with a local `struct` whose `uc_sigmask` is the
**kernel** `sigset_t` (8 bytes, `_NSIG == 64`), not the C library's 128-byte one
— getting that size wrong is the original bug (Ramin's `pc - sizeof(ucontext_t)`
used glibc's). Verified: PASS on **both** the stock and the reserve-patched
kernel, 12 frames each.

| libgcc unwinder | stock kernel | reserve kernel |
|---|---|---|
| Ramin's upstream (gcc 15.3/16.2/master), `pc - sizeof(ucontext_t)` | FAIL | FAIL |
| gcc 0001 CFA-anchored (earlier) | PASS | FAIL |
| gcc 0001 trampoline-anchored (now) | **PASS** | **PASS** |

Two independent problems, both tested under glibc on the real kernel:

- **A pre-existing upstream bug, unrelated to the kernel reserve.** Ramin's
  unwinder (currently in gcc master) fails on the *stock* kernel under glibc,
  because it subtracts glibc's `ucontext_t` (304 bytes) where it needs the
  kernel's `struct ucontext` (184). It was written for uClibc, whose `ucontext_t`
  matches the kernel; under glibc, signal-frame unwinding is broken with no
  kernel change involved. A uClibc buildroot would not show it.
- **The kernel reserve is a second, orthogonal break.** A libgcc that fixes the
  first bug by CFA-anchoring still breaks once the reserve moves `&siginfo` off
  the handler's SP. The trampoline anchor tolerates both.

## How other processors handled kernel signal-frame changes

- **Most never moved the frame head.** aarch64 grew its sigcontext for SVE/ZA
  state, but those go in *chained extension records inside* `uc_mcontext`, at the
  tail — so `context->cfa` still points at `siginfo` and the anchor never moved.
  No unwinder change was needed. Its "Historically ... `uc_mcontext`" comment is
  a *type* rename (`struct sigcontext` to glibc's `mcontext_t`), not a layout
  change.
- **arm is the precedent for a real layout change.** The ARM kernel had two
  distinct signal frames (`struct sigframe` and later `struct rt_sigframe`); its
  libgcc unwinder tells them apart by the restorer trampoline instructions and
  uses the matching offset. That is the same trampoline-dispatch idea used here.
- **The MicroBlaze difference.** The arg-save reserve inserts space at the
  *front* of the frame, moving `&siginfo` off the handler's SP — something no
  other arch does, because they only ever grew their frames at the tail. That is
  why CFA-anchoring, which is fine everywhere else, is not enough here, and why
  the trampoline anchor (arm-style, immune to a front change) is the right fit.
