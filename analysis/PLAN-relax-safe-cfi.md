# Plan: CFI and DWARF that survive MicroBlaze linker relaxation

Status (2026-11-01): A–D are written, plus one patch the plan missed (readelf,
below), as `patches/binutils/0008`–`0012` on the `binutils-relax-cfi` branch of
`microblaze-testsuite`, on top of the seven binutils patches in review. Not
sent. The relocation numbers 36–43 are provisional until question 0 is
answered. E and F are not written.

Measured 2026-11-01 against binutils master `19c3a4c4` and gcc master
`da8eaee29`, built by `microblaze-testsuite`.

### As written

| patch | plan | notes |
|---|---|---|
| 0008 `microblaze: add ADD, SUB and SET relocations` | A | 8 types, numbers 36–43; `info_to_howto`/`relocate_section` now reject the 34–35 gap |
| 0009 `microblaze: adjust ADD and SUB relocations when relaxing` | B | |
| 0010 `readelf: apply MicroBlaze ADD, SUB and SET relocations` | new | without it three gas tests fail: readelf warns about unknown types when dumping `.o` DWARF |
| 0011 `gas: microblaze: emit ADD and SUB for code label differences` | C | field zeroed (MicroBlaze applies the symbol value); `TC_FORCE_RELOCATION_SUB_LOCAL` deliberately not copied |
| 0012 `gas: microblaze: emit CFA advances as relocations` | D | ADD on a zeroed field instead of RISC-V's SET8/16/32, so no extra types |

Measured with the series against the seven in-review patches alone, test by
test: gas 331→332, ld 486→490, binutils 245→245. The only differences are the
five new tests, and there are no failures on either side.

End to end through `microblaze-testsuite` (gcc master plus `__moddi3`, no
gcc-0002), `check-gcc-smoke`: 106 passes, 0 failures, 8 unsupported, both with
`--no-relax` and with relaxation on. Relaxation used to make every execution
test report status 2 (the `--wrap` bug, fixed by binutils 0006).

## Why: the CFI patches are not correct under `-relax` as they stand

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so every normal
link deletes `imm` prefixes. Every **difference between two code labels** that
gas resolves at assembly time goes stale when an `imm` between the two labels
is deleted. MicroBlaze gas resolves all of them, so nothing ever tells ld that
those differences need adjusting:

```
$ cat d.s        # .4byte b - a   (globals)   .4byte .Lx - .Ly   (locals)
$ readelf -r d.o
There are no relocations in this file.
```

Three measured consequences:

1. **GCC's own `.eh_frame`/`.debug_frame` today.** `f` in a small test
   (`-O2 -g`, three calls and a global load, all relaxable) is 0x50 bytes after
   relaxation. Its FDE still says `pc=00000304..00000368`, 0x64 bytes, which
   runs into `g` at 0x354. GCC writes `.4byte $LFE0-$LFB0`, and gas froze it.
2. **Line tables and `addr2line` today.** In the same link the `t.c` line
   table has rows at 0x354 and 0x360 after the end of `f`.
   `addr2line -f 0x358` (inside `g`) answers `f`. GCC writes the line table
   itself (`microblaze.h`: `DWARF2_ASM_LINE_DEBUG_INFO 0`) using
   `.uleb128 $LM2-$LM1`, and the location lists use the same form.
3. **The outbox CFI patches (`outbox/binutils/0003` + `0004`).** gas with
   both applied, on a hand-written function using `.cfi_*` with two relaxable
   calls:

   ```
                 relaxed (imm deleted)        --no-relax
   rtsd at       0x101c                       0x1024
   ra restored   0x1024   <- inside g         0x1024
   FDE           0x1000..0x102c <- covers g   0x1000..0x102c
   ```

   `dw2gencfi.c` computes each `DW_CFA_advance_loc` in an `rs_cfa` frag at
   assembly time (`dw2gencfi.c:1714`), and the FDE length is a same-section
   difference that gas folds to a constant.

So 0003/0004 are no worse than what GCC emits today, but they are not
correct either. GCC's configure sets `HAVE_GAS_CFI_DIRECTIVE` once gas
accepts `.cfi_*`, but GCC only uses them with gcc-0002 (see "GCC
follow-ups"). Hand-written assembly with `.cfi_*` (glibc 0008) hits this
path as soon as 0003 lands.

Repro sources: `microblaze-testsuite` scratch, to be turned into the ld
tests below (`relax-cfi.s`, `relax-fde-range.s`).

## The design to borrow

RISC-V had the same problem, since its linker deletes bytes too, and solved it
in gas and bfd without changing the DWARF. LoongArch then copied the same
design, so a reviewer has two working precedents in the tree:

| piece | RISC-V | LoongArch |
|---|---|---|
| keep code-label differences as relocations | `tc-riscv.h:99` `TC_FORCE_RELOCATION_SUB_SAME` for `SEC_CODE` | `tc-loongarch.h:88` |
| split a difference into an ADD/SUB pair | `tc-riscv.c:4989-5060` | yes |
| CFA advances as relocations | `riscv_pre_output_hook`, `tc-riscv.c:5308`, `BFD_RELOC_RISCV_CFA` cases `tc-riscv.c:5042-5114` | `loongarch_pre_output_hook` |
| line-table advances as relocations | `tc-riscv.h:138` `DWARF2_USE_FIXED_ADVANCE_PC 1` | `tc-loongarch.h:103` |
| the relocation types | `elfxx-riscv.c:497-748` (ADD8..64, SUB6..64, SET6..32) | `elfxx-loongarch.c` ADD/SUB/SUB6 |
| ULEB128 differences | `R_RISCV_SET_ULEB128`/`SUB_ULEB128`, `elfxx-riscv.c:796-811` | `R_LARCH_ADD_ULEB128`/`SUB_ULEB128` |

What does **not** need borrowing: RISC-V keeps label symbols and moves them,
while MicroBlaze's relax already rewrites the addend of any relocation against
the relaxed section's section symbol, using `calc_fixup()`
(`elf32-microblaze.c`, the "Look through all other sections" loop). An
ADD/SUB pair against `.text+N` gets corrected by that same loop, with one more
`case` each. That keeps the bfd side small.

Why the pre-chosen sizes stay valid: relaxation only deletes bytes, so a
difference can only shrink. If gas picked `DW_CFA_advance_loc` (6 bits) or
`advance_loc1`, the relaxed value still fits. RISC-V relies on the same fact.

## The series

Each patch builds and passes the testsuite on its own, changes one thing,
comes with a test, and where it copies code says from where, so a reviewer
can diff it, as was done for the `--wrap` patch.

### 0. RFC, no code: relocation numbers

MicroBlaze relocs stop at `R_MICROBLAZE_32_NONE = 33`. The new types need
numbers, which are ABI. Before writing anything, ask Michael Eager and Neal
Frager (AMD) whether AMD's downstream binutils (the 64-bit MicroBlaze work)
already uses numbers above 33, and agree a block. **Not yet checked**; AMD's
GitHub binutils fork is where to look first. Also ask whether they would
accept these always-on (open question 1).

Proposed names follow RISC-V: `R_MICROBLAZE_ADD8/16/32`, `SUB8/16/32`,
`SUB6`, `SET6`. 8 types.

### A. bfd: add the ADD/SUB relocation types (no producer yet)

- `include/elf/microblaze.h`, `bfd/reloc.c` (+ regenerated `bfd-in2.h`,
  `libbfd.h`), howtos, `microblaze_elf_reloc_type_lookup`, and the arithmetic
  in `microblaze_elf_relocate_section`.
- Nothing emits them yet, so no existing output changes; the whole-suite
  comparison should show zero status changes.
- Test: `ld-microblaze/diff-relocs.{s,d}` written with `.reloc . ,
  R_MICROBLAZE_ADD32, sym` (`microblaze_elf_reloc_name_lookup` already
  exists), checking the linked bytes.
- Review recipe: the howtos side by side with `elfxx-riscv.c:497-748`; the
  arithmetic with `riscv_elf_relocate_section`'s ADD/SUB cases.

### B. bfd: relaxation adjusts the new relocations

- Add the eight types to both loops in `microblaze_elf_relax_section`: this
  section's relocs, and other sections' relocs against this section's
  section symbol. Each is a `calc_fixup()` on the addend, as for
  `R_MICROBLAZE_32`.
- Test: `ld-microblaze/relax-diff.{s,d,ld}`, a `.reloc` pair spanning a
  deleted `imm`, checked at the value relaxed and unrelaxed. Fixed addresses
  via a linker script, as the `relax-wrap` test does.
- Lands with the `binutils-relax` pair in review, since it touches the same
  function. Rebase onto them, and say so in the cover letter.

### C. gas: emit an ADD/SUB pair for differences of code labels

- `tc-microblaze.h`: `TC_FORCE_RELOCATION_SUB_SAME` for `SEC_CODE` (verbatim
  from `tc-riscv.h:99`), `TC_FORCE_RELOCATION_SUB_LOCAL`.
- `md_apply_fix`: split `BFD_RELOC_8/16/32` with an `fx_subsy` into the pair
  (from `tc-riscv.c:4989-5060`).
- `cons_fix_new_microblaze` currently picks `R_MICROBLAZE_32_SYM_OP_SYM` when
  the subtrahend is not local. Route code-label differences to the pair
  instead and leave `SYM_OP_SYM` for whatever is left. Its relax arm is dead
  code (already noted in `patches/binutils/README.md`), so the cover letter
  must say what, if anything, still produces it.
- **This is the patch that fixes GCC's output with no GCC change:** FDE
  lengths, `advance_loc4` deltas, `DW_AT_high_pc` lengths.
- Tests: gas dump of the pair; ld test reproducing finding 1 (FDE range after
  relaxation). Re-run gcc `execute.exp` through the DejaGnu board as an end to
  end check. A frame table that is wrong in another way shows up as EH test
  failures.

### D. gas: CFA advances as relocations (needs `0003`)

- `microblaze_pre_output_hook` and an internal `BFD_RELOC_MICROBLAZE_CFA`
  (not an ELF reloc), copied from `riscv_pre_output_hook` and the
  `BFD_RELOC_RISCV_CFA` handling in `md_apply_fix`. Each `rs_cfa` frag
  becomes SET6/SUB6, ADD8/SUB8, ADD16/SUB16 or ADD32/SUB32 depending on the
  advance form gas chose.
- Test: `ld-microblaze/relax-cfi.{s,d}`, finding 3 exactly. Expect the
  restore row at 0x101c and the FDE ending at 0x1024.
- With A–D, `outbox/binutils/0003`/`0004` become correct under relaxation.
  `0004`'s FDE *start* (`R_MICROBLAZE_32_PCREL` against `.text`) is already
  adjusted by relax, and D fixes the length and advances.

### E. gas: `DWARF2_USE_FIXED_ADVANCE_PC` (optional for the CFI goal)

- One line from `tc-riscv.h:138`. Line tables gas generates from `.loc`
  (hand-written assembly with `-g`) use `DW_LNS_fixed_advance_pc` with an
  ADD16/SUB16 pair.
- Unblocks a gcc patch that drops `DWARF2_ASM_LINE_DEBUG_INFO 0` from
  `microblaze.h`, so GCC uses `.loc` and gas owns the line table. That fixes
  finding 2 for line tables without the ULEB128 relocs.

### F. (second series) ULEB128 differences

- `R_MICROBLAZE_SET_ULEB128`/`SUB_ULEB128`, after RISC-V and LoongArch. Needed
  for `.debug_loclists`/`.debug_rnglists` (`.uleb128 $LVL2-1-$Ltext0`) and
  for GCC's own line table if E's gcc patch is not taken.
- Kept separate because it is not needed for CFI, it adds two more reloc
  numbers, and its relax handling has to re-encode in place without changing
  the length.

### GCC follow-ups (gcc-patches, after binutils lands)

- **`gcc-0002` (PC-relative EH encodings) is required for GCC to use
  `.cfi_*` at all**, not just configure. Measured: with 0001-0012 in gas,
  configure sets `HAVE_GAS_CFI_DIRECTIVE 1`, but GCC still writes its own
  `.debug_frame`/`.eh_frame`. `dwarf2out_do_cfi_asm` (`dwarf2cfi.cc`) returns
  false when `ASM_PREFERRED_EH_DATA_FORMAT (2, 1)` is neither absolute nor
  PC-relative, and MicroBlaze returns `DW_EH_PE_aligned` there. Without
  gcc-0002, C fixes GCC's tables and D only affects hand-written `.cfi_*`.
- Optionally drop `DWARF2_ASM_LINE_DEBUG_INFO 0` once E is in a release.

## Order and dependencies

```
in review:  binutils-relax 1/2, 2/2        outbox/binutils 1/5..5/5 (CFI = 3/5, pcrel = 4/5)
                  |                                   |
            0 (RFC numbers) ──> A ──> B ──> C ──> D (needs 3/5) ──> E      F later
```

A–D are one series of four (with E as a fifth if it stays small), sent after
the RFC is answered. Each one is reviewable alone:

| | touches | rough size (estimate) | the reviewer checks |
|---|---|---|---|
| A | include, bfd | ~150 lines, mostly howtos | fields match RISC-V; no output changes |
| B | bfd | ~20 | one `case` group per loop |
| C | gas | ~60 | diff against `tc-riscv.c`; the `SYM_OP_SYM` story |
| D | gas, bfd/reloc.c | ~80 | diff against `riscv_pre_output_hook` |
| E | gas | 1 + test | — |

Suggested change to the CFI patch now in review: add a sentence to 3/5's
cover letter saying FDE lengths and advances are fixed at assembly time, which
is wrong under `-relax`, the same as GCC's own tables today, and that a
follow-up series fixes both. A reviewer who finds this themselves will wonder
what else was missed.

## Open questions

1. **Always on, or behind an option?** RISC-V emits pairs only when relaxing
   (`-mrelax`, default on). MicroBlaze gas has no such option and ld relaxes by
   default. Always on is simplest. The cost is larger `.rela.eh_frame` and
   `.rela.debug_*` in objects, not in linked images. Measure it on newlib
   before the RFC.
2. **Objects from older gas** keep frozen differences. Nothing can fix those;
   say so in the cover letter.
3. **CIE code alignment factor** is 1 on MicroBlaze (`cf=1` above). With 4-byte
   instructions, 4 would let more advances use the 1-byte form. That changes the
   CIE GCC and gas emit, and it is a separate question that should not ride along.
4. **`R_MICROBLAZE_32_SYM_OP_SYM`:** does anything still produce it after C?
   If not, its handling can be documented as legacy or removed, in a separate
   patch.
