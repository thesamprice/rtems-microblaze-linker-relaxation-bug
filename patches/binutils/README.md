# binutils patch series

Four `git am`-able patches against upstream master `b7da195b94` (2.47.50.20260805).
Together they take the MicroBlaze testsuite to **zero unexpected failures** on both
`microblaze-elf` and `microblaze-xilinx-rtems7`.

```sh
cd binutils-gdb
git am .../0001-*.patch .../0002-*.patch .../0003-*.patch .../0004-*.patch
```

Verified: the series applies to pristine master with `git am`, and the resulting tree is
identical to the one tested.

## The patches

| # | what | fixes |
|---|---|---|
| 0001 | don't index the local symbol cache with a global symbol index | the relaxation bug; adds 3 new tests |
| 0002 | neutralise relocations against discarded sections | 4 existing tests |
| 0003 | widen the `pr24511` xfail to all MicroBlaze targets | 1 existing test |
| 0004 | write the value for `BFD_RELOC_8` and `BFD_RELOC_16` fixups | 2 existing tests |

**0001** is the substantive one and stands alone — it is the silent miscompilation
documented in the rest of this repository. The other three are independent bugs found
while testing it, and each can be taken or dropped separately.

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

**No test moves in the wrong direction, and `XPASS` is zero everywhere** — which matters
because 0004 cures a test that was xfailed, and that xfail is removed in the same patch.

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
