# binutils 0002: neutralise relocations against discarded sections

**Patch:** `patches/binutils/0002-microblaze-neutralise-relocations-against-discarded-.patch`
**Files:** `bfd/elf32-microblaze.c`

## What it does
`elf32-microblaze.c`'s `relocate_section` had no `RELOC_AGAINST_DISCARDED_SECTION`
— the idiom ~60 other ELF backends use — so relocations into discarded
linkonce/comdat sections survived and resolved against dead symbols. The patch
resolves the target section early (local or global) and calls
`RELOC_AGAINST_DISCARDED_SECTION` when it is discarded, guarded against a NULL
`howto` (for `R_MICROBLAZE_TEXTREL_32_LO`, which has no HOWTO) and a NULL
`sym_hashes` (objects with no globals).

## Upstream audit — LANDED
Fixed in current master, including both guards. `bfd/elf32-microblaze.c:1119`
now reads `if (sym_sec != NULL && discarded_section(sym_sec) && howto != NULL)`
then `RELOC_AGAINST_DISCARDED_SECTION(...)` (`:1120`), with the global branch
gated on `else if (sym_hashes != NULL)` (`:1099`). Commit "microblaze:
neutralise relocations against discarded sections", 2026-08-13 (mirror synced
2026-09-04).

## Existing deep doc
`patches/binutils/README.md` — "**0002**" summary, "Fixed: 0002 could
dereference a NULL howto", and "Fixed: 0002 could dereference a NULL
`sym_hashes`" (the full guard audit).

## Strongest cross-arch citation
`bfd/elf32-ppc.c:7639-7641,7648` — ppc and `elf32-mcore.c` are the only other
backends whose howto table is an array of *pointers*, and ppc likewise treats a
NULL howto as a live case rather than dereferencing it. Every dense-array
backend (e.g. `elf32-sh.c:3486`) cannot hit the hazard, so ppc is the model for
the NULL-howto guard. The `sym_hashes != NULL` check mirrors
`RELOC_FOR_GLOBAL_SYMBOL` (`bfd/elf-bfd.h:3431-3436`).

## Status
Was "ready; NULL howto guarded" in the series README. **Now merged upstream**
alongside 0001. Doc records the landed state.

Re-verified 2026-09-04: present in the base commit `6f24afa` and current master
`193340ad3`; the patch no longer applies. See [REWORK.md](REWORK.md).
