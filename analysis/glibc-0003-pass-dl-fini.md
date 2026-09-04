<!-- Per-patch analysis. Cite code as path:line. -->

# glibc 0003: `_start` passes null `rtld_fini`, so no destructor runs in a dynamic MicroBlaze program

**Patch:** `glibc-longjmp-chk/patches/0003-microblaze-pass-dl_fini-to-libc_start_main.patch`
**Target:** glibc (`sourceware.org/git/glibc.git`) at base commit `10ed541ad145` (2026-08-25)
**Files touched:** `sysdeps/microblaze/start.S`
**Status:** independent; sent to Neal Frager as part of the 3-patch set on 2026-09-02; not yet on libc-alpha.

## What it does
`__libc_start_main`'s 6th argument, `rtld_fini`, is the finalizer the dynamic linker wants registered with `atexit`; it is `_dl_fini`. MicroBlaze's `_start` has always passed `0` there (`addk r10,r0,r0`). The dynamic linker does hand `_dl_fini` over — `_dl_start_user` leaves `_dl_fini - 8` in r15 before jumping to `_start` — but `_start` never looked at r15. The patch reads r15: if non-zero it computes `rtld_fini = r15 + 8 = _dl_fini`; if zero (kernel-started, all registers cleared by `ELF_PLAT_INIT`) it passes 0.

Since glibc 2.34 (commit `035c012e32`, "Reduce the statically linked startup code [BZ #23323]", which stopped passing `__libc_csu_fini`), `_dl_fini` is the *only* thing that runs a dynamically linked program's destructors. So with `rtld_fini` null, **nothing runs**: no `__attribute__((destructor))`, no `.fini_array`, no DSO `_fini`. Static programs are unaffected (`call_fini` handles them); before 2.34 only DSO destructors were lost.

## Upstream audit: is this already fixed?
Not fixed. Verified against the `bminor/glibc` `master` mirror (sourceware cgit Anubis-blocked): `sysdeps/microblaze/start.S` on master still sets the 6th argument with `addk r10,r0,r0` in the delay slot of `brid __libc_start_main`, with no reference to r15 and no `beqid r15` guard. The bug is live on master for every dynamically linked MicroBlaze program.

## Why it survived so long unpatched
Destructors silently not running is invisible unless you look for their output. It only becomes a *hard* failure since 2.34, and only the testsuite exposes it: `elf/tst-array{1,2,4}-cmp`, `tst-initorder*-cmp`, `order-cmp` (missing "fini" lines), all 111 mtrace `*-mem` tests (leaked memory because atexit cleanup never runs), and the 47 `tst-dso-ordering` tests ("should not return here"). As with 0001/0002, `build-many-glibcs` only compiles, so no one saw the failures. The zeroed `r10` dates to the 2012 port (`7756ba9d6d`); the *consequence* widened to all destructors at 2.34.

## What a reviewer should sanity-check (this port)
In the patched `sysdeps/microblaze/start.S`:
- The guard: `beqid r15,1f` then delay-slot `addk r10,r0,r0` (no rtld_fini), else `addik r10,r15,8` (`rtld_fini = _dl_fini`). r15 arrives holding `_dl_fini - 8`, so `+8` recovers `_dl_fini`.
- The zero-means-kernel assumption: MicroBlaze's `ELF_PLAT_INIT` (`arch/microblaze/include/uapi/asm/elf.h`) zeroes every GP register at exec, and qemu-user does the same, so a zero r15 reliably identifies a kernel-launched process with no rtld_fini. This is the crux of the safety argument.
- The register move: the old code set `r10` in the branch delay slot; the patch moves the rtld_fini computation before the `brid` and now fills the delay slot with the `r9` (unused "fini") clear instead. Confirm the delay slot is still a valid single instruction in both the SHARED and non-SHARED arms.

## How other processors do the same thing
Every arch whose `_start` receives the finalizer in a register from the dynamic linker threads it straight into `__libc_start_main`'s `rtld_fini` slot — MicroBlaze's r15 convention is the same idea:
- **riscv:** `_dl_start_user` loads it with `sysdeps/riscv/dl-machine.h:128` `lla a0, _dl_fini`; `sysdeps/riscv/start.S:51` `mv a5, a0  /* rtld_fini. */`.
- **arm:** `sysdeps/arm/dl-machine.h:165` `.word _dl_fini(GOTOFF)` (left in a1); `sysdeps/arm/start.S:89` `push { a1 }  /* Push rtld_fini */`.
- **sh:** `sysdeps/sh/dl-machine.h:185-186` `.long _dl_fini@GOT`; passed as the rtld_fini arg per the comment at `sysdeps/sh/start.S:79`.
- **or1k:** `sysdeps/or1k/start.S:63` "Pass in rtld_fini from dl-start.S".

The difference is only the register/ABI: those use the ordinary argument register; MicroBlaze uses r15 by its own `_dl_start_user` convention (a return from `_start` would land in `_dl_fini`).

## Same-processor code that does related logic (the crux)
The patch is correct iff r15 really holds `_dl_fini - 8` at `_start`. `sysdeps/microblaze/dl-machine.h`, `_dl_start_user`:
- `dl-machine.h:139` — `addik r15,r20,_dl_fini@GOTOFF` (r20 is the GOT base; r15 = `_dl_fini`).
- `dl-machine.h:140` — `addik r15,r15,-8` (r15 = `_dl_fini - 8`).
- `_dl_start_user` then falls through / jumps to the program entry (`_start`) with r15 in that state.

So the dynamic linker sets `r15 = _dl_fini - 8`; the patched `_start` does `addik r10,r15,8 = _dl_fini`. Exact round-trip. The `-8`/`+8` is the MicroBlaze branch-delay-slot return offset, matching `rtsd rX,8` semantics used throughout the port.

## Other cross-checks
Commit `035c012e32` is what makes this a total-destructor failure rather than a DSO-only one; a reviewer weighing severity should note the pre-2.34 vs post-2.34 split. The static path is provably unaffected because `call_fini` (in `elf/dl-fini.c` / static startup) runs `.fini_array` independently of `rtld_fini`.

## How to verify on real hardware
No qemu/docker needed. On a `microblazeel-linux` board, build this and run it **dynamically linked**:
```c
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void ctor(void){ puts("constructor ran"); }
__attribute__((destructor))  static void dtor(void){ puts("destructor ran"); }
static void at(void){ puts("atexit ran"); }
int main(void){ atexit(at); puts("main ran"); return 0; }
```
`gcc dtor.c -o dtor` (dynamic). Unpatched libc prints `constructor ran` / `main ran` but **neither** `atexit ran` nor `destructor ran`; patched libc prints all four. The static build (`gcc -static`) prints all four either way — that contrast confirms the fault is specifically the dynamic `rtld_fini` handoff, not the destructor machinery.
