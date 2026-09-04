<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. -->

# binutils 0008: keep the canonical PLT address for function-pointer equality

**Patch:** `patches/binutils/0008-bfd-microblaze-canonical-plt-pointer-equality.patch`
**Target:** `binutils-gdb` at base commit `b7da195b94b` (2.47.50.20260805, master snapshot ~2026-08-05)
**Files touched:** `bfd/elf32-microblaze.c` (`microblaze_elf_finish_dynamic_symbol`)
**Status:** independent; not sent upstream (patches/binutils/README.md:38)

## What it does
In a non-PIC executable that takes the address of a function defined in a
shared library, the linker builds a PLT entry for it and must leave the PLT
address as the value of the executable's undefined symbol, so `ld.so` treats
that PLT stub as the symbol's *canonical* address and resolves every reference
in the process — the library's own, and `dlsym` — to it. MicroBlaze already
records `pointer_equality_needed` in `check_relocs` and points the symbol at
the PLT in `allocate_dynrelocs`, but `microblaze_elf_finish_dynamic_symbol`
then zeroed `st_value` unconditionally, so `&strlen` in the executable was its
PLT stub while `dlsym(RTLD_DEFAULT,"strlen")` and every pointer libc handed out
was the real function. The patch keeps the value unless the symbol is only
weakly referenced or never carried a pointer-equality reloc.

## Upstream audit: is this already fixed?
No. The `.patch` pre-image against `b7da195b94b` shows the unconditional
`sym->st_value = 0;` under the comment "Zero the value.", and the container's
build tree (a snapshot of that master) carries the fix only because the patch
is applied to it. `check_relocs` already sets `h->pointer_equality_needed`
(`bfd/elf32-microblaze.c:2610`) upstream — that half predates this patch — but
`finish_dynamic_symbol` never consulted it. The change is MicroBlaze-only and
nobody has touched canonical-PLT handling in this backend; the README notes the
defect is present in the shipped 2.41 toolchain too
(glibc-longjmp-chk/README.md:429). (I could not fetch live HEAD directly —
sourceware gitweb is behind Anubis and the GitHub binutils mirror 404s from
this environment — but the base is only weeks old and no MicroBlaze
canonical-PLT commit exists to supersede it.)

## Why it survived so long unpatched
Nobody exercises C function-pointer equality on a *non-PIC* MicroBlaze
executable linked against a shared libc. It needs the specific triple of
non-PIC main, an address-taken libc function, and a runtime comparison against
`dlsym`/`dladdr`; the glibc testsuite is never run on MicroBlaze, so
`misc/tst-ldbl-errorfptr` and `elf/tst-addr1` (the two tests that catch it)
were never seen to fail. The generic RELA machinery otherwise "works", it just
gives the wrong canonical address.

## What a reviewer should sanity-check (this port)
- `bfd/elf32-microblaze.c:3345-3347`: after `sym->st_shndx = SHN_UNDEF;` the
  guard is `if (!h->ref_regular_nonweak || !h->pointer_equality_needed)
  sym->st_value = 0;` — value is kept only when the symbol is a non-weak
  regular reference *and* pointer equality was flagged.
- `bfd/elf32-microblaze.c:2610`: `check_relocs` sets
  `h->pointer_equality_needed = 1` for `R_MICROBLAZE_64` / `R_MICROBLAZE_32`
  (but not `_64_PCREL`) when `h != NULL && !bfd_link_pic (info)` — i.e. an
  absolute address-taken reference in a non-PIC link. This is the flag the
  guard reads; confirm the reloc types that take a function's address route
  through here.
- `bfd/elf32-microblaze.c:2918-2921`: `allocate_dynrelocs` does
  `h->root.u.def.value = h->plt.offset;` when `!h->def_regular`, i.e. the
  symbol's value already points into `.plt` before `finish_dynamic_symbol`
  runs; the patch simply stops that value being overwritten with 0.

## How other processors do the same thing
- **elf32-arm.c:17120-17131** — the direct model. Byte-for-byte the same
  comment ("Leave the value if there were any relocations where pointer
  equality matters …") and the identical guard
  `if (!h->ref_regular_nonweak || !h->pointer_equality_needed) sym->st_value = 0;`.
  The patch's commit message says "as elf32-arm does"; verified it matches.
  arm sets the flag on `R_ARM_ABS32`/`ABS32_NOI` in an executable
  (`elf32-arm.c:15479`).
- **elfnn-aarch64.c:10121** — same guard verbatim
  (`if (!h->ref_regular_nonweak || !h->pointer_equality_needed)`); flag set at
  `:8133`, and `:3071` also gates keeping the PLT canonical on
  `!h->pointer_equality_needed`.
- **elf32-i386.c:3953** — the same idea with the weaker test
  `if (!h->pointer_equality_needed)` alone (no `ref_regular_nonweak` term),
  flag set at `:1871`/`:1898`. Shows the `ref_regular_nonweak` term is the
  arm/aarch64 refinement MicroBlaze correctly copied rather than the i386 form.

So MicroBlaze now matches the arm/aarch64 conditional exactly; a reviewer can
diff the three guard lines and confirm they are identical.

## Same-processor code that does related logic
The three sites above (`:2610` set, `:2918-2921` point-at-PLT, `:3345-3347`
keep-or-zero) are one chain in the same file and must stay consistent: the flag
is only ever set in a non-PIC link, which is exactly when a canonical PLT
address is meaningful, so the guard cannot wrongly preserve a value in a
`-shared`/PIE link. `h->plt.offset` is the `.plt` slot whose address
`allocate_dynrelocs` stored; `finish_dynamic_symbol` writes the actual PLT
instructions for that slot just above (`:3277` onward).

## Other cross-checks
The ELF gABI / psABI canonical-PLT contract: a non-PIC executable that needs a
function's address gets a PLT entry acting as its address, and the dynamic
symbol's `st_value` = that PLT address is the signal to `ld.so` that this is the
definitive address (see the arm comment, which is the canonical wording across
backends). Interacts with nothing else in this series; independent of 0001-0007
and 0009.

## How to verify on real hardware
Build a **non-PIC** dynamically-linked program (default `-no-pie` is fine; do
not pass `-fPIC`/`-pie`) with the patched `ld`:

```c
#include <assert.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
int main (void) {
  void *d = dlsym (RTLD_DEFAULT, "strlen");
  printf ("&strlen=%p dlsym=%p &puts=%p\n", (void*)&strlen, d, (void*)&puts);
  assert ((void*)&strlen == d);          /* fails on unpatched ld */
  return 0;
}
```

Link with `-ldl`. On the board, unpatched: the assert fires (or the printf
shows `&strlen` = a PLT stub address in the executable while `dlsym` = the libc
address). Patched: the two print equal and the assert passes. A stronger check
is `dladdr(&puts, &info)` returning non-zero with `info.dli_sname == "puts"` —
on the unpatched linker `dladdr` on the PLT address finds no symbol (this is
the `elf/tst-addr1` failure). No qemu/docker needed; a stock MicroBlaze Linux
userland with `libdl` suffices.
