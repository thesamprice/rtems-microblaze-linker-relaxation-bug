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
