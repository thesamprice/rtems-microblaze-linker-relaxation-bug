# binutils 0004: write the value for `BFD_RELOC_8`/`BFD_RELOC_16` fixups

**Patch:** `patches/binutils/0004-microblaze-write-the-value-for-BFD_RELOC_8-and-BFD_R.patch`
**Files:** `gas/config/tc-microblaze.c`, `gas/testsuite/gas/all/forward.d`

## What it does
`md_apply_fix` had cases for `BFD_RELOC_32`/`64` and the MicroBlaze-specific
relocs but none for `BFD_RELOC_8` or `BFD_RELOC_16`, so a byte or halfword
datum resolved at fixup time (e.g. `.dc.b L1-L0`) fell through and assembled to
**zero**; the fixup then became `BFD_RELOC_NONE`, so no relocation survived to
correct it either. The patch adds the two cases, modelled on the existing
`BFD_RELOC_32` case, and drops the now-passing `gas/all/forward` xfail.

## Upstream audit — NOT landed
Current master `gas/config/tc-microblaze.c` `md_apply_fix` (switch at `:2113`)
still handles `BFD_RELOC_MICROBLAZE_32_LO`, `_ROSDA`, `_RWSDA`, `BFD_RELOC_32`,
`BFD_RELOC_64` and friends but has **no** `case BFD_RELOC_8:`/`case
BFD_RELOC_16:` (verified by fetch, 2026-09-04; only `BFD_RELOC_8/16` uses are
the `tc_gen_reloc` MAP macros at `:2510-2511`). The byte/halfword datum still
assembles to zero. Not re-tested since 0001 changed, per README.

## Existing deep doc
`patches/binutils/README.md` — "**0004**" summary and the gas testsuite tables
(327/1 → 329/0 on `microblaze-elf`).

## Strongest cross-arch citation
The in-file `BFD_RELOC_32` case of `md_apply_fix` (upstream
`tc-microblaze.c:2148`) is the model the patch follows — it writes the value
byte-by-byte honouring `target_big_endian`; the new `BFD_RELOC_8`/`16` cases do
the same for one and two bytes. Every gas port that emits data relocations
carries `BFD_RELOC_8`/`16`/`32` cases in `md_apply_fix`; MicroBlaze was simply
missing the two smaller ones.

## Status
Independent bug; **not sent upstream**, not re-tested since 0001 landed. Ready
to send once re-verified against current master.
