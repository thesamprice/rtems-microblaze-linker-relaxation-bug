<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# gas + bfd 0009: `sym - .` across sections, emit and relax `R_MICROBLAZE_32_PCREL`

**Patch:** `patches/binutils/0009-microblaze-pcrel-data-relocs.patch`
**Target:** `binutils-gdb` master at base commit `6f24afa4391b` (`2026-08-31`); upstream audited against master `193340ad3e08` (`2026-09-04`)
**Files touched:** `gas/config/tc-microblaze.c`, `gas/config/tc-microblaze.h`, `bfd/elf32-microblaze.c`, `gas/testsuite/gas/microblaze/reloc_pcrel.{s,d,exp}`, `gas/testsuite/gas/microblaze/cfi.d`
**Status:** independent; needs the gcc patch to matter; not sent upstream (patches README, row 0009)

## What it does
MicroBlaze gas rejects `sym - .` when `sym` is in another section ("operation combines symbols in different segments") because it never defined `DIFF_EXPR_OK`, and that difference is exactly what a PC-relative `.eh_frame` pointer is. So neither GCC nor the CFI directives could use `DW_EH_PE_pcrel`; every MicroBlaze DSO shipped a writable `.eh_frame` with one `R_MICROBLAZE_REL` per FDE (711 in `libc.so`) and no `.eh_frame_hdr` search table. The patch defines `DIFF_EXPR_OK`, teaches `cons_fix_new_microblaze` to emit `R_MICROBLAZE_32_PCREL` for `sym - .`, lets `tc_gen_reloc` honour `fx_pcrel` on a 32-bit fixup, clears the erroneous `partial_inplace` on the `R_MICROBLAZE_32_PCREL` howto (a RELA target must not rewrite the addend), and extends the relaxation addend-adjustment loop to that relocation so FDE pointers survive `-relax`.

## Upstream audit: is this already fixed?
Still open, all four pieces. In master `193340ad3e08` (fetched 2026-09-04):
- `gas/config/tc-microblaze.h` does not define `DIFF_EXPR_OK`.
- `cons_fix_new_microblaze` (upstream `tc-microblaze.c:2585`) has only the `BFD_RELOC_MICROBLAZE_32_SYM_OP_SYM` arm for `O_subtract`; there is no `R_MICROBLAZE_32_PCREL` / cross-section arm.
- `tc_gen_reloc` lists `BFD_RELOC_32` in the plain pass-through case (`code = fixp->fx_r_type`) with no `fx_pcrel` test.
- The `R_MICROBLAZE_32_PCREL` howto is still `partial_inplace = true` (upstream `elf32-microblaze.c:82`), the only PCREL howto in the table set that way, on a RELA target.
- The relaxation loop (upstream `elf32-microblaze.c:2128-2129`) adjusts only `R_MICROBLAZE_32` and `R_MICROBLAZE_32_NONE`; `R_MICROBLAZE_32_PCREL` is absent. The whole feature is unimplemented upstream.

## Why it survived so long unpatched
Nothing ever generated `R_MICROBLAZE_32_PCREL`. GCC chose `DW_EH_PE_aligned` for PIC precisely because the assembler could not express `sym - .` across sections, so the relocation type existed in the howto table but no code path emitted it — which is how a wrong `partial_inplace` flag sat there unnoticed. MicroBlaze is described in `glibc-longjmp-chk/README.md` ("Round four") as the last Linux target still using aligned PIC eh_frame. The `.eh_frame_hdr`-less linear FDE walk it caused was a performance and correctness cost nobody paid attention to until unwinding was actually run on the target.

## What a reviewer should sanity-check (this port)
- `gas/config/tc-microblaze.h:115` `#define DIFF_EXPR_OK` — accepts the expression and, via `gas/dw2gencfi.c:31-37`, sets `CFI_DIFF_EXPR_OK 1` so `.cfi_*` FDE pointers become PC-relative too (this is why `cfi.d`'s augmentation flips `0b`→`1b`).
- `gas/config/tc-microblaze.c` `cons_fix_new_microblaze` new arm — matches `O_subtract` with the subtrahend being the current location (`X_op_symbol` in `now_seg`, same frag, value `fr_address + where`) and the minuend in another section, then `fix_new (..., 1, BFD_RELOC_32_PCREL)` with the plain addend. Confirm the same-section case still folds to a constant (the test's `p - .` in `.rodata` does).
- `gas/config/tc-microblaze.c:2507` `code = fixp->fx_pcrel ? BFD_RELOC_32_PCREL : BFD_RELOC_32;` — `BFD_RELOC_32` was moved out of the pass-through list into its own case so a PC-relative 32-bit fixup maps to the PCREL relocation.
- `bfd/elf32-microblaze.c:82` `false, /* Partial Inplace. */` on the `R_MICROBLAZE_32_PCREL` howto — the load-bearing one-liner. With `partial_inplace` true, `bfd_install_relocation` rewrites the addend as "addend − offset", so `sym - . + 100` at a nonzero field offset came out short by that offset.
- `bfd/elf32-microblaze.c:2141` adds `|| ELF32_R_TYPE (irelscan->r_info) == R_MICROBLAZE_32_PCREL` to the group that runs `irelscan->r_addend -= calc_fixup (...)` when relaxation deletes an `imm` before the target; without it, FDE pointers into a relaxed section go stale.
- `reloc_pcrel.d` expects `R_MICROBLAZE_32_PCREL` with addends `f+0`, `.text+0x8`, `f+0x64` for `f - .`, `.Lloc - .`, `f - . + 100`.

## How other processors do the same thing
- `gas/config/tc-riscv.h:105` `DIFF_EXPR_OK 1` plus `tc-riscv.h:102` `TC_FORCE_RELOCATION_SUB_LOCAL(FIX,SEG) 1`, feeding `R_RISCV_32_PCREL` (`elfNN-riscv.c:2128`, `:2793`) — the fullest RELA comparator for "`sym - .` becomes a 32-bit PCREL relocation".
- `bfd/elf32-or1k.c:179-191` `R_OR1K_32_PCREL` howto is `pc_relative true`, `partial_inplace false`, `pcrel_offset true`, `dst_mask 0xffffffff` — field-for-field what the MicroBlaze howto should be after this patch, on another RELA target. `gas/config/tc-or1k.h:35` defines `DIFF_EXPR_OK`, and `elf32-or1k.c:868` maps `BFD_RELOC_32_PCREL → R_OR1K_32_PCREL`. The cleanest single citation that the corrected MicroBlaze howto is right.
- `gas/config/tc-sh.h:208` and `gas/config/tc-sparc.h:117` define `TC_FORCE_RELOCATION_SUB_LOCAL`, the guard that keeps `sym - .` from being resolved away when the minuend is local; MicroBlaze instead pins the relocation by constructing it directly in `cons_fix_new_microblaze`, which is sufficient because the eh_frame minuend is a section-relative label.
- Relaxation adjusting PCREL addends: `bfd/elf32-sh.c` (`sh_elf_relax_delete_bytes`, e.g. the addend fix-ups around `:667-688`) and `bfd/elf32-avr.c` (`elf32_avr_relax_delete_bytes`) both walk the relocations that point across a deleted region and correct their addends; MicroBlaze's `calc_fixup`-based loop at `elf32-microblaze.c:2124-2172` is the same technique, and this patch simply adds the PCREL type to the set it corrects.

## Same-processor code that does related logic
- `bfd/elf32-microblaze.c:2124-2172` — the existing relax addend-adjust loop already handled `R_MICROBLAZE_32`, `R_MICROBLAZE_32_NONE` (shared block) and `R_MICROBLAZE_32_SYM_OP_SYM`; `R_MICROBLAZE_32_PCREL` now joins the first block and gets the same `r_addend -= calc_fixup (...)` treatment, keeping it consistent with the absolute-32 case it mirrors.
- `gas/config/tc-microblaze.c:2470` `md_pcrel_from_section` defines the PC anchor for PC-relative fixups; the new `BFD_RELOC_32_PCREL` path relies on it to compute `S + A − P`.
- The other `R_MICROBLAZE_*_PCREL` howtos (`elf32-microblaze.c:88` `R_MICROBLAZE_64_PCREL`, `:103` `R_MICROBLAZE_32_PCREL_LO`) are already `partial_inplace false`; this patch brings `R_MICROBLAZE_32_PCREL` into line with its own PCREL siblings, so the table is now internally consistent.

## Other cross-checks
- Pairs with `patches/gcc/0002-microblaze-pcrel-eh-encodings.patch`, which switches `ASM_PREFERRED_EH_DATA_FORMAT` to `pcrel|sdata4` (`indirect|pcrel|sdata4` for globals); without the binutils change the assembler rejects the expressions GCC would emit. The relocation is inert until that GCC change (or the CFI directives) drives it.
- `glibc-longjmp-chk/README.md` ("Round four") table records the verified outcome: `libc.so` `.eh_frame` 711→0 dynamic relocs and a read-only section with an `.eh_frame_hdr` table after a full rebuild.
- `gas/dw2gencfi.c:43-44` enforces `CFI_DIFF_EXPR_OK ⇒ CFI_DIFF_LSDA_OK`, so defining `DIFF_EXPR_OK` also makes LSDA pointers PC-relative — desirable and consistent, not a surprise.

## How to verify on real hardware
On a Linux host with a `microblazeel-linux` toolchain carrying this patch (and gcc 0002 for the compiler side):
1. Assemble `.4byte f - .` with `f` in `.text` and the datum in `.rodata`; `readelf -r a.o` should show `R_MICROBLAZE_32_PCREL` (pre-patch: assembly error).
2. Compile a `-fexceptions -fPIC` C or C++ translation unit and `ld -shared` it; confirm with `readelf -S` that `.eh_frame` is read-only (flag `A`, not `WA`), `readelf -r` shows zero dynamic relocations in `.eh_frame`, and `readelf -S`/`-wF` shows an `.eh_frame_hdr` with a binary-search table (one entry per FDE).
3. Link with `-Wl,--relax` and confirm the stored FDE deltas are still correct after an `imm` is deleted (compare an FDE's `pc` to the function address).
4. Run a C++ `throw`/`catch` or `_Unwind_Backtrace` that crosses the DSO boundary on the board and confirm it unwinds identically to the old aligned encoding.
