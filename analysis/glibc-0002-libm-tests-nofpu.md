<!-- Per-patch analysis. Cite code as path:line. -->

# glibc 0002: libm tests abort on soft-float MicroBlaze (no exception/rounding config)

**Patch:** `glibc-longjmp-chk/patches/0002-microblaze-libm-tests-nofpu.patch`
**Target:** glibc (`sourceware.org/git/glibc.git`) at base commit `10ed541ad145` (2026-08-25)
**Files touched:** adds `sysdeps/microblaze/math-tests-exceptions.h`, `sysdeps/microblaze/math-tests-rounding.h`
**Status:** independent; sent to Neal Frager as part of the 3-patch set on 2026-09-02; not yet on libc-alpha.

## What it does
MicroBlaze is soft-float on `ieee754/soft-fp` with a `bits/fenv.h` that defines no FE_* exception classes and only to-nearest rounding. The libm test harness was never told this, so `test_exceptions` in `math/libm-test-support.c` found no exception class to exercise and tripped `assert (ran == 1)` — 933 math tests abort with SIGABRT on a cross build run under qemu-user. This is a testsuite-configuration gap, not a runtime bug. The patch adds the two per-arch override headers (`EXCEPTION_TESTS_* = 0`, `ROUNDING_TESTS_* == FE_TONEAREST`) that every soft-float port already carries, and `math/` then runs 1162 PASS / 0 FAIL.

## Upstream audit: is this already fixed?
Not fixed. Verified against the `bminor/glibc` `master` mirror (sourceware cgit is Anubis-blocked): both `sysdeps/microblaze/math-tests-exceptions.h` and `sysdeps/microblaze/math-tests-rounding.h` return HTTP 404 — neither exists upstream. Without them the sysdeps search falls back to `sysdeps/generic/math-tests-exceptions.h:25-28` and `sysdeps/generic/math-tests-rounding.h:25-28`, both of which assert full FE support (`EXCEPTION_TESTS_* 1`, `ROUNDING_TESTS_* 1`) — the exact defaults that make the harness expect exceptions MicroBlaze cannot raise.

## Why it survived so long unpatched
Same root cause as 0001: nobody runs the libm suite on MicroBlaze. `build-many-glibcs.py` only compiles, and this assert fires only when the tests actually execute. The port has been soft-float-only since 2012 (commit `7756ba9d6d`), so the gap has existed the whole time; it simply was never surfaced because the suite was never run on the target.

## What a reviewer should sanity-check (this port)
- `sysdeps/microblaze/math-tests-exceptions.h:23-25` — `EXCEPTION_TESTS_float`/`double`/`long_double` all `0`.
- `sysdeps/microblaze/math-tests-rounding.h:23-25` — `ROUNDING_TESTS_float`/`double`/`long_double` `(MODE) == FE_TONEAREST`. `FE_TONEAREST` is a defined constant on MicroBlaze (see below), so the macro compiles.
- **Placement note (correct, and a deliberate difference from other arches):** these headers sit directly under `sysdeps/microblaze/`, not under a `nofpu/` subdirectory. MicroBlaze has no hard-float variant, so the override is unconditional; the other ports keep hard-float configs alongside and therefore scope theirs under `nofpu/`. Same content, appropriate location.

## How other processors do the same thing
Every soft-float port carries this identical pair (all under `nofpu/` because they also have hard-float builds):
- **exceptions == 0:** `sysdeps/riscv/nofpu/math-tests-exceptions.h:25-27`, `sysdeps/loongarch/nofpu/math-tests-exceptions.h:24-26`, `sysdeps/or1k/nofpu/math-tests-exceptions.h:25-27`, `sysdeps/arc/nofpu/math-tests-exceptions.h:23-25`, `sysdeps/arm/nofpu/math-tests-exceptions.h:25-27`. MicroBlaze's values match exactly.
- **rounding == FE_TONEAREST:** `sysdeps/arc/nofpu/math-tests-rounding.h:23-25`, `sysdeps/riscv/nofpu/math-tests-rounding.h:23-25`, `sysdeps/loongarch/nofpu/math-tests-rounding.h:23-25`, `sysdeps/or1k/nofpu/math-tests-rounding.h:24-26`, `sysdeps/arm/nofpu/math-tests-rounding.h:25-27`. Identical form. (nios2 has no such headers, contrary to a first guess — it is not soft-float-only in this tree.)

## Same-processor code that does related logic
The override is correct only because MicroBlaze really has no exceptions and only one rounding mode:
- `sysdeps/microblaze/bits/fenv.h:33` — `#define FE_ALL_EXCEPT 0` (no `FE_INVALID`/`FE_DIVBYZERO`/… defined at all).
- `sysdeps/microblaze/bits/fenv.h:28-30` — the only rounding enum is `FE_TONEAREST` (`0x1`); comment: "MicroBlaze supports only round-to-nearest."
- `sysdeps/microblaze/Implies` — `ieee754/soft-fp`, confirming the soft-float FP path and generic `fesetround` stub the commit message cites.

## Other cross-checks
`math/libm-test-support.c`'s `test_exceptions` / `assert (ran == 1)` is the exact abort site the README records for the 933 failures; the harness reads `EXCEPTION_TESTS_*` and `ROUNDING_TESTS_*` to decide which classes to run. The two headers are the standard, minimal way to feed it a soft-float profile.

## How to verify on real hardware
This is not a runtime bug — nothing a normal MicroBlaze program does changes with or without the patch. The only "verification" is the testsuite itself: build glibc for `microblazeel-linux` and run `make check subdirs=math` on the board (or under qemu). Unpatched, 933 libm tests abort with SIGABRT at the `assert (ran == 1)` in `math/libm-test-support.c`; patched, `math/` completes with 0 failures. No standalone C reproducer exists because user code never trips the assert — only the test harness reads these headers.
