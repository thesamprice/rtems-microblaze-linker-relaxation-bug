# binutils 0001: don't index the local symbol cache with a global symbol index

**Patch:** `patches/binutils/0001-ld-microblaze-don-t-index-the-local-symbol-cache.patch`
**Files:** `bfd/elf32-microblaze.c` (+ 3 new ld tests)

## What it does
`microblaze_elf_relax_section`'s other-sections scan loop did `isym = isymbuf +
ELF32_R_SYM(irel->r_info)` with no guard, indexing a `sh_info`-sized local
symbol buffer with a *global* symbol index. Out-of-bounds reads corrupted
relaxation deltas, silently miscompiling addends. The fix guards each such
access with `>= sh_info → continue`, reads only `sh_info` locals, and uses
`PTR_ADD` since the buffer may now be NULL.

## Upstream audit — LANDED
Fixed in current master. `bfd/elf32-microblaze.c` now reads only `sh_info`
locals (`:1903`), guards the scan loop `if (ELF32_R_SYM(irelscan->r_info) >=
symtab_hdr->sh_info) continue;` (`:2125`), and ends the buffer with
`PTR_ADD(isymbuf, sh_info)` (`:2329`) — the v2 patch verbatim. Commit
"ld: microblaze: don't index the local symbol cache", 2026-08-13 (mirror synced
2026-09-04).

## Existing deep doc
`ANALYSIS.md` (Root cause §, Fix §, Upstream status §); `RELAXATION-GUIDE.md`
§5 "Walking through `microblaze_elf_relax_section`" and §6 "Provenance";
`patches/binutils/README.md` "0001 status: sent as v2 (2026-08-12)".

## Strongest cross-arch citation
`bfd/elf32-sh.c` — the file MicroBlaze's relax loop was copied from — has the
guard `if (ELF32_R_SYM(irelscan->r_info) >= symtab_hdr->sh_info) continue;` in
its other-sections loop since the first commit in binutils git history
(`252b5132c7`, 1999-05-03; at `elf32-sh.c:1230` in the port-landing tree). The
port dropped it at copy time in 2009; upstream master now matches sh again.

## Status
**Sent as v2 (2026-08-12), reviewed by Alan Modra ("looks good"), and now
merged upstream.** No further action; this doc records the landed state.

Re-verified 2026-09-04 against current master `193340ad3`: the guard is present
and our patch no longer applies (the fix is already there). See
[REWORK.md](REWORK.md).
