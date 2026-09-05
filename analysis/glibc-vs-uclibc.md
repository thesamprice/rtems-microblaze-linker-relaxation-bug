# glibc vs uClibc on MicroBlaze: why the C library changes the toolchain

Several of the fixes in this repository behave differently depending on which C
library the target uses, because parts of the toolchain — above all libgcc's
signal-frame unwinder — depend on the C library's runtime data layout. The two
libraries in play on MicroBlaze Linux are **glibc** (the modern default) and
**uClibc-ng** (still common in minimal Buildroot systems). This note collects
the library-dependent differences so a reviewer or a distributor knows what is
affected and what to test where.

Everything below about glibc is measured on the Bootlin `microblazeel` glibc
(2.41) under qemu-system with a real 6.12 kernel. The uClibc column is what the
code and its authors assert (Ramin's unwinder comment; the kernel headers); it
was not re-measured here, and that gap is called out where it matters.

## The one difference that drives everything: `ucontext_t` / `sigset_t` size

The kernel writes a `struct ucontext` into the signal frame. Its `uc_sigmask` is
the **kernel** `sigset_t`, which is small; the C library's `ucontext_t` puts a
much larger `sigset_t` at the same field, so the two types have very different
sizes even though the useful part (`uc_mcontext`) sits at the same offset.

| | kernel | uClibc | glibc |
|---|---|---|---|
| `sigset_t` (`uc_sigmask`) | 8 bytes (`_NSIG` = 64, 2 words) | matches the kernel | **128 bytes** (1024 bits) |
| `sizeof(ucontext_t)` | 184 bytes | matches the kernel | **304 bytes** |
| offset of `uc_mcontext` | 20 | 20 | 20 (same) |

The offset of `uc_mcontext` is the same everywhere (the oversized `uc_sigmask`
comes *after* it). Anything that uses that **offset** is portable; anything that
uses `sizeof(ucontext_t)` is not.

## Where it bites: the libgcc signal-frame unwinder

`libgcc/config/microblaze/linux-unwind.h` (Ramin Moussavi's, in gcc 15.3 / 16.2
/ master) locates the sigcontext as:

```c
ucontext_t *uc = (ucontext_t *) (pc - sizeof (ucontext_t));
sc = &uc->uc_mcontext;
```

It uses `sizeof(ucontext_t)`, the size that differs between the libraries:

| unwinder | uClibc | glibc, stock kernel | glibc, reserve kernel |
|---|---|---|---|
| Ramin's upstream (`pc - sizeof(ucontext_t)`) | works (by design) | **FAIL** | **FAIL** |
| gcc 0001, CFA-anchored (earlier this repo) | — | PASS | FAIL |
| gcc 0001, trampoline-anchored (now) | — | **PASS** | **PASS** |

Read the code and it is explicit: Ramin's own comment says *"uClibc's ucontext_t
matches the kernel's struct ucontext."* It was written and validated for uClibc,
where `sizeof(ucontext_t) == 184` and the arithmetic lands on the frame. Under
glibc, `sizeof(ucontext_t) == 304`, the subtraction overshoots by 120 bytes, and
`_Unwind_Backtrace` from a signal handler stops at the signal frame. Verified:
FAIL on both a stock and a reserve-patched kernel under glibc (see
[sigframe-test/FINDINGS.md](sigframe-test/FINDINGS.md)).

So on glibc this is a **live upstream bug today**, with or without any kernel
change: backtraces from handlers and C++ exceptions thrown through a
signal-interrupted frame do not unwind. On uClibc the same code is fine, which
is why it went unnoticed — the users who hit it are on glibc.

The fix in `patches/gcc/0001` anchors on the rt_sigreturn trampoline (at the end
of the frame) and computes the offset with a **kernel-sized** ucontext, so it is
correct for glibc and independent of the kernel's front-of-frame layout. It
passes on both kernels under glibc.

## Other library-dependent items in this series

These are less about a size mismatch and more about which library exercises a
path at all:

- **`____longjmp_chk` (glibc 0001).** The do-nothing stub hangs every fortified
  `longjmp`. It is a glibc file; the bug surfaces on glibc systems (the original
  native-gdb report was glibc). uClibc has its own fortify implementation and
  does not use this file.
- **Destructors via `_dl_fini` (glibc 0003).** glibc 2.34+ runs `.fini_array`
  through `_dl_fini`; MicroBlaze `start.S` never passed it, so destructors were
  silently skipped in dynamically linked glibc programs. This is specific to
  glibc's post-2.34 startup contract.
- **`ucontext` (glibc 0004), asm CFI (glibc 0005), `backtrace` (glibc 0006),
  `ld.so` `.eh_frame` (glibc 0007).** These are glibc source files; the
  behaviour they fix is what glibc's own testsuite exercises. Nobody runs that
  suite on MicroBlaze, which is why the gaps persisted.

## Which toolchains use which library

- **glibc** is the default in the mainstream flows: AMD/Xilinx **PetaLinux**
  (Yocto-based), **Bootlin** MicroBlaze toolchains, and **Yocto / OpenEmbedded**
  generally. Modern vendor and distro builds are glibc.
- **uClibc-ng** remains common in **Buildroot** minimal-footprint builds, and was
  the default in older, pre-Yocto PetaLinux — which is the era much of the
  existing MicroBlaze code (including the unwinder) was written and tested in.

(These are the qualitative ecosystem defaults, not a usage statistic.)

## Practical guidance

- **Test signal-frame unwinding under glibc, not uClibc.** A uClibc build hides
  the unwinder bug. Use the [sigframe-test](sigframe-test/README.md) under
  qemu-system with a glibc rootfs.
- **When submitting gcc 0001 upstream, frame it as a glibc bug fix**, not just as
  support for the kernel reserve: the upstream unwinder is broken for every glibc
  MicroBlaze target today, independent of the reserve.
- **If you maintain both libraries**, the trampoline anchor is correct for both
  (it uses the kernel layout, which uClibc already matches), so it is a strict
  improvement, not a glibc-only special case.
