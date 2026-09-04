<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. -->

# gcc 0002: PC-relative encodings for MicroBlaze .eh_frame pointers

**Patch:** `patches/gcc/0002-microblaze-pcrel-eh-encodings.patch`
**Target:** `gcc` master (verified against the live file, ~2026-09)
**Files touched:** `gcc/config/microblaze/microblaze.h`
(`ASM_PREFERRED_EH_DATA_FORMAT`)
**Status:** independent; requires binutils 0009; not sent upstream (glibc-longjmp-chk/README.md:466-470, patches/binutils/README.md:39)

## What it does
`ASM_PREFERRED_EH_DATA_FORMAT` chooses how gcc encodes pointers in `.eh_frame`.
MicroBlaze used `DW_EH_PE_aligned` (absolute pointers) for PIC/global, the last
Linux target still doing so. Absolute pointers force every shared object to
carry a *writable* `.eh_frame` with one dynamic relocation per FDE (711
`R_MICROBLAZE_REL` in glibc `libc.so`), and they make `ld` refuse to build the
`.eh_frame_hdr` binary-search table ("FDE encoding in … prevents
.eh_frame_hdr table being created"), so libgcc linearly walks every FDE of an
object on every unwind. The patch switches to `DW_EH_PE_pcrel | DW_EH_PE_sdata4`
for code pointers and `DW_EH_PE_indirect | DW_EH_PE_pcrel | DW_EH_PE_sdata4` for
global (personality) pointers — the encoding every other ELF target uses. Result:
read-only `.eh_frame`, no dynamic relocations, and a working `.eh_frame_hdr`.

## Upstream audit: is this already fixed?
No. Fetched gcc master live
(`raw.githubusercontent.com/gcc-mirror/gcc/master/gcc/config/microblaze/microblaze.h`):
the macro is still

```c
#define ASM_PREFERRED_EH_DATA_FORMAT(CODE,GLOBAL) \
  ((flag_pic || GLOBAL) ? DW_EH_PE_aligned : DW_EH_PE_absptr)
```

exactly the pre-image the patch rewrites. The container's `microblaze.h:212`
shows the new form only because the patch is applied there. The patched line is:

```c
#define ASM_PREFERRED_EH_DATA_FORMAT(CODE,GLOBAL) \
  (((GLOBAL) ? DW_EH_PE_indirect : 0) | DW_EH_PE_pcrel | DW_EH_PE_sdata4)
```

## Why it survived so long unpatched
Purely an assembler limitation, not a policy choice: gas for MicroBlaze
rejected `sym - .` when `sym` was in another section ("operation combines
symbols in different segments"), and that difference expression is precisely
what a PC-relative `.eh_frame` pointer compiles to. With no assembler support,
`DW_EH_PE_aligned` (absolute + dynamic relocs) was the only thing that worked,
so gcc's port hard-coded it and it was never revisited. binutils 2.46 / patch
0009 adds `R_MICROBLAZE_32_PCREL` support for cross-section `sym - .`, which is
what finally unblocks the normal encoding.

## What a reviewer should sanity-check (this port)
- `gcc/config/microblaze/microblaze.h:212-213`: the new macro. `CODE` (0 data,
  1 code label, 2 function pointer) is unused — every pointer gets
  `pcrel|sdata4`; only `GLOBAL` adds `DW_EH_PE_indirect` (the pointer is stored
  as a GOT-mediated slot because a global/personality symbol may be dynamically
  resolved). This matches the psABI EH convention: pcrel|sdata4 for the FDE/LSDA
  pointers, indirect|pcrel|sdata4 for the personality routine.
- `sdata4` (signed 4-byte) is right for a 32-bit target: the FDE-to-PC delta
  fits in a signed 32-bit displacement.
- The old form keyed on `flag_pic || GLOBAL`; the new form is unconditional
  (same encoding for PIC and non-PIC). Confirm that is intended — pcrel works
  in both, and a uniform encoding is what nios2/riscv/or1k also emit.

## How other processors do the same thing
pcrel|sdata4 (indirect for global) is the near-universal choice; `DW_EH_PE_aligned`
was the MicroBlaze outlier. Verified in the container's (unpatched) gcc tree:

- **gcc/config/riscv/riscv.h:1233-1234** — *identical* to the patched
  MicroBlaze macro:
  `(((GLOBAL) ? DW_EH_PE_indirect : 0) | DW_EH_PE_pcrel | DW_EH_PE_sdata4)`.
- **gcc/config/or1k/or1k.h:414-415** — also identical, same three tokens.
  riscv and or1k are the exact template; a reviewer can diff character-for-
  character.
- **gcc/config/nios2** — no `ASM_PREFERRED_EH_DATA_FORMAT` of its own, so it
  inherits the `DW_EH_PE_absptr` default; not a pcrel comparator, but confirms
  MicroBlaze was unusual in defining `aligned` at all.
- **gcc/config/arm/arm.h:948-950** — the deliberate *exception*, and not a
  counter-example: arm uses its own `.ARM.exidx`/EHABI unwinder, so its macro
  returns `ARM_TARGET2_DWARF_FORMAT` for code labels and `DW_EH_PE_absptr`
  otherwise. Cite it only to show why arm looks different (a different unwinder,
  not a preference for absolute DWARF pointers).

So the correctness oracle is riscv/or1k: MicroBlaze's new macro is textually the
same as theirs.

## Same-processor code that does related logic
This patch is inert without the assembler/linker side:

- **binutils 0009** (`patches/binutils/0009-microblaze-pcrel-data-relocs.patch`,
  see `analysis/binutils-0009-*`): defines `DIFF_EXPR_OK`, makes
  `cons_fix_new_microblaze` emit `R_MICROBLAZE_32_PCREL` for cross-section
  `sym - .`, clears the stray `partial_inplace` on that howto, and teaches
  linker relaxation to adjust `R_MICROBLAZE_32_PCREL` addends. gcc's pcrel
  `.eh_frame` output is exactly these `sym - .` expressions, so **0002 must not
  be applied without 0009** — older assemblers reject the expressions
  (patch header, lines 23-24 / `microblaze.h:210-211`).
- The gas `.cfi_*` directives (binutils 0006) switch to the same PC-relative
  encoding automatically once `DIFF_EXPR_OK` is defined
  (`CFI_DIFF_EXPR_OK` follows it), so hand-written asm FDEs and gcc-emitted
  FDEs end up with the same `0x1b` (pcrel|sdata4) augmentation.

## Other cross-checks
- **DWARF EH augmentation:** with this encoding the CIE augmentation string's
  `R`/`P`/`L` bytes become `0x1b` (pcrel|sdata4) and `0x9b`
  (indirect|pcrel|sdata4); the README records the observed FDE augmentation
  `0x1b` and an `.eh_frame_hdr` table header `011b033b`
  (glibc-longjmp-chk/README.md:476-484), which is the on-disk proof the
  encoding took effect.
- **`HAVE_LD_RO_RW_SECTION_MIXING`:** gcc only emits a read-only `.eh_frame`
  section if configure found this (needs objdump on PATH at configure time);
  otherwise the tables are still pcrel but land in a `WA` section. A read-only
  result therefore also depends on how gcc was configured, not just this macro
  (README caveat, lines 490-497).
- glibc rebuild evidence: `libc.so` `.eh_frame` went 711 dynamic relocs → 0 and
  writable → read-only with the hdr table once rebuilt with the new encoding
  (README table, lines 504-507).

## How to verify on real hardware
Same DSO/unwind check as the binutils EH patches; no qemu/docker:

1. Build a shared object with the patched gcc+binutils and inspect it on any
   host: `readelf -S lib.so` shows `.eh_frame` with flags `A` (not `WA`) and an
   `.eh_frame_hdr` present; `readelf -r lib.so` shows **no** `R_MICROBLAZE_REL`
   entries against `.eh_frame`; `readelf --debug-dump=frames` shows FDE
   augmentation `0x1b`.
2. On the board, an executable that calls `_Unwind_Backtrace` through a
   function in that DSO must report the same frames as with the old encoding
   (the README confirms 7 frames, identical) — i.e. the switch is behaviour-
   preserving for unwinding while removing the dynamic relocs.
3. Cross-check that a C++ program throwing an exception across the DSO boundary
   still catches correctly on the board. Requires the patched glibc `ld.so`
   fixes (0007) for full unwinding, so run against the patched runtime.
