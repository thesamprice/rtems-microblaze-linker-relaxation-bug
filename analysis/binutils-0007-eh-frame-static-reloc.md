<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# bfd 0007: apply the relocation statically when the `.eh_frame` editor returns -2

**Patch:** `patches/binutils/0007-bfd-microblaze-eh-frame-static-reloc.patch`
**Target:** `binutils-gdb` master at base commit `6f24afa4391b` (`2026-08-31`); upstream audited against master `193340ad3e08` (`2026-09-04`)
**Files touched:** `bfd/elf32-microblaze.c`
**Status:** independent; not sent upstream (patches README, row 0007)

> **History (this session).** Applies cleanly to current binutils master; the
> reworked series builds and passes the gas/ld suites ([REWORK.md](REWORK.md)),
> and the round-four full rebuild confirmed the read-only `.eh_frame` plus
> `.eh_frame_hdr` table end to end.

## What it does
When linking a shared object, `_bfd_elf_section_offset` returns `(bfd_vma) -2` for an `R_MICROBLAZE_32` in `.eh_frame` whose FDE the `.eh_frame` editor is re-encoding as PC-relative: no dynamic relocation is wanted, but the absolute target value must still be written into the section so the editor can turn it into a delta. Every backend that supports this returns "skip the dynamic reloc, but relocate the field in place"; `elf32-microblaze.c` only skipped. On a RELA target the addend lives in the relocation, not the field, so the field kept its assembled value of zero and `_bfd_elf_write_section_eh_frame` produced a PC-relative pointer to address 0. The fix sets `relocate = true` on the -2 branch and writes `relocation + addend` into the field with `bfd_put_32`.

## Upstream audit: is this already fixed?
Still open. In the current upstream `bfd/elf32-microblaze.c` (master `193340ad3e08`, fetched 2026-09-04) the `microblaze_elf_relocate_section` copy-reloc block reads `if (outrel.r_offset == (bfd_vma) -1) skip = true; else if (outrel.r_offset == (bfd_vma) -2) skip = true;` — the -2 arm sets only `skip`, there is no `relocate` local and no `bfd_put_32` afterwards. That is byte-identical to the base commit and to the pre-patch state this patch rewrites. The defect is present upstream today.

## Why it survived so long unpatched
GCC-generated MicroBlaze frames never reach this path. GCC's `ASM_PREFERRED_EH_DATA_FORMAT` picks `DW_EH_PE_aligned` (absolute pointers) for PIC MicroBlaze, and the `.eh_frame` editor leaves aligned encodings alone — which is also why every MicroBlaze DSO ships a writable `.eh_frame` full of `R_MICROBLAZE_REL` dynamic relocations and no `.eh_frame_hdr` table. Only assembler-generated FDEs, using the default `sdata4` encoding, get re-encoded and hit the -2 case. Since MicroBlaze gas rejected `.cfi_*` until patch 0006, no such FDE ever existed, so no shared object ever exercised the branch. It was dead code that happened to be wrong.

## What a reviewer should sanity-check (this port)
- `bfd/elf32-microblaze.c:1663-1671` — the `else if (outrel.r_offset == (bfd_vma) -2)` now sets `skip = true, relocate = true`; the comment explains the RELA-addend reasoning.
- `bfd/elf32-microblaze.c:1709-1710` — after the `outrel` is written, `if (relocate && r_type == R_MICROBLAZE_32) bfd_put_32 (input_bfd, relocation + addend, contents + offset);`. Confirm the guard is `R_MICROBLAZE_32` only (the sole absolute 32-bit type routed through this block) and that `relocation + addend` is the final resolved value, so the editor computes a correct `target - pc` delta.
- `relocate` is initialised `false` at the top of the block, so the ordinary dynamic-reloc paths (`-1` skip, live copy relocs) are unchanged; only the -2 case now also writes the field.
- MicroBlaze is RELA (`bfd/elf32-microblaze.c:3604` `elf_backend_rela_normal 1`, and `USE_RELA` at `:31`), which is exactly why the field was zero and the write is needed.

## How other processors do the same thing
- `bfd/elf32-sh.c:3876-3877` is the model: `else if (outrel.r_offset == (bfd_vma) -2) skip = true, relocate = true;` — identical idiom, same two-token statement, in the same copy-reloc block shape.
- Seventeen ELF backends in this tree carry the `skip = true, relocate = true` idiom: `elf32-arm.c`, `elf32-cris.c`, `elf32-i386.c`, `elf32-m68k.c`, `elf32-metag.c`, `elf32-nds32.c`, `elf32-s390.c`, `elf32-sh.c`, `elf32-tic6x.c`, `elf32-tilepro.c`, `elf32-vax.c`, `elf64-ppc.c`, `elf64-s390.c`, `elf64-x86-64.c`, `elfxx-sparc.c`, `elfxx-tilegx.c`, and (now) `elf32-microblaze.c`. The -2 skip-and-relocate contract is the common one.
- `bfd/elfNN-riscv.c:3175-3178` does the RELA form explicitly: `else if (outrel.r_offset == (bfd_vma) -2) ... relocate = true;`, the closest RELA comparator to MicroBlaze.
- Honest counter-example: `bfd/elf32-or1k.c:1652` sets `else if (outrel.r_offset == (bfd_vma) -2) skip = true;` with no `relocate` — OpenRISC, also RELA, carries the very same omission MicroBlaze had. So "every other backend relocates" is not literally true; or1k is the one peer that shares the bug (and, like MicroBlaze pre-0009, uses aligned PIC eh_frame, so it has not been caught either). The patch's commit message should be read as "the backends that support PC-relative assembler eh_frame", of which `elf32-sh.c` is representative.

## Same-processor code that does related logic
- `bfd/elf32-microblaze.c:1655-1707` is the single copy-reloc emission block for `R_MICROBLAZE_32`/`_64`; the new `bfd_put_32` sits immediately after `bfd_elf32_swap_reloca_out` at `:1707`, so the field write and the (skipped) dynamic reloc are decided together.
- The `.eh_frame` editor that requests -2 is generic (`bfd/elf-eh-frame.c`); the MicroBlaze-specific part is only that the value must be materialised here because the addend is in the RELA entry.
- Patch 0009 is the paired change: it makes gas able to emit `R_MICROBLAZE_32_PCREL` directly, so future frames can be PC-relative from the start; 0007 fixes the case where the editor converts an absolute `R_MICROBLAZE_32` FDE pointer at link time.

## Other cross-checks
- `glibc-longjmp-chk/README.md` ("binutils 0007" paragraph): with CFI in glibc's assembly, every gas FDE in `libc.so` covered `pc=0..size` before this fix; that is the observable symptom.
- ELF `.eh_frame` re-encoding semantics are in the LSB/DWARF eh_frame documentation; the -2 sentinel is `_bfd_elf_section_offset`'s "offset lies in a section being edited" return, documented at its definition in `bfd/elflink.c`.
- Regression surface is limited: the only field ever written is one that the editor immediately overwrites with a delta, so a correct absolute value in, a correct PC-relative value out.

## How to verify on real hardware
On a Linux host with a `microblazeel-linux` toolchain carrying patches 0006/0007 (and, for a fully PC-relative result, 0009):
1. Assemble an object with a `.cfi_*`-bracketed function so it has an assembler FDE with the default `sdata4` encoding.
2. `ld -shared` it into a DSO. Pre-patch: `readelf -wf libx.so` shows the FDE `pc` at `0`. Post-patch: the FDE `pc` equals the function's runtime address.
3. Confirm there is no bogus dynamic relocation pointing into `.eh_frame` for that FDE (`readelf -r`), i.e. the -2 path still suppressed the dynamic reloc while writing the field.
4. Run a C++ `throw`/`catch` or `_Unwind_Backtrace` that unwinds through that DSO's assembler frame on the board and confirm it resolves the frame instead of faulting at address 0.
