<!-- Per-patch analysis. Follows analysis/TEMPLATE.md. Cite code as path:line. -->

# gas 0006: accept `.cfi_*` directives for MicroBlaze

**Patch:** `patches/binutils/0006-gas-microblaze-cfi-directives.patch`
**Target:** `binutils-gdb` master at base commit `6f24afa4391b` (`2026-08-31`); upstream audited against master `193340ad3e08` (`2026-09-04`)
**Files touched:** `gas/config/tc-microblaze.c`, `gas/config/tc-microblaze.h`, `gas/testsuite/gas/microblaze/cfi.{s,d,exp}`
**Status:** independent; not sent upstream (patches README, row 0006)

> **History (this session).** After the `main`-branch merge this superseded the
> cancellation branch's second gas CFI patch: 0006 was kept for its testsuite
> and its `tc_regname_to_dw2regnum` (so `.cfi_offset r15` works with register
> names), and the duplicate was dropped — see
> [MERGE-AUDIT.md](MERGE-AUDIT.md) zone A. The reworked series builds and passes
> the MicroBlaze gas suite on current master `193340ad3` ([REWORK.md](REWORK.md)).

## What it does
MicroBlaze is one of the few ELF targets whose assembler rejects `.cfi_*` with "CFI is not supported for this target", because `tc-microblaze.h` never defined `TARGET_USE_CFIPOP`. GCC hides this by writing its own `.eh_frame`, but hand-written assembly (all of glibc's MicroBlaze asm) then carries no unwind information, so `_Unwind_Backtrace` and `-fexceptions` cleanup handlers stop at the first assembler frame. The patch turns on `TARGET_USE_CFIPOP` and supplies the three CFI hooks with the values GCC already uses for this ABI: the CFA is r1, the return-address column is 15, and the CIE data-alignment factor is -4.

## Upstream audit: is this already fixed?
Still open. The current upstream `gas/config/tc-microblaze.h` (master `193340ad3e08`, fetched 2026-09-04) contains none of `TARGET_USE_CFIPOP`, `DWARF2_CIE_DATA_ALIGNMENT`, `DWARF2_DEFAULT_RETURN_COLUMN`, `tc_cfi_frame_initial_instructions`, or `tc_regname_to_dw2regnum`. The current `tc-microblaze.c` has neither `microblaze_cfi_frame_initial_instructions` nor `microblaze_regname_to_dw2regnum` nor any `cfi_add_CFA_def_cfa` call. With `TARGET_USE_CFIPOP` undefined, `md_cfi_startproc` is a no-op and the parser emits the "not supported" error, so the feature is absent, not merely wired differently.

## Why it survived so long unpatched
Nothing on MicroBlaze ever exercised assembler CFI. GCC emits its own frame tables regardless of gas support, so compiled code always had unwind info; only hand-written assembly is affected, and no MicroBlaze `.S` file in glibc or the kernel ever used `.cfi_*` (they could not — the assembler rejected them). The gap was invisible until pthread cancellation and `_Unwind_Backtrace` were run against real MicroBlaze glibc, which is what `glibc-longjmp-chk/README.md` ("Round three") documents. It is a never-wired-up feature, not a regression.

## What a reviewer should sanity-check (this port)
- `gas/config/tc-microblaze.h:123` `TARGET_USE_CFIPOP 1` — enables the whole `.cfi_*` machinery.
- `gas/config/tc-microblaze.h:125` `DWARF2_DEFAULT_RETURN_COLUMN 15` — r15 is the link register; `rtsd r15, 8` is MicroBlaze's return instruction, and GCC's `DWARF_FRAME_RETURN_COLUMN` is likewise 15. The `+8` in `rtsd r15,8` (the delay-slot return offset) is unwind-neutral: the column names the register, not the offset.
- `gas/config/tc-microblaze.h:124` `DWARF2_CIE_DATA_ALIGNMENT -4` — the negative word size, so `DW_CFA_offset r15` in units of -4 encodes a save at `cfa-8` from `.cfi_rel_offset r15, 0` after an 8-byte frame, exactly the `cfi.d` expectation.
- `gas/config/tc-microblaze.c:401` `microblaze_cfi_frame_initial_instructions` calls `cfi_add_CFA_def_cfa (1, 0)` — initial CFA is the incoming r1 with offset 0, matching `DW_CFA_def_cfa: r1 ofs 0` in `cfi.d`.
- `gas/config/tc-microblaze.c:410` `microblaze_regname_to_dw2regnum` maps `r0..r31` (and `R0..R31`) to 0..31 and rejects anything else — the only registers with DWARF numbers on this target.
- `cfi.d` expects CIE `Return address column: 15`, `Data alignment factor: -4`, augmentation `zR`; confirm the FDE covers `pc=0..0x10` for the 4-instruction body.

## How other processors do the same thing
- `gas/config/tc-riscv.c:5797` `riscv_cfi_frame_initial_instructions` is `cfi_add_CFA_def_cfa (X_SP, 0)` — byte-for-byte the shape of MicroBlaze's `cfi_add_CFA_def_cfa (1, 0)`; RISC-V's data alignment is also -4 (`tc-riscv.h:129`). The closest structural comparator.
- `gas/config/tc-csky.h:62-63` uses `DWARF2_DEFAULT_RETURN_COLUMN 15` and `DWARF2_CIE_DATA_ALIGNMENT (-4)` — an independent 32-bit RISC target that lands on the same two constants MicroBlaze uses, so (15, -4) is not unusual.
- `gas/config/tc-sparc.h:172` also uses return column 15, with `sparc_cfi_frame_initial_instructions` doing `cfi_add_CFA_def_cfa (14, ...)` at `tc-sparc.c:4942` — shows the return column and the CFA register are chosen independently.
- `gas/config/tc-or1k.c:396` `or1k_cfi_frame_initial_instructions` is `cfi_add_CFA_def_cfa_register (1)` — OpenRISC also makes r1 the CFA register; note or1k defines no `tc_regname_to_dw2regnum`, so unlike MicroBlaze its users must write `.cfi_offset` with bare numbers.
- `gas/config/tc-riscv.c:5803` `tc_riscv_regname_to_dw2regnum` is the fuller pattern (ABI names, FPR offset +32); MicroBlaze's numeric-only `r%u` map is the minimal correct form.

## Same-processor code that does related logic
- GCC `gcc/config/microblaze/microblaze.h` defines `DWARF_FRAME_RETURN_COLUMN` as 15 (cited in the patch's commit message); the gas value must equal it or gas- and GCC-generated `.eh_frame` disagree on the return column.
- `gas/config/tc-microblaze.c:2470` `md_pcrel_from_section` and the existing `R_MICROBLAZE_*_PCREL` howtos define what "PC-relative" means on this target; patch 0009 is what lets the FDE pointers these CFI directives emit become PC-relative rather than absolute.
- The MicroBlaze ABI return-address offset (`rtsd r15, 8`, `RETURN_ADDR_OFFSET`) is the reason column 15 is correct; the test's `rtsd r15, 8` exercises it.

## Other cross-checks
- Interacts with patch 0009: once `DIFF_EXPR_OK` is defined there, `dw2gencfi.c:31-37` derives `CFI_DIFF_EXPR_OK 1` from it, so these same FDE pointers switch to `DW_EH_PE_pcrel`; that is why `cfi.d`'s augmentation byte changes from `0b` to `1b` in 0009.
- glibc side: `glibc-longjmp-chk/README.md` ("Round three", correction to 0005) records that a wrong FDE on `__syscall_cancel_arch` made the unwinder loop; the assembler CFI has to describe r15 correctly for cancellation to terminate.
- DWARF register numbering is the psABI's; only r0..r31 are assigned, which is why the regname map rejects everything else.

## How to verify on real hardware
On a Linux host with a real `microblazeel-linux` toolchain built with this patch:
1. Assemble a `.S` with `.cfi_startproc`/`.cfi_def_cfa`/`.cfi_offset r15,-8`/`.cfi_endproc` and confirm it assembles (pre-patch it errors "CFI is not supported for this target").
2. `readelf -wf a.o` and confirm a CIE with `Return address column: 15`, `Data alignment factor: -4`, and an FDE covering the function.
3. Build a small C program that calls a hand-written assembly routine which itself calls a C callback, and run `_Unwind_Backtrace` (or a C++ `throw` through the asm frame) on the board; confirm the backtrace passes through the assembly frame instead of stopping at it.
