# glibc vs uClibc on MicroBlaze: why the C library changes the toolchain

Several of the fixes in this repository behave differently depending on which C
library the target uses, because parts of the toolchain — above all libgcc's
signal-frame unwinder — depend on the C library's runtime data layout. This is a **Linux** question; the RTOS and bare-metal targets (RTEMS,
FreeRTOS) use Newlib and are unaffected — see the last section. The two
libraries in play on MicroBlaze Linux are **uClibc-ng** (the common default, and the only option without an MMU)
and **glibc** (an MMU-only choice). This note collects
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

## Which toolchains use which library (checked, 2026-09)

MicroBlaze is a soft-core that is often built **without an MMU**, and **glibc
requires an MMU** — so a large share of MicroBlaze Linux systems *cannot* use
glibc at all. uClibc-ng supports both MMU and no-MMU, which is why it is the
common default:

- **Buildroot**: default C library for MicroBlaze is **uClibc**; glibc is an
  opt-in.
- **PetaLinux**: historically defaults to **uClibc**, with glibc selectable in
  the rootfs config.
- **Bootlin** toolchains: offered in **all three** (glibc, uClibc-ng, musl)
  variants — there is no single default; you choose. This repo used the glibc
  variant.
- **Yocto / meta-xilinx**: `TCLIBC` is configurable; the meta-microblaze layer
  does not declare a MicroBlaze-specific default.

So **uClibc-ng is at least as common as glibc on MicroBlaze, and likely the more
typical default**; glibc is the MMU-only minority — which is what this repo, the
Bootlin glibc toolchain, and the original native-gdb report happen to use. The
long-broken, never-tested state of the glibc MicroBlaze port is consistent with
it being a minority rather than the mainstream. (This is the project-default
picture, not a usage statistic.)

## RTOS and bare-metal: Newlib (RTEMS, FreeRTOS)

Everything above is about **Linux**. The RTOS and bare-metal targets do not use
glibc or uClibc at all, and none of the signal-frame / unwinder discussion
applies to them — they have no Linux kernel, no `rt_sigframe`, no `ld.so`, and no
`ucontext_t` in the Linux sense.

- **RTEMS** uses **Newlib**. The `microblaze-rtems` toolchain links Newlib as its
  C library; RTEMS supplies the OS glue on top. This repository *started* as an
  RTEMS/Newlib problem — the `-O2` linker-relaxation miscompile in `ANALYSIS.md`
  (binutils 0001, now upstream) — which is a toolchain bug, independent of the C
  library.
- **FreeRTOS** ships **no C library of its own** — it is only a scheduler/kernel.
  Applications link whatever the toolchain provides, which on embedded targets is
  **Newlib** (often newlib-nano), or **picolibc** as a modern alternative. On
  Xilinx MicroBlaze, FreeRTOS is built against the Xilinx standalone/bare-metal
  BSP, which is Newlib-based.

So on MicroBlaze the C library depends on the target:

| Target | C library |
|---|---|
| Linux, MMU | glibc *or* uClibc-ng *or* musl (uClibc-ng most common) |
| Linux, no-MMU (uClinux) | uClibc-ng or musl (glibc not possible) |
| RTEMS | Newlib |
| FreeRTOS / bare-metal | Newlib (newlib-nano), or picolibc; no libc from FreeRTOS itself |

The signal-frame unwinder issue in this document is confined to the top two rows,
and specifically bites glibc.

## Practical guidance

- **Test signal-frame unwinding under glibc, not uClibc.** A uClibc build hides
  the unwinder bug. Use the [sigframe-test](sigframe-test/README.md) under
  qemu-system with a glibc rootfs.
- **When submitting gcc 0001 upstream, frame it as a glibc bug fix**, not just as
  support for the kernel reserve: the upstream unwinder is broken for every glibc
  MicroBlaze target today, independent of the reserve. glibc is a minority on
  MicroBlaze (uClibc-ng is more common, and the only option without an MMU), so
  it affects fewer users than the headline suggests — but it is a real, total
  failure for those it does affect.
- **If you maintain both libraries**, the trampoline anchor is correct for both
  (it uses the kernel layout, which uClibc already matches), so it is a strict
  improvement, not a glibc-only special case.
