<!-- Per-patch analysis. Reviewer-facing. path:line citations are into the
     patched glibc tree at /src/glibc-cfi (base 10ed541ad145, 2026-08-25). -->

# glibc 0005: add CFI to the MicroBlaze assembly sources

**Patch:** `glibc-longjmp-chk/patches/0005-microblaze-asm-cfi.patch`
**Target:** glibc (`sourceware.org/git/glibc.git`) at base commit `10ed541ad145` (2026-08-25)
**Files touched:** `config.h.in`, `sysdeps/microblaze/{sysdep.h, configure, configure.ac, start.S, dl-trampoline.S, _mcount.S}`, `sysdeps/unix/sysv/linux/microblaze/{clone.S, setcontext.S, syscall_cancel.S, sysdep.h}`
**Status:** ready — from patches README (round two + a round-three correction; depends on binutils 0006). Not yet sent.

> **History (this session).** After the `main`-branch merge, the cancellation
> branch's tail-call fix (`patches/glibc/0002`, make `__syscall_cancel_arch`
> tail-call `__syscall_do_cancel`) supersedes this patch's `syscall_cancel.S`
> hunk for the cancel frame — a tail call leaves no frame to unwind, so no CFI is
> needed there. The rest of this patch's CFI (`start.S`, `dl-trampoline.S`,
> `_mcount.S`, `clone.S`, the syscall-error handler) is still wanted for general
> unwinding and backtraces. See [MERGE-AUDIT.md](MERGE-AUDIT.md) zone D.

## What it does
No hand-written MicroBlaze assembly in glibc carries unwind info: `ENTRY`/`END`
emitted no `cfi_startproc`/`cfi_endproc`, and the frame-building routines
(`_dl_runtime_resolve`, `_mcount`, the PIC syscall-error handler) described
nothing. Any unwind reaching such a frame stops there. Concretely,
`pthread_cancel` with `-fexceptions` cleanup unwinds out of
`__syscall_cancel_arch` and the handlers never run (`nptl/tst-cancelx4`:
"cleanup handler not called"), and `elf/tst-unwind-main` aborts because `_start`
has no FDE marking it outermost. The reason none of this was ever added is that
gas rejected `.cfi_*` for MicroBlaze ("CFI is not supported for this target").
This patch (a) adds a configure probe `libc_cv_microblaze_asm_cfi` →
`HAVE_MICROBLAZE_ASM_CFI` and makes the `cfi_*` macros expand to nothing when
gas can't take them (`sysdeps/microblaze/sysdep.h:44-63`), (b) emits
`cfi_startproc`/`cfi_endproc` from `ENTRY`/`END` (`sysdep.h:34,39`), (c)
describes the frames of `_dl_runtime_resolve`/`_dl_runtime_profile`, `_mcount`,
and the reentrant PIC `SYSCALL_ERROR_HANDLER`, and (d) terminates the unwind
chain (`cfi_undefined (r15)`) in `_start`, the `clone` child, and
`__startcontext`. It depends on gas support from binutils patch 0006.

## Upstream audit: is this already fixed?
No. Upstream master `sysdeps/microblaze/sysdep.h` still defines
`ENTRY(name)` as globl/type/align/label/`CALL_MCOUNT` with **no**
`cfi_startproc`, and `END(name)` as just `ASM_SIZE_DIRECTIVE(name)`; there is no
mention of `cfi_startproc`, `cfi_endproc`, or `HAVE_MICROBLAZE_ASM_CFI` anywhere
in the file (verified against the GitHub `bminor/glibc` master mirror). No
`libc_cv_microblaze_asm_cfi` probe exists. The MicroBlaze asm is still
unwind-information-free upstream. Genuinely open.

## Why it survived so long unpatched
Two reinforcing reasons. gas literally could not assemble `.cfi_*` for
MicroBlaze until binutils gained the support (patch 0006), so no one could add
CFI even if they wanted to — and because there was no CFI, no unwinder ever
walked through libc's asm frames, so the breakage was invisible. It only
surfaces when you run the nptl cancellation tests and the unwind/backtrace tests
(`tst-unwind-main`, `tst-backtrace*`, `tst-cancelx*`), which are never run on
real MicroBlaze (build-many-glibcs only compiles). The port has been this way
since it landed (glibc 2.18, 2013).

## What a reviewer should sanity-check (this port)
- **DWARF constants.** MicroBlaze return-address column is **15** and
  `RETURN_ADDR_OFFSET` is **8**: r15 holds the address of the caller's `brlid`,
  and return is `rtsd r15,8` (past the branch + its delay slot). Confirmed by
  `sysdeps/microblaze/__longjmp.S:31,50` (`lwi r15,r5,16` then `rtsd r15,8`) and
  `setjmp.S:39`. binutils 0006 encodes exactly this: CFA = r1 offset 0
  (`cfi_add_CFA_def_cfa (1, 0)`), return column r15, data alignment -4 (see
  `patches/binutils/0006-gas-microblaze-cfi-directives.patch:61,129-135`).
- **The cancel-path fix (the crux).** `syscall_cancel.S:56-65`: on the
  cancellation branch, before `brlid r15,__syscall_do_cancel` clobbers r15, the
  code now does `addik r1,r1,-8; cfi_adjust_cfa_offset (8); swi r15,r1,0;
  cfi_rel_offset (r15, 0)`. Without this, the FDE says the return address is in
  r15, the CFA does not move across the call, and the unwinder resolves the
  `brlid`'s own address and loops forever — this broke 31 nptl cancellation
  tests in the first CFI version (README round three). Check that the frame is
  established *before* the branch and that the offset (r15 at CFA-8) matches.
- **Unwind terminators.** `start.S:44` `cfi_undefined (r15)` (kernel entry, no
  caller — r15 is undefined per `ELF_PLAT_INIT` zeroing regs), `clone.S:63`
  (child has no caller), `setcontext.S:89` in `__startcontext` (outermost frame
  of a makecontext context). Each stops the walk instead of chasing a bogus RA.
- **Macro gating.** `sysdep.h:44-63`: when `HAVE_MICROBLAZE_ASM_CFI` is not
  defined every `cfi_*` macro is `#undef`'d and redefined empty, so the sources
  stay uniform and still assemble on pre-2.46 gas. `ENTRY` unconditionally emits
  `cfi_startproc` (`sysdep.h:34`), which becomes a no-op in that case.
- **Frame descriptions.** `dl-trampoline.S:29-52` and `:60-83`
  (`cfi_adjust_cfa_offset (40)`, `cfi_rel_offset (r15, 0)`), `_mcount.S`
  (`cfi_adjust_cfa_offset (4*24)`, `cfi_rel_offset (r15, 4*10)`), and the
  reentrant `SYSCALL_ERROR_HANDLER` in `.../microblaze/sysdep.h:131-149`
  (adjust +16, r15 at 0, r20 at 8, restores + adjust -16). Verify each
  offset equals the corresponding `swi ... r1,off`.

## How other processors do the same thing
- **ENTRY emits cfi_startproc** on essentially every CFI-carrying port:
  `sysdeps/or1k/sysdep.h:33,38`, `arm/sysdep.h:99,107`, `sh/sysdep.h:42,47`,
  `aarch64/sysdep.h:94,127`, `csky/sysdep.h:32,37`, `arc/sysdep.h:32,37`. The
  MicroBlaze change (`sysdep.h:34,39`) is the same pattern. or1k is the closest
  recent port.
- **The cancel-path pattern is universal** and is the direct oracle for the
  crux fix — every port saves the return-address register into a frame before
  calling `__syscall_do_cancel`, with CFI:
  - riscv `.../riscv/syscall_cancel.S:60-64`: `addi sp,sp,-16;
    cfi_def_cfa_offset (16); REG_S ra,(16-SZREG)(sp); cfi_offset (ra,-SZREG);
    call __syscall_do_cancel`.
  - arc `.../arc/syscall_cancel.S:50-54`: `push_s blink; cfi_def_cfa_offset (4);
    cfi_offset (31,-4); bl @__syscall_do_cancel`.
  - or1k `.../or1k/syscall_cancel.S:56-62` keeps r9 saved across the call with
    `cfi_remember_state`/`cfi_restore_state`.
  MicroBlaze (`syscall_cancel.S:60-63`) is line-for-line the riscv/arc shape:
  adjust CFA, store RA reg, `cfi_rel_offset`, then branch.
- **makecontext trampoline terminator.** riscv `.../riscv/setcontext.S:104`
  uses `cfi_register (ra, s0)` (s0==0) to end the chain in `__start_context`;
  MicroBlaze uses `cfi_undefined (r15)` in `__startcontext` (`setcontext.S:89`)
  for the same purpose.

## Same-processor code that does related logic
- `sysdeps/microblaze/setjmp.S` / `__longjmp.S`: the r15 + `rtsd r15,8` return
  convention the CFI (return column 15, offset 8) must match. glibc's
  cancellation fallback also uses this setjmp/longjmp path, which is exactly
  what previously masked the missing-FDE bug (the walk ended and glibc longjmp'd
  out) until the FDE was added.
- `setcontext.S:86-107` (`__startcontext`, from patch 0004): 0005 adds its
  `cfi_undefined (r15)` terminator (`setcontext.S:89`). The two patches are
  coupled — the terminator only matters because 0004 introduced the trampoline.
- `start.S` and `clone.S`: `_start`/child are the other two frames with no
  caller; consistent treatment (`cfi_undefined (r15)`).

## Other cross-checks
- **Depends on binutils 0006** (`patches/binutils/0006-gas-microblaze-cfi-directives.patch`):
  gas must accept `.cfi_*` with CFA=r1, return column r15, data alignment -4.
  Its testsuite dump (`:129-136`) shows precisely the encoding this patch's
  cancel frame produces (`def_cfa r1 ofs 0`, `def_cfa_offset 8`,
  `offset r15 at cfa-8`). Without 0006, `HAVE_MICROBLAZE_ASM_CFI` stays undefined
  and every `cfi_*` is a no-op, so the patch is safe but inert.
- **Interacts with gcc 0001** (`patches/gcc/0001-libgcc-microblaze-signal-frame-glibc-layout.patch`):
  full cancellation/backtrace through a signal frame also needs libgcc's
  `MD_FALLBACK_FRAME_STATE_FOR` fix (in gcc master, not gcc 14). CFI here makes
  libc's own frames walkable; the signal frame is a separate libgcc concern.
- **Interacts with binutils 0007 / glibc 0007** (README round three): once gas
  FDEs exist in `libc.so`, the `.eh_frame` static-reloc and `ld.so`
  `.eh_frame` terminator bugs surface; those are separate patches.

## How to verify on real hardware
No qemu/docker needed. On a Linux MicroBlaze board with the patched libc (and,
for the signal-frame leg, the patched libgcc):

1. **Cancellation cleanup** — proves the unwinder now walks through
   `__syscall_cancel_arch` and runs cleanup handlers instead of looping/hanging:

```c
#define _GNU_SOURCE
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
static void cleanup (void *arg) { puts ("cleanup ran"); }  /* must print */
static void *worker (void *arg) {
  char buf[1];
  pthread_cleanup_push (cleanup, 0);
  read (0, buf, 1);          /* blocks: a cancellation point */
  pthread_cleanup_pop (0);
  return 0;
}
int main (void) {
  pthread_t t; void *r;
  pthread_create (&t, 0, worker, 0);
  sleep (1);
  pthread_cancel (t);
  pthread_join (t, &r);
  printf ("joined, canceled=%d\n", r == PTHREAD_CANCELED);
  return 0;
}
```

  Compile the worker TU with `-fexceptions`. Expected: `cleanup ran` /
  `joined, canceled=1`, and the process exits promptly. On the unpatched libc it
  hangs (unwinder loops on the `brlid`'s own address on the cancel path) or the
  cleanup never prints.

2. **C++ exception through a libc callback** — proves an exception propagates
   across a libc frame that now has an FDE:

```cpp
#include <cstdlib>
#include <cstdio>
extern "C" int cmp (const void *a, const void *b) {
  throw 42;                         /* unwind out through qsort (libc) */
}
int main () {
  int v[4] = {4,3,2,1};
  try { qsort (v, 4, sizeof (int), cmp); }
  catch (int e) { printf ("caught %d\n", e); return 0; }   /* must reach here */
  puts ("no catch"); return 1;
}
```

  Expected: `caught 42`. This is a cross-libc-unwind smoke test: the throw must
  propagate back through the `qsort` call frame in libc. qsort itself is C (so
  already CFI-covered), but on first call the path also crosses the lazy-bind
  resolver `_dl_runtime_resolve` — a hand-written asm frame that was
  undescribed before this patch; with `-z lazy` (where supported) the unpatched
  libc can `std::terminate` there instead of catching. Pair it with test 1,
  which exercises the guaranteed-asm cancel frame directly.
