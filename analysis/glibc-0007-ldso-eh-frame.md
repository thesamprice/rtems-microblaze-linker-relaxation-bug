<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# glibc 0007: terminate `ld.so`'s `.eh_frame`

**Patch:** `glibc-longjmp-chk/patches/0007-elf-terminate-ld-so-eh_frame.patch`
**Target:** `glibc.git` at base commit `10ed541` (2026-08-25); built in the glibc-cfi tree
**Files touched:** `elf/Makefile`
**Status:** independent; not sent upstream (Assisted-by trailer, list-ready)

## What it does
`ld.so` is linked from `librtld.os` alone, so unlike `libc.so` and every other
shared object glibc builds it never gets `sofini.os`, the object whose sole job
is a zero-length CFIE that terminates `.eh_frame`. Its `.eh_frame` therefore
ends in the last FDE's CFI opcodes with no terminator (on MicroBlaze:
`05 9c 04 9d 03 9f 01 00`). The patch builds an rtld flavour of that object,
`rtld-sofini.os`, from `sofini.c` and links it last into `ld.so`
(`elf/Makefile`, new `libof-rtld-sofini := rtld` rule and the `$(objpfx)ld.so:`
dependency). `sofini.os` as built for libc cannot be reused: `symbol-hacks.h`
gives it undefined `__GI_memcpy`-style references that `ld.so` does not define
and `-z defs` rejects.

## Upstream audit: is this already fixed?
**No — still open, and generic.** Current `elf/Makefile` on `bminor/glibc`
master links `ld.so` as `$(objpfx)ld.so: $(objpfx)librtld.os $(ld-map)` — no
`rtld-sofini.os`, no terminator, and `rtld-sofini` appears nowhere (verified by
fetch, 2026-09-04). `sofini.os` is built and listed in `extra-objs`, but
`Makerules:604-676` only appends it to the normal shared-object link
("`sofini.os` must be placed last since it terminates .eh_frame section"), a
path `ld.so` does not take. So every target's `ld.so` has an unterminated
`.eh_frame` today; the change is not MicroBlaze-specific.

## Why it survived so long unpatched
The gap is latent everywhere and only bites MicroBlaze. On other targets
`ld.so` has an `.eh_frame_hdr` binary-search table, so the unwinder finds FDEs
by table lookup and never walks `.eh_frame` linearly past its end. MicroBlaze
cannot have that table: GCC uses `DW_EH_PE_aligned` pointers in PIC code and ld
refuses to build the search table for that encoding ("FDE encoding ... prevents
.eh_frame_hdr table being created"). libgcc then falls back to
`linear_search_fdes`, which stops only at a zero-length entry — so it runs off
the end of the unterminated section into whatever is mapped next and aborts in
`read_encoded_value_with_base` on a garbage encoding (`0xff`). MicroBlaze is
simply the first port here to unwind *through* `ld.so` and hit the missing
terminator.

## What a reviewer should sanity-check (this port)
- The new object is a distinct rtld build of the *same* source: rule
  `$(objpfx)rtld-sofini.os: sofini.c` with `libof-rtld-sofini := rtld`
  (`elf/Makefile`), not a reuse of `sofini.os`.
- It is linked **last**: `rtld-sofini.os` follows `librtld.os` in the
  `$(objpfx)ld.so:` prerequisites, so its zero terminator lands at the end of
  the merged `.eh_frame` (order matters; a mid-section terminator is useless).
- The `-z defs` sanity check that follows the link still passes — the point of
  the rtld flavour is that it carries no `__GI_*` undefined references.

## How other processors do the same thing
Every target gets `.eh_frame` terminated the same way for its *DSOs*:
`Makerules:604,608,669,676` append `sofini.os` last to each shared object.
`crtend`/`crtn` provide the equivalent terminator for ordinary executables and
DSOs linked with the normal crt files; `ld.so` is linked
`-nostdlib -nostartfiles` and gets neither, which is exactly why it needs its
own. The reason other targets do not *notice* the missing `ld.so` terminator is
the `.eh_frame_hdr` table, not a different terminator — so there is no
per-arch precedent that already fixes `ld.so`; this is a first.

## Same-processor code that does related logic
The frame that trips the walk is `__libc_start_main`'s return address, which
`_dl_start_user` sets to `_dl_fini - 8` — inside `ld.so`. So any
`_Unwind_Backtrace` or forced unwind that reaches `main` walks into `ld.so`'s
`.eh_frame` (`elf/tst-unwind-main`). This patch is what makes the MicroBlaze
CFI/backtrace work (glibc 0005/0006, binutils 0006/0007, gcc 0001) actually
complete rather than abort; see `glibc-longjmp-chk/README.md` "Round three".

## Other cross-checks
- The unterminated bytes are visible with `readelf -x .eh_frame ld.so` (or
  `objdump --dwarf=frames ld.so`): before the patch the last CFIE is not a
  4-byte zero length; after, it is.
- Because it is generic, a reviewer could reasonably propose sending it
  upstream as a target-independent hardening (every `ld.so` benefits), noting
  that only MicroBlaze currently exercises the path.

## How to verify on real hardware
On a Linux MicroBlaze host: (1) `readelf --wide -x .eh_frame $(prefix)/lib/ld.so`
and confirm the section ends in a 4-byte zero length record after the patch,
not in CFI opcodes. (2) Build and run `elf/tst-unwind-main`; it aborts in
`read_encoded_value_with_base` before the patch and passes after. (3) Any
`_Unwind_Backtrace` from a normal program that unwinds through `main`/`ld.so`
completes instead of aborting.
