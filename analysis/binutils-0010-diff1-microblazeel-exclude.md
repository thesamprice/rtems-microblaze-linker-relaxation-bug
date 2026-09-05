# binutils 0010: exclude microblazeel from the gas diff1 test

**Patch:** `patches/binutils/0010-gas-testsuite-exclude-microblazeel-from-diff1.patch`
**Target:** binutils master, `gas/testsuite/gas/all/gas.exp`
**Status:** open; testsuite-only, independent

## What it does
`gas/all/gas.exp` skips the "difference of two undefined symbols" test (`diff1`)
for targets that resolve such differences at link time via relaxation. The guard
is `![istarget microblaze-*-*]` (`gas.exp:73`), which matches the big-endian
triplet but not the little-endian `microblazeel-*-*`, so the test runs and fails
on `microblazeel` even though the assembler is correct. Widen the glob to
`microblaze*-*-*`.

## Why it survived
Nobody ran the generic `gas/all` suite on `microblazeel` — the MicroBlaze
testing that happened used `microblaze-*` (big-endian) or only the
`gas/microblaze` subset. It is the same class of gap as patch 0003 (an xfail
whose glob missed the `-linux` triplet).

## What a reviewer should sanity-check
- `gas/testsuite/gas/all/gas.exp:70-83` — `diff1` is inside the relaxation-target
  exclusion list, alongside `avr-*-*`, `rl78-*-*`, `rx-*-*`; MicroBlaze belongs
  there for the same reason (link-time relaxation resolves undefined-symbol
  differences), and both endiannesses should be covered.

## How other processors do it
The neighbours in the same list already use endian-agnostic globs where needed;
the fix just makes MicroBlaze consistent (`microblaze*-*-*`).

## Verification
With the fix, `gas/all` on `microblazeel` drops from 2 failures to 1 — only the
generic `all end` (quoted-symbol-name) test remains, which is not
MicroBlaze-specific. See analysis/REWORK.md for the full gas/ld/binutils run.
