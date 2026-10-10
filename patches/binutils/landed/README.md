# binutils patches that are upstream

Kept for the record only; none of these are applied by `harness/run.sh` or
generated into `outbox/`. Each is the version that actually landed.

| file | upstream commit | committed | by |
|---|---|---|---|
| `0001-ld-microblaze-don-t-index-the-local-symbol-cache.patch` | `a639e0adaf2` | 2026-08-28 | Alan Modra |
| `0002-microblaze-neutralise-relocations-against-discarded-.patch` | `f55053f1dc9` | 2026-08-28 | Alan Modra |
| `0004-microblaze-add-BFD_RELOC_8-and-BFD_RELOC_16-cases.patch` | `ee6b7f5bb8e` | 2026-09-24 | Michael J. Eager |
| `0011-microblaze-use-md_number_to_chars-in-md_apply_fix.patch` | `5047dd4a3a2` | 2026-09-24 | Michael J. Eager |
| `0010-gas-testsuite-exclude-microblazeel-from-diff1-and-end.patch` | `ad8ac4b8993` | 2026-09-24 | Michael J. Eager |
| `0012-microblaze-use-md_number_to_chars-in-md_assemble.patch` | `0dabe1eeb6d` | 2026-09-24 | Michael J. Eager |

Also upstream, and never carried here as a file: the arch-neutral
`bfd/dwarf2.c` addr2line tie-break, `b2e68bf063e` (committed 2026-09-18 by
Alan Modra). It was this repo's 0004→0005 before being removed on 2026-09-08
and sent standalone; the sent patches live outside this repo in
`claude-mb/addr2line-tie-v2/`.

## Numbering

The numbers are this repo's bookkeeping, not the order they were sent or
landed. 0004, 0010, 0011 and 0012 went to the list together as one v3 series
(`[PATCH v3 1/4]` … `4/4`); 0011 and 0012 were written during that review and
never existed as standalone repo patches before it.

## How the v3 series came about

0004 went out alone as v1 (2026-09-20). Neal Frager reviewed it and asked for
the stale comment above the `#xfail:` line in `forward.d` to go as well, which
became v2 (2026-09-22). Michael Eager then asked for `md_number_to_chars`
instead of open-coded `buf[n] |=` writes, "like aarch64, mips, sparc", and
added that cleaning up the other `BFD_RELOC_MICROBLAZE_*` cases the same way
would be welcome. v3 (2026-09-24) did both, plus:

- **0010** grew a second hunk. Testing on `microblazeel-elf` for the first
  time showed `gas.exp` excludes MicroBlaze from *two* tests — `diff1` and
  `end` — and both guards said `microblaze-*-*`, which does not match the
  little-endian triplet. The original 0010 only widened the `diff1` one.
- **0012** finished the conversion in `md_assemble`, which let the four
  `INST_BYTE0..3` macros be deleted outright.

`INST_IMM_OFFSET` survives as the only `target_big_endian` test left in
`tc-microblaze.c`: `md_number_to_chars` fixes the byte order of the 16-bit
immediate field but not its *position*, which is offset 2 big-endian and 0
little-endian because the instruction word itself is stored in target order.

Test evidence for the series is in
[`../../../binutils-testsuite/microblaze-elf/0004-standalone/`](../../../binutils-testsuite/microblaze-elf/0004-standalone/README.md).
