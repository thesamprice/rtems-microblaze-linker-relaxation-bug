# binutils patch series

Four `git am`-able patches against upstream master `b7da195b94` (2.47.50.20260805).
Together they take the MicroBlaze testsuite to **zero unexpected failures** on both
`microblaze-elf` and `microblaze-xilinx-rtems7`.

```sh
cd binutils-gdb
git am .../0001-*.patch .../0002-*.patch .../0003-*.patch .../0004-*.patch
```

**0005 is independent of the four above** — it is not a MicroBlaze fix and not part
of the testsuite story. It is an architecture-neutral `bfd/dwarf2.c` determinism fix
for `addr2line`, carried here because it is what makes per-test coverage `.info`
files reproducible in the tcgcov work. It applies to the same `binutils-gdb` master
and to `binutils-2.45.1` (what the Buildroot MicroBlaze target builds), and is also
staged as `board/qemu/patches/binutils/0006-bfd-dwarf2-addr2line-tiebreak.patch` in
that build tree. Not sent upstream yet.

Verified: the series applies to pristine master with `git am`, and the resulting tree is
identical to the one tested.

0001 and 0002 are re-verified against `b7da195b94b` in their current form: `git am` of
0001 alone gives tree `07bc4db4a9`, and 0002 on top gives ld 480 passes / 0 unexpected
failures. 0003 and 0004 have not been re-tested since 0001 changed.

## The patches

| # | what | fixes | status |
|---|---|---|---|
| 0001 | don't index the local symbol cache with a global symbol index | the relaxation bug; adds 3 new tests | **sent as v2, 2026-08-12** |
| 0002 | neutralise relocations against discarded sections | 4 existing tests | ready; NULL howto guarded |
| 0003 | widen the `pr24511` xfail to all MicroBlaze targets | 1 existing test | blocked: needs `#noxfail: microblaze*-linux*` |
| 0004 | write the value for `BFD_RELOC_8` and `BFD_RELOC_16` fixups | 2 existing tests | not reviewed since 0001 |
| 0005 | break equal-range `addr2line` function ties by DIE offset, not pointer | non-reproducible `-f`/`-i` output; adds 1 regression pin | independent; not sent upstream |

They are no longer sent as one series. 0001 went to the list on its own, as recommended
below, and 0002 is now numbered as a standalone `[PATCH]` rather than `2/4`.

**0001** is the substantive one and stands alone — it is the silent miscompilation
documented in the rest of this repository. The other three are independent bugs found
while testing it, and each can be taken or dropped separately.

### 0001 status: sent as v2 (2026-08-12)

Neal Frager posted v1 to binutils@sourceware.org on 2026-08-10,
`<20260810060011.4186926-1-neal.frager@amd.com>`. Alan Modra reviewed it — "The patch
looks good to me" — and suggested a tidy-up, on the grounds that no code in
`microblaze_elf_relax_section` needs to re-read global symbols.

v2 applies that tidy-up verbatim and was sent on 2026-08-12,
`<20260813021826.84333-1-thesamprice@gmail.com>`, threaded under v1 and copied to Neal
Frager, Alan Modra and Michael Eager. It:

- reads only the `sh_info` local symbols rather than the whole symbol table;
- fails the relaxation rather than asserting if the read fails;
- uses `PTR_ADD` for the end of the local symbol buffer, since `isymbuf` may now be NULL;
- drops the dead assignment to `isym` before the global symbol loop.

The `sh` precedent is now cited in the commit message, including that the guard has been
in `sh_elf_relax_delete_bytes` since the first binutils commit (`252b5132c7`,
1999-05-03) — verified, not assumed.

Two things were deliberately left out of the sent version, to keep it as close to v1 as
possible. Add them if a reviewer asks:

- **The `R_MICROBLAZE_32_SYM_OP_SYM` arm is dead code.** It is the only arm of the five
  not gated on `STT_SECTION`, so a reviewer may read the guard as a semantic change
  there. It is not: that `else if` is nested inside the
  `R_MICROBLAZE_32 || R_MICROBLAZE_32_NONE` test above it and can never be true.
- **An expanded comment on the `isymbuf` fetch**, recording that `symtab_hdr->contents`
  holds only local symbols. Alan left that comment line untouched, so v2 does too;
  `elf32-sh.c:573` likewise keeps a one-liner.

Whole `make check` on `microblaze-elf`, pristine `b7da195b94b` versus v2, compared test
by test: **zero status changes** in either direction, nothing disappeared, the only
difference is the three new tests. ld 473→476 passes, gas 327/1 and binutils 239/0 both
unchanged.

**0002** — `bfd/elf32-microblaze.c` had no `RELOC_AGAINST_DISCARDED_SECTION`, the idiom
60 other ELF backends use. Relocations into discarded linkonce sections survived and
resolved against dead symbols.

**0003** — testsuite only. The test already xfails targets whose own linker script does
not define `__init_array_start`; MicroBlaze is such a target but the glob only covered
`*-elf` triples.

**0004** — `md_apply_fix` had no case for `BFD_RELOC_8` or `BFD_RELOC_16`, so a byte or
halfword datum resolved at fixup time assembled to **zero**. It also cures
`gas/all/forward`, which was xfailed for `microblaze-*-*`; that xfail is dropped in the
same patch.

**0005** — `bfd/dwarf2.c`, `lookup_address_in_function_table`, broke equal-range ties
between two `struct funcinfo *` by comparing the pointers. Those come from `bfd_zalloc`,
so the winner tracked heap layout and `addr2line -f -i` named a different (inlined)
function from run to run on the same binary — 23 of 200 runs differed on an RTEMS riscv
`hello.exe`, only in which function was named, never in file/line. The fix orders by
`unit_offset` (the DIE offset), which is what the pre-2016 walk of `unit->function_table`
effectively did and which does not move with the heap. The bundled `dw2-inline-tie`
test is a **regression pin** — allocation order normally equals DIE order, so a portable
test cannot force the divergence; inverting the new comparison to `<` makes it FAIL,
which is what gives it teeth. Found while chasing why coverage `.info` files were not
reproducible across runs of the same suite: `FN`/`FNDA` moved while `DA`, `BRDA`, `LF`
and `BRF` never did. Arch-independent; wanted by any tcgcov user who symbolizes with
`addr2line -i` (all of them). `make check-binutils` on `riscv64-unknown-elf`: 236→237
passes, the one pre-existing efi-format failure unchanged.

## Testsuite

Whole `make check`, both targets, pristine master versus the series applied.

### `microblaze-elf`

| component | baseline | with series |
|---|---|---|
| gas | 327 pass, 1 fail | **329 pass, 0 fail** |
| binutils | 239 pass, 0 fail | 239 pass, 0 fail |
| ld | 473 pass, 4 fail | **480 pass, 0 fail** |

### `microblaze-xilinx-rtems7`

| component | baseline | with series |
|---|---|---|
| gas | 324 pass, 1 fail | **326 pass, 0 fail** |
| binutils | 239 pass, 0 fail | 239 pass, 0 fail |
| ld | 472 pass, 5 fail | **479 pass, 0 fail** |

**No test moves in the wrong direction on either target above, and `XPASS` is zero on
both** — which matters because 0004 cures a test that was xfailed, and that xfail is
removed in the same patch.

### Known defect: 0003 XPASSes on `microblaze*-linux*`

The two targets above are the only ones measured, and that was not enough. On
`microblaze-xilinx-linux-gnu`, patch 0003 as written produces `XPASS: ld-elf/pr24511`.
Linux targets use `SCRIPT_NAME=elf` (`ld/emulparams/elf32mb_linux.sh:1`), which *does*
define `__init_array_start`, so the test genuinely passes there and the widened xfail is
wrong for it.

The fix is one line, and upstream invented the mechanism for this exact MicroBlaze split —
`bc85bc665a` (2024-10-10, Alan Modra, *"Add noxfail option to run_dump_test"*), whose
commit message cites *"pr23658-1e which fails on all microblaze ELF targets except
microblaze-linux."* Follow `ld/testsuite/ld-elf/pr23658-1e.d:17-18`:

```
#xfail: ... microblaze*-* ...
#noxfail: microblaze*-linux*
```

With `#noxfail: microblaze*-linux*` added, `ld-elf/elf.exp` on `microblaze-xilinx-linux-gnu`
gives 327 expected passes and zero unexpected successes. **0003 should not be sent until
this is applied.**

### Fixed: 0002 could dereference a NULL howto

`microblaze_elf_howto_table` (`bfd/elf32-microblaze.c:38`) is an array of *pointers*, not
of howtos, and is zero-filled. `R_MICROBLAZE_TEXTREL_32_LO` (32) is the one in-range
relocation type with **no HOWTO entry** — 33 entries in `microblaze_elf_howto_raw`
against 34 slots. Patch 0002 passed `howto` straight to `_bfd_clear_contents`, which
reads `howto->size` via `bfd_reloc_offset_in_range` (`bfd/reloc.c:1341`, `:529`). The
type is reachable — relaxation rewrites `TEXTREL_64` into it and `relocate_section` has a
case for it — so `-mpic-data-text-rel` code plus a discarded comdat section could crash
the linker.

0002 now guards the call with `howto != NULL`. **`elf32-ppc.c` is the model**: it and
`elf32-mcore.c` are the only other backends whose howto table is an array of pointers,
and ppc likewise treats a NULL howto as a live case rather than dereferencing it
(`bfd/elf32-ppc.c:7639-7641`, `:7648`). Every other backend gets its howto by pointer
arithmetic into a dense array of values — `elf32-sh.c:3486` is typical — so the hazard
cannot arise there and those files offer no precedent.

ppc also range-checks the index before the lookup; MicroBlaze already does that at
`:1075`, so only the NULL handling was missing.

Consequence: a relocation of that type against a discarded section is left alone rather
than neutralised, which is the pre-existing behaviour. Supplying the missing HOWTO entry
would be the fuller fix, but needs the correct field values and belongs in its own patch.

Audited the other eleven uses of `microblaze_elf_howto_table` for the same hazard; all
are safe. The two `->name` dereferences at `:1245` and `:1293` sit inside
`case R_MICROBLAZE_SRO32` / `SRW32`, types 7 and 8, both of which have howtos, and the
lazy-init check at `:1043` tests `R_MICROBLAZE_max-1` = 33 = `R_MICROBLAZE_32_NONE`,
which has a howto.

**Still open, and separate from this patch:** `:1151` does `if (!howto->partial_inplace)`
in the `bfd_link_relocatable` branch with no NULL check, so `ld -r` on an object holding a
`TEXTREL_32_LO` against a section symbol dereferences NULL today, independent of 0002.
Worth its own one-liner.

### Fixed: 0002 could dereference a NULL `sym_hashes`

The same shape of mistake, found by asking whether `sym_hashes[r_symndx - sh_info]` can go
out of bounds.

**The index cannot.** `_bfd_elf_link_info_read_relocs` routes every relocation through
`elf_link_read_relocs_from_section`, which rejects `r_symndx >= NUM_SHDR_ENTRIES
(symtab_hdr)` with a hard error (`bfd/elflink.c:2851-2864`). `elf_sym_hashes` is allocated
with `symcount - sh_info` entries (`bfd/elflink.c:4864`), so `r_symndx - sh_info` is
always inside it, and the subtraction cannot wrap because the `else` branch only runs when
`r_symndx >= sh_info`. This is genuinely unlike 0001, where nothing tied the index range to
the buffer length.

**The pointer can.** `RELOC_FOR_GLOBAL_SYMBOL` (`bfd/elf-bfd.h:3431-3436`) — the macro
every backend uses for this lookup — guards `sym_hashes == NULL` and documents it as
arising from "erroneous or unsupported input (mixing a.out and elf in an archive, for
example)". 0002 hoisted its own lookup to `:1101`, ahead of MicroBlaze's
`RELOC_FOR_GLOBAL_SYMBOL` at `:1191`, and so outran that guard.

Now `else if (sym_hashes != NULL)`, leaving `sym_sec` NULL so neutralisation is skipped and
the later macro still returns false exactly as it does today.

Both defects in 0002 are the same failure mode: moving work earlier in the function moves it
ahead of a check that already existed further down.

Raw `.sum` files: [`../../binutils-testsuite/`](../../binutils-testsuite/).

## Checks run on every patch

- `contrib/check_GNU_style.py` — clean on all four. Verified the checker actually works
  by feeding it a deliberately mangled version of the same hunk first; it reported all
  five error classes.
- `git diff --check` across the whole series — no whitespace errors.
- `git am` onto pristine master — all four apply, resulting tree identical to the tested
  one.
- ChangeLog entries are in the commit messages. Binutils has generated the `ChangeLog`
  files from the git log since 2021-07-03, per
  `binutils/README-how-to-make-a-release`.

## Note on evidence

The RTEMS material elsewhere in this repository is *motivation* — why 0001 matters to a
real project — not validation. Validation is the ASan reproducer in
[`../../testcase-upstream/`](../../testcase-upstream/) and the testsuite results above.

## Where to send it

Sourceware Bugzilla against `ld` / MicroBlaze for 0001, plus the series to
binutils@sourceware.org. Add your own `Signed-off-by:` before sending.

Consider sending 0001 on its own first. It is a two-line fix with a reproducer and a
clean testsuite; the other three are unrelated and can follow once it lands, rather than
splitting reviewer attention across four problems with the same target.

That is what happened: 0001 went out alone as v1 and then v2, and 0002 is next once 0001
lands. Note that 0001 is signed off as `samuel.r.price@nasa.gov` (inherited from v1) while
0002 uses `thesamprice@gmail.com`, which is the address that can send and receive list
mail. Both are the same person and DCO does not require one address, but they are
inconsistent across the two patches.
