# binutils 0003: widen the `pr24511` xfail to all MicroBlaze targets

**Patch:** `patches/binutils/0003-ld-testsuite-widen-the-pr24511-xfail-to-all-MicroBla.patch`
**Files:** `ld/testsuite/ld-elf/pr24511.d` (testsuite only)

## What it does
`ld-elf/pr24511` expects `__init_array_start`/`__fini_array_start`, which
targets carrying their own linker script do not define.
`ld/scripttempl/elfmicroblaze.sc` defines neither, but the test's xfail glob
only matched `microblaze*-*-elf*`, so the test *failed* rather than *xfailed*
on `microblaze-xilinx-rtems7` and other non-elf MicroBlaze triples. The patch
widens the glob to `microblaze*-*-*`.

## Upstream audit — NOT landed
Current master `ld/testsuite/ld-elf/pr24511.d` still reads
`#xfail: ... microblaze*-*-elf* ...` (verified by fetch, 2026-09-04). Not
merged, and per the series README it should **not** be sent as written: on
`microblaze*-linux*` the `elf` SCRIPT_NAME *does* define the symbols, so the
widened xfail turns into an `XPASS` there.

## Existing deep doc
`patches/binutils/README.md` — "Known defect: 0003 XPASSes on
`microblaze*-linux*`", which gives the one-line fix.

## Strongest cross-arch citation
`ld/testsuite/ld-elf/pr23658-1e.d:17-18` — upstream invented the `#noxfail:`
mechanism for this exact MicroBlaze linux/elf split (commit `bc85bc665a`,
2024-10-10, Alan Modra, "Add noxfail option to run_dump_test", whose message
cites "pr23658-1e which fails on all microblaze ELF targets except
microblaze-linux"). 0003 should follow it with `#noxfail: microblaze*-linux*`.

## Status
**Blocked; not sent.** Needs the `#noxfail: microblaze*-linux*` line added
before it is correct on Linux triples. Testsuite-only, no code impact.
