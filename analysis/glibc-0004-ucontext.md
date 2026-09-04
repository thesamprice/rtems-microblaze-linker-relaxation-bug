<!-- Per-patch analysis. Reviewer-facing. path:line citations are into the
     patched glibc tree at /src/glibc-cfi (base 10ed541ad145, 2026-08-25). -->

# glibc 0004: implement getcontext/setcontext/swapcontext/makecontext for MicroBlaze

**Patch:** `glibc-longjmp-chk/patches/0004-microblaze-ucontext.patch`
**Target:** glibc (`sourceware.org/git/glibc.git`) at base commit `10ed541ad145` (2026-08-25)
**Files touched:** `sysdeps/unix/sysv/linux/microblaze/{getcontext.S, setcontext.S, swapcontext.S, makecontext.c, ucontext_i.sym, Makefile}`
**Status:** ready — from patches README (round two, not yet sent)

## What it does
MicroBlaze has never had a real ucontext implementation; it falls through to
the generic ENOSYS stubs (`stdlib/getcontext.c`, `stdlib/makecontext.c`, etc.,
each `__set_errno (ENOSYS)` + `stub_warning`). So `getcontext` returns -1/ENOSYS
and every `stdlib/tst-setcontext*` / `tst-swapcontext*` test fails, and no
coroutine/interpreter that uses ucontext works. This patch adds the four
functions in assembly (getcontext/setcontext/swapcontext) plus a C
`makecontext`, and a `ucontext_i.sym` that computes the struct offsets the asm
needs. The four symbols already exist at `GLIBC_2.18` in the abilist
(`.../microblaze/le/libc.abilist:982,1326,1793,2005` — `getcontext`,
`makecontext`, `setcontext`, `swapcontext`, all `F`), so filling in the bodies
needs no new symbol version.

## Upstream audit: is this already fixed?
No. Current upstream master still has no MicroBlaze ucontext:
- `sysdeps/unix/sysv/linux/microblaze/getcontext.S` → 404 (does not exist).
- `sysdeps/unix/sysv/linux/microblaze/ucontext_i.sym` → 404.
- `sysdeps/unix/sysv/linux/microblaze/makecontext.c` → 404, so MicroBlaze uses
  the generic ENOSYS stub `stdlib/makecontext.c` (verified in-tree: the stub is
  `makecontext (…) { __set_errno (ENOSYS); }` + `stub_warning (makecontext)`).

(Checked via the GitHub `bminor/glibc` master mirror; sourceware git blobs are
behind Anubis and refuse the fetch, but the mirror tracks master.) The port
still ships only the stubs, so the change applies cleanly and is genuinely new.

## Why it survived so long unpatched
The MicroBlaze port landed in glibc 2.18 (2013) with the generic ENOSYS
ucontext stubs and no one ever replaced them — the abilist entries are all
`GLIBC_2.18`. The glibc testsuite is never run on real MicroBlaze
(build-many-glibcs only compiles), so the 13 failing `tst-setcontext*` /
`tst-swapcontext*` cases were never observed. ucontext is also rarely a
build-time dependency, so the missing implementation stayed invisible.

## What a reviewer should sanity-check (this port)
- **Register set saved.** `getcontext.S:30-49` saves exactly the callee-saved
  set the ABI requires: r1(sp), r2, r13, r15(RA), r19-r31, into
  `uc_mcontext + N*4`. This is right because `mcontext_t.regs` is `r0..r31`
  laid out consecutively (`sys/ucontext.h:38-70`, r0 at 38 … r31 at 69, pc at
  70), so `uc_mcontext + N*4` == register N. r3-r12 (caller-saved, incl. return
  value r3) are deliberately not saved.
- **PC slot.** `getcontext.S:49-50` does `addik r3,r15,8; swi r3,r5,MCONTEXT_PC`
  — resume address is r15+8 (the instruction after the caller's brlid + delay
  slot). `ucontext_i.sym:22` defines `MCONTEXT_PC = uc_mcontext + 32*4`, and pc
  is indeed the 33rd word (index 32) after r0..r31 — matches `sys/ucontext.h:70`.
- **setcontext restore order.** `setcontext.S:29` stashes `ucp` in r19 across
  the syscall, restores r5-r10 (makecontext args), then r1/r2/r13/r15/r20-r31,
  loads pc into r12, reloads r19 **last** (`setcontext.S:73`), then `brad r12`
  with `addk r3,r0,r0` in the delay slot so a resumed getcontext returns 0.
  Confirm r19 is reloaded after it is used as the base pointer.
- **makecontext frame.** `makecontext.c:58` `sp -= (argc>6?argc-6:0)+7` reserves
  the 28-byte ABI area (7 words = link slot + 6 arg-home slots) plus overflow
  args, 8-byte aligned; `makecontext.c:61-64` set r1=sp, r15=`&__startcontext-8`
  (so FUNC's `rtsd r15,8` lands on `__startcontext`), r19=uc_link, pc=func;
  args 1-6 go to r5-r10 via `(&regs.r5)[i]` (contiguous per `sys/ucontext.h`),
  args >6 to `sp[7 + i - 6]` (`makecontext.c:71`) just above the 28-byte area.
- **__startcontext trampoline.** `setcontext.S:86-107`: if uc_link (r19) is
  non-null, `setcontext` it; else call `exit`. Two `nop`s precede
  `ENTRY (__startcontext)` (`setcontext.S:83-85`) so an unwinder resolving the
  `__startcontext-8` return address does not land inside `__setcontext`.

## How other processors do the same thing
- **riscv** is the closest structural oracle (its `ucontext_i.sym` is nearly
  identical to MicroBlaze's — same `SIG_BLOCK/SIG_SETMASK/_NSIG8` and
  `UCONTEXT_*` offsets). `sysdeps/unix/sysv/linux/riscv/getcontext.S:24-77`
  saves ra/sp/callee-saved into the gregs array and does the same
  `rt_sigprocmask (SIG_BLOCK, NULL, &uc_sigmask, _NSIG8)`; `getcontext.S:73`
  branches to `__syscall_error` on failure, the analogue of MicroBlaze's
  `bgei r12,SYSCALL_ERROR_LABEL` (`getcontext.S:62`).
- **riscv makecontext** `.../riscv/makecontext.c:42-71`: sets the return-address
  register to 0 and stashes func in a callee-saved reg, uc_link in another, args
  in a0-a7 then overflow on the stack — the same shape as MicroBlaze's
  `makecontext.c`. MicroBlaze differs only in that it seeds r15 to
  `__startcontext-8` rather than jalr-ing func from within the trampoline.
- **riscv __start_context** `.../riscv/setcontext.S:101-115`: on FUNC return it
  loads uc_link into a0 and tail-calls `__setcontext`, else `exit` — identical
  logic to MicroBlaze `__startcontext` (`setcontext.S:86-107`). (The unwind
  terminator here, `cfi_register (ra, s0)` vs MicroBlaze's `cfi_undefined (r15)`,
  is added by patch 0005; see that doc.)
- **or1k** `.../or1k/getcontext.S` uses the shared `__CONTEXT_FUNC_NAME` body
  and the same `rt_sigprocmask` sequence — a second recent-port confirmation.

## Same-processor code that does related logic
- `sys/ucontext.h:34-90`: the authoritative `mcontext_t`/`ucontext_t` layout the
  offsets are computed from. `regs` is `r0..r31` then `pc, msr, ear, esr, fsr,
  pt_mode` — the kernel's `pt_regs` order, which is what the kernel signal frame
  and `ELF_PLAT_INIT` also use, so the saved order is self-consistent with the
  rest of the port. `ucontext_t` is `uc_flags, uc_link, uc_stack, uc_mcontext,
  uc_sigmask` (`sys/ucontext.h:81-88`); `ucontext_i.sym:14-22` derives every
  offset with `offsetof`, so a struct change can't silently desync the asm.
- `sysdeps/microblaze/setjmp.S:39` / `__longjmp.S:31,50`: r15 is the return
  address, restored and returned via `rtsd r15,8`. getcontext/setcontext use the
  same r15+8 resume convention.
- gcc patch `patches/gcc/0001-libgcc-microblaze-signal-frame-glibc-layout.patch`
  reads the kernel `rt_sigframe`, whose `regs` member is the same `pt_regs`
  order — cross-confirms the register ordering this patch relies on.

## Other cross-checks
- The syscall error path uses the existing `SYSCALL_ERROR_LABEL` /
  `SYSCALL_ERROR_HANDLER` from `.../microblaze/sysdep.h`; patch 0005 later adds
  CFI to that handler but does not change its behaviour.
- Interaction with 0005: `__startcontext` gains `cfi_undefined (r15)` there
  (`setcontext.S:89`) so it terminates the unwind chain when a context-started
  function is unwound.

## How to verify on real hardware
No qemu/docker needed. On a Linux MicroBlaze board, compile against the patched
libc and run:

```c
#include <ucontext.h>
#include <stdio.h>
static ucontext_t uctx_main, uctx_func;
static void f (int a, int b) {
  printf ("in f: %d %d\n", a, b);        /* proves args reached r5,r6 */
  swapcontext (&uctx_func, &uctx_main);  /* back to main */
  printf ("f resumed\n");
}
int main (void) {
  static char stack[64*1024];
  if (getcontext (&uctx_func) == -1) { perror ("getcontext"); return 1; }
  uctx_func.uc_stack.ss_sp = stack;
  uctx_func.uc_stack.ss_size = sizeof stack;
  uctx_func.uc_link = &uctx_main;
  makecontext (&uctx_func, (void (*)(void)) f, 2, 11, 22);
  swapcontext (&uctx_main, &uctx_func);  /* into f */
  printf ("back in main\n");
  swapcontext (&uctx_main, &uctx_func);  /* resume f, which returns via uc_link */
  printf ("done\n");
  return 0;
}
```

Expected on the patched libc: `in f: 11 22` / `back in main` / `f resumed` /
`done`. On the unpatched libc `getcontext` returns -1 with `errno==ENOSYS`
(prints `getcontext: Function not implemented`) and exits. That single-run
difference confirms the implementation end-to-end (arg passing, swap, and
uc_link return through `__startcontext`).
