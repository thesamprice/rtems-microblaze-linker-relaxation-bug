<!-- Per-patch analysis. Cite code as path:line. -->

# glibc 0001: `____longjmp_chk` is a do-nothing stub, so every fortified `longjmp` hangs

**Patch:** `glibc-longjmp-chk/patches/0001-microblaze-Implement-____longjmp_chk-using-the-gener.patch`
**Target:** glibc (`sourceware.org/git/glibc.git`) at base commit `10ed541ad145` (2026-08-25)
**Files touched:** adds `sysdeps/microblaze/jmpbuf-offsets.h`; deletes `sysdeps/unix/sysv/linux/microblaze/____longjmp_chk.S`
**Status:** sent upstream to Neal Frager (AMD), Cc Gopi Kumar Bulusu, 2026-09-01; not yet on libc-alpha.

## What it does
`____longjmp_chk` is the machine half of `__longjmp_chk`, the routine `longjmp`/`siglongjmp` resolve to under `_FORTIFY_SOURCE`. On MicroBlaze it has been a two-instruction stub since the 2012 port: `rtsd r15,0; nop`. It never restores the jump buffer, and `rtsd r15,0` returns to the *call* instruction rather than past its delay slot (normal return is `rtsd r15,8`), so `__longjmp_chk` calls the stub, the stub returns into the call, and they ping-pong forever at 100% CPU. The patch deletes the stub and adds `sysdeps/microblaze/jmpbuf-offsets.h` defining `JB_FRAME_ADDRESS(buf)` via `_jmpbuf_sp`, which makes the sysdeps search select the generic C `____longjmp_chk` instead — exactly what riscv, loongarch, or1k and arc do.

## Upstream audit: is this already fixed?
Not fixed. Verified against the `bminor/glibc` `master` mirror (sourceware cgit is behind Anubis bot-blocking and returns 403 to WebFetch):
- `sysdeps/unix/sysv/linux/microblaze/____longjmp_chk.S` on master is still the stub — two entries (`__revisit_longjmp_chk`, `____longjmp_chk`), each just `rtsd r15,0; nop`, no jump-buffer restore.
- `sysdeps/microblaze/jmpbuf-offsets.h` on master returns HTTP 404 — the file does not exist upstream, so the generic C version is never selected and the stub still wins the sysdeps search.

## Why it survived so long unpatched
The stub landed with the port (commit `7756ba9d6d`, "MicroBlaze Port", David Holsgrove, 2012) and has only had copyright bumps since; it is byte-identical in the AMD/Xilinx glibc fork. MicroBlaze's only CI is `build-many-glibcs.py`, which compiles but never runs the suite. The three default tests that exercise this path (`debug/tst-longjmp_chk`, `tst-longjmp_chk2`, `tst-longjmp_chk3`, all built `-D_FORTIFY_SOURCE=1`) have apparently never been run on the target; on an unpatched cross build under qemu-user all three time out.

## What a reviewer should sanity-check (this port)
- `sysdeps/microblaze/jmpbuf-offsets.h:21-22` — includes `<jmpbuf-unwind.h>` and defines `JB_FRAME_ADDRESS(buf) ((void *) _jmpbuf_sp (buf))`. This is the only symbol the generic version needs from the arch.
- The generic consumer `sysdeps/unix/sysv/linux/____longjmp_chk.c:36-37`: `this_frame = __builtin_frame_address (0)` vs `saved_frame = JB_FRAME_ADDRESS (env)`, then the `called_from` / `sigaltstack` frame checks. It requires `JB_FRAME_ADDRESS`, `_STACK_GROWS_DOWN` and `INTERNAL_SYSCALL_CALL`, all of which MicroBlaze already has.
- Deleting the `.S` is what lets the search fall through to the generic `.c` — confirm no other MicroBlaze makefile still references `____longjmp_chk` as an object.

## How other processors do the same thing
There are two upstream idioms; MicroBlaze now uses the modern one.
- **loongarch** `sysdeps/loongarch/jmpbuf-offsets.h:22` — `JB_FRAME_ADDRESS(buf) ((void *) _jmpbuf_sp (buf))`, byte-identical to the new MicroBlaze line, and loongarch carries **no** `____longjmp_chk.S`. This is the strongest single oracle.
- **riscv** `sysdeps/riscv/jmpbuf-offsets.h:22-23` — same `_jmpbuf_sp` form, no `.S`.
- **or1k** `sysdeps/or1k/jmpbuf-offsets.h:22`, **arc** `sysdeps/arc/jmpbuf-offsets.h:19,22` (`JB_SP 1`, `buf[JB_SP]`) — same pattern, no `.S`.
- Counter-examples that keep a hand-written checked longjmp with `CHECK_SP`: `sysdeps/unix/sysv/linux/arm/____longjmp_chk.S`, `sysdeps/unix/sysv/linux/csky/abiv2/____longjmp_chk.S`, `sysdeps/sh/____longjmp_chk.S`. Both approaches are valid; the C route is what the newer ports pick and is easier to keep correct.

## Same-processor code that does related logic
`_jmpbuf_sp` must return the saved stack pointer, i.e. the `JB_SP` slot.
- `sysdeps/microblaze/bits/setjmp.h:33` — the `__jmp_buf` struct's first member is `int *__sp; /* dedicated name for r1 */`, so SP lives at offset 0.
- `sysdeps/microblaze/setjmp.S:35` — `swi r1,r5,0` stores r1 (SP) into that offset-0 slot; `sysdeps/microblaze/__longjmp.S:27` — `lwi r1,r5,0` restores it.
- `sysdeps/microblaze/jmpbuf-unwind.h:35-37` — `_jmpbuf_sp (regs)` returns `(uintptr_t) regs[0].__sp`, i.e. exactly that saved SP. So `JB_FRAME_ADDRESS` yields the setjmp caller's frame, which is what the generic check compares against `__builtin_frame_address(0)`.

## Other cross-checks
`sysdeps/microblaze/Implies` gives `_STACK_GROWS_DOWN` semantics via the generic Linux stack config, and `INTERNAL_SYSCALL_CALL` (for the `sigaltstack` query in the generic `.c`) is already provided. The AMD/Xilinx fork carries the identical stub, so every fortify-enabled PetaLinux/Buildroot MicroBlaze rootfs inherits the hang; Gopi has reported it to AMD.

## How to verify on real hardware
No qemu/docker needed. On a `microblazeel-linux` board:
1. Minimal reproducer, compile with fortify on:
   ```c
   #include <setjmp.h>
   #include <stdio.h>
   static jmp_buf b;
   int main(void){
     if (setjmp(b)==0){ puts("calling longjmp"); longjmp(b,1); }
     puts("OK: setjmp returned after longjmp");
     return 0;
   }
   ```
   `gcc -O2 -D_FORTIFY_SOURCE=2 t.c -o t`. On an unpatched libc it prints `calling longjmp` and hangs at 100% CPU forever; on a patched libc it prints the `OK:` line and exits 0. Building the same source with `-U_FORTIFY_SOURCE` always returns, which isolates the fault to the checked path.
2. Real-world witness: run a native `gdb` (it defines `_FORTIFY_SOURCE=2` for itself and `longjmp`s out of readline on any error) and trigger one error at the prompt. Unpatched gdb spins forever; patched gdb reports the error and returns to the prompt.
