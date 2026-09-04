<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# glibc 0006: MicroBlaze uses the generic unwinder-based `backtrace`

**Patch:** `glibc-longjmp-chk/patches/0006-microblaze-generic-backtrace.patch`
**Target:** `glibc.git` at base commit `10ed541` (2026-08-25); built in the glibc-cfi tree
**Files touched:** `sysdeps/microblaze/Makefile`, `sysdeps/microblaze/backtrace.c` (deleted), `sysdeps/microblaze/backtrace_linux.c` (deleted), `sysdeps/unix/sysv/linux/microblaze/Makefile`
**Status:** independent; not sent upstream (Assisted-by trailer, list-ready)

## What it does
MicroBlaze shipped its own `backtrace()` that walks the stack by scanning
backwards from each return address for an `addik r1,r1,-N` prologue and
treating that as the frame size (`sysdeps/microblaze/backtrace.c`,
`find_frame_creation`). It misfires on any prologue not of that exact shape,
stops after a few frames, and reports `__backtrace` itself as frame 0, so
`debug/tst-backtrace2`/`3` fail with no signal involved. The patch deletes
`backtrace.c` and `backtrace_linux.c` and their two `sysdep_routines +=
backtrace_linux` entries, so MicroBlaze falls back to the generic
`debug/backtrace.c`, which walks with `_Unwind_Backtrace` off GCC's DWARF
unwind tables like every modern port.

## Upstream audit: is this already fixed?
**No — still open.** Current master still carries the arch-specific file:
`sysdeps/microblaze/backtrace.c` on `bminor/glibc` master returns the same
`find_frame_creation` / `addik r1` scanner and `__backtrace` (verified by
fetch, 2026-09-04), and `sysdeps/microblaze/Makefile` still appends
`backtrace_linux` to `sysdep_routines` under `ifeq ($(subdir),resource)`. No
upstream commit has removed them. The port therefore still uses the broken
hand-rolled walker.

## Why it survived so long unpatched
The glibc testsuite is never run on MicroBlaze (build-many-glibcs only
compiles), so `debug/tst-backtrace*` was never observed failing. The scanner
is also "good enough" for a couple of frames of a plain C stack, which is all
a casual `backtrace()` caller sees, so the defect stayed invisible. The file
dates from the original MicroBlaze port and was never revisited when the
generic `_Unwind_Backtrace` path became the norm for new ports.

## What a reviewer should sanity-check (this port)
- The deletion is total: after the patch there is no `backtrace*.c` under
  `sysdeps/microblaze/` and no `backtrace_linux` in either Makefile
  (`sysdeps/microblaze/Makefile`, `sysdeps/unix/sysv/linux/microblaze/Makefile`).
- Nothing else references `_identify_sighandler` (it lived only in the two
  deleted files) — grep the tree to confirm no dangling caller.
- The generic path needs unwind info: confirm GCC emits `.eh_frame` for
  MicroBlaze (it does) and that `debug/backtrace.c:128` reaches
  `_Unwind_Backtrace` via `__libc_unwind_link_get()`.

## How other processors do the same thing
The generic `debug/backtrace.c` is the correctness oracle: it uses
`_Unwind_GetIP`/`_Unwind_GetCFA`/`_Unwind_Backtrace`
(`debug/backtrace.c:82,90,128`). Only four legacy ports still carry a custom
walker — `sysdeps/{arm,i386,m68k,sparc}/backtrace.c`. Every modern port ships
**no** `backtrace.c` and relies on the generic one: `sysdeps/riscv`,
`sysdeps/aarch64`, `sysdeps/nios2`, `sysdeps/or1k`, `sysdeps/csky`,
`sysdeps/loongarch` (verified: no `backtrace.c` in any of those dirs).
Removing MicroBlaze's aligns it with that modern group, not the legacy four.

## Same-processor code that does related logic
Signal-frame unwinding for MicroBlaze now depends on libgcc's
`MD_FALLBACK_FRAME_STATE_FOR` (`libgcc/config/microblaze/linux-unwind.h` in
GCC master), which the deleted `backtrace_linux.c` used to reimplement by
matching the `rt_sigreturn` trampoline. That fallback is fixed by
`patches/gcc/0001-libgcc-microblaze-signal-frame-glibc-layout.patch`; the two
must land together for `debug/tst-backtrace4`–`6` (signal-frame cases) to
pass. See `glibc-longjmp-chk/README.md` "Round three".

## Other cross-checks
- Pairs with glibc 0007 (ld.so `.eh_frame` terminator): a backtrace that walks
  through `ld.so` needs both this and the terminator to complete.
- `tst-backtrace2`/`3` pass with this patch alone; `4`–`6` need the gcc libgcc
  fix; lazy-binding and some signal cases remain gcc-version-gated, per the
  README failure table.

## How to verify on real hardware
On a Linux MicroBlaze host with a glibc built from these patches: compile and
run `debug/tst-backtrace2` and `tst-backtrace3` (or a 5-line program calling
`backtrace()`/`backtrace_symbols()` from a few nested functions). Correct
behaviour: the first entry is the caller of `backtrace`, not `__backtrace`,
and all expected frames appear. With a gcc that has the libgcc signal-frame
fix, `tst-backtrace4`–`6` also complete through the signal frame.
