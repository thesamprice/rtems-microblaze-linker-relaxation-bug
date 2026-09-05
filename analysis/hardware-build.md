# Building the MicroBlaze Linux target with hardware acceleration

The toolchain used throughout this repository (Bootlin `microblazeel--glibc--
stable-2025.08-1`) defaults to the most conservative MicroBlaze configuration —
everything soft-emulated:

```
-mcpu=v4.00.a        (an old core version)
-msoft-float         (no FPU; float ops via soft-fp calls)
-mxl-soft-mul        (multiply emulated)
-mxl-soft-div        (divide emulated)
-mxl-barrel-shift    disabled  (shifts emulated)
-mxl-pattern-compare disabled
-mxl-multiply-high   disabled
-mxl-reorder         disabled
```

That is the lowest-common-denominator a soft-core toolchain ships. A target
whose FPGA has the hardware units wants them turned on. `-O2` is already the
default for the built libraries (glibc, gcc, binutils, and the glibc tests).

## The flag set for a full-featured core

```
-O2 -mcpu=v11.0 -mhard-float -mxl-barrel-shift -mxl-multiply-high \
    -mno-xl-soft-mul -mno-xl-soft-div -mxl-pattern-compare -mxl-reorder
```

Which of these you may use is set by the FPGA design — a MicroBlaze built
without a barrel shifter cannot run `-mxl-barrel-shift` code, which is exactly
why the toolchain default is conservative. Match the flags to the hardware.

## It is correctness-safe: none of the fixes here depend on the arithmetic units

Verified on qemu-system (petalogix, Linux 6.12): the signal-frame unwinder test
(gcc 0001) built with the **full flag set above at -O2** unwinds correctly —
PASS, all frames recovered. The exception-handling, CFI, relocation and
signal-frame fixes are about frame layout and relocations, not arithmetic, so
the hardware int/float flags do not affect them.

(One caveat found while checking, worth stating precisely because it *looks*
like an unwinder failure and is not: at `-O2` gcc inlines the whole trivial call
chain `main <- outer <- mid <- leaf` into `main`, so `main` calls `raise()`
directly. The `leaf`/`mid`/`outer` symbols survive only because their addresses
are taken for the marker array; nothing calls them (confirmed by disassembly:
no `brlid` targets them). So those frames genuinely are not on the stack, and
the backtrace correctly omits them -- the unwinder reported exactly what was
there. A backtrace test whose markers are not `noinline` mistakes that for a
failure. `sigframe-test/sigunwind.c` now marks its markers `noinline` so the
call chain is real; this is a property of the test, not the unwinder, which is
correct at both -O1 and -O2.)

## Hard-float on MicroBlaze: two things that are not obvious

1. **It is ABI-compatible with soft-float.** MicroBlaze's FPU operates on the
   general-purpose registers — there is no separate float register file and no
   `-mfloat-abi` split as on arm. `-mhard-float` changes only whether float ops
   compile to FPU instructions (`fadd`, `fmul`) or soft-fp calls (`__mulsf3`);
   the calling convention is identical. So hard-float object code links against
   the existing soft-float glibc, and float args pass the same way.

2. **It does NOT change glibc patch 0002.** The MicroBlaze FPU has no
   configurable rounding and no exception status flags: `sysdeps/microblaze/
   bits/fenv.h` defines `FE_ALL_EXCEPT 0` and only `FE_TONEAREST`. That is a
   hardware property, true whether or not `-mhard-float` is passed. So patch
   0002 (`math-tests-exceptions.h` / `-rounding.h`, which tell the libm suite
   there are no exceptions and only round-to-nearest) stays correct on a
   hard-float target. Hard-float speeds float *operations*; it does not give the
   core an fenv it lacks.

## For a fully hardware-accelerated runtime

The flag set above makes *application* code use the hardware. To make glibc and
libgcc themselves use it, rebuild them with the same flags (glibc's MicroBlaze
port is soft-fp-based — `sysdeps/.../Implies` selects `ieee754/soft-fp` — but
that is the software *implementation* of float; compiling glibc `-mhard-float`
emits FPU instructions for its math and the soft-fp fenv stays a correct no-op).
No hard-float glibc *port* is required, because of the ABI compatibility above.
The `harness/run.sh` configure lines are where you would add the flags
(`CFLAGS`/`CC`), then rerun the suite; the correctness results already recorded
carry over, since the fixes are independent of the arithmetic units.
