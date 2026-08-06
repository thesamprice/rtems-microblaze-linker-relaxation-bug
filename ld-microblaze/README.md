# `ld/testsuite/ld-microblaze/`

Dejagnu tests for the linker relaxation fix. These are the files as they appear
in the complete patch — [`../patches/binutils/`](../patches/binutils/) — copied
here so they can be read without unpacking it.

**This is the first `ld-microblaze` directory in binutils.** The target has had
no linker tests at all, which is some of the reason a defect this old went
unnoticed.

## What they do

Both tests assemble `relax-addend.s` and `relax-addend-support.s`, link them
with `-relax --gc-sections` and a fixed linker script, and check that a
relocation with a non-zero addend against a global symbol survived.

`.text.aaa_relaxed` contains an `IMM` that relaxation deletes. `.text.zzz_victim`,
a sibling section of the same object, refers to `gvar + 0x18`. Relaxing the
first makes the linker walk the relocations of the second, which is where the
unguarded index lives.

| test | dumper | relocation | checks |
|---|---|---|---|
| `relax-addend.d` | `objdump -d` | `R_MICROBLAZE_64` | the `IMM`/`LWI` pair resolves to `gvar + 0x18` |
| `relax-addend-data.d` | `readelf -x .checkdata` | `R_MICROBLAZE_32` | a data word initialised to `gvar + 0x18` |

Two dumpers and two relocation arms of the same loop, so a fix that misses one
arm is still caught.

`relax-addend.ld` pins `.text` at `0x90000000` and `.data` at `0x90001000`, so
`gvar` is at `0x90001000` and the reference must be `0x90001018`. Without the
script the expected output would depend on the built-in linker script and drift
between binutils versions.

The branch target lives in `.text.zz_support`, laid out after the relaxed
section, because a backward reference is not relaxed and the test would then
exercise nothing.

## Results

Run against upstream master `b7da195b94` (2.47.50.20260805):

```
PASS: MicroBlaze relaxation preserves R_MICROBLAZE_32 addends
PASS: MicroBlaze relaxation preserves R_MICROBLAZE_64 addends
```

Whole binutils `make check`, target `microblaze-xilinx-rtems7`:

| component | baseline | patched |
|---|---|---|
| gas | 323 pass, 2 fail | identical |
| binutils | 92 pass, 17 fail | identical |
| ld | 476 pass, 13 fail | 478 pass, 13 fail |

Delta across the whole suite is exactly the two new passes. Details and raw
`.sum` files: [`../binutils-testsuite/`](../binutils-testsuite/).

## What they do and do not prove

**They detect addend corruption.** Verified by injecting an unconditional
four-byte subtraction at the same place in `microblaze_elf_relax_section` and
re-running:

```
FAIL: MicroBlaze relaxation preserves R_MICROBLAZE_32 addends
FAIL: MicroBlaze relaxation preserves R_MICROBLAZE_64 addends
```

**In a normally built linker they do not fail on unfixed binutils.** The
out-of-bounds read happens on every run, but whether it corrupts the addend depends on
what the bytes past the end of the symbol buffer happen to be. A portable
output-comparison test cannot force that.

**Under an ASan-built linker `relax-addend-eh.d` does fail on unfixed binutils**, because
the read itself is unconditional and ASan traps it. Measured on `microblaze-xilinx-elf`,
master `b7da195b94`:

| ld built | guard | result |
|---|---|---|
| normally | removed | 3 pass |
| normally | present | 3 pass |
| with ASan | removed | **`relax-addend-eh.d` FAILS**, 2 ASan reports |
| with ASan | present | 3 pass |

Attribution is exact: this was measured by deleting **only** the two-line
`ELF32_R_SYM (irelscan->r_info) >= symtab_hdr->sh_info` guard from
`microblaze_elf_relax_section`, leaving the other three patches in the tree. Nothing
else varies between the rows.

The other two tests pass in all four configurations — they drive the `--gc-sections`
route, which is closed on current master, so they cannot discriminate no matter how the
linker is built.

So anyone running the binutils testsuite against an ASan-instrumented `ld` — which is
worth doing anyway — gets a test that genuinely catches this. See
[`../binutils-testsuite/`](../binutils-testsuite/) for how to set that up; on macOS it
needs `MallocNanoZone=0` or the allocator prints into tool output and manufactures
spurious failures.

So these are regression tests that pin correct behaviour, plus the first
coverage this target has ever had. The evidence that the bug is real is the
ASan report in [`../testcase-upstream/`](../testcase-upstream/), which is
deterministic.

## Running them

```sh
cp -r ld-microblaze binutils-gdb/ld/testsuite/
cd binutils-build
make check-ld RUNTESTFLAGS="ld-microblaze/microblaze.exp"
```

Needs `as`, `ld` and `objdump`/`readelf` built in the same tree
(`make all-ld all-gas all-binutils`) and dejagnu installed.
