# GCC torture suite validation

The binutils testsuite says *no test outcomes change*. This says something stronger and
more useful: **no real program's code changes.**

GCC's C torture suite, run against the four-patch series. Same compiler throughout —
only the assembler and linker are swapped — so any difference is attributable to the
patches.

## Summary

| | |
|---|---|
| **Executable content across the suite** | **byte-identical** |
| execute tests passing | **1585 of 1609** |
| execute failures caused by the patches | **0** — all 13 fail identically on both linkers |
| assembler output across 1878 programs | **byte-identical** |

## Assembler — patch 0004

`gcc.c-torture/compile`, 1920 sources at `-O2`, assembled twice with the same GCC and
different `as`:

```
identical: 1878   differ: 0   did-not-compile: 42
```

Zero differences. Adding the `BFD_RELOC_8` / `BFD_RELOC_16` cases changes nothing about
ordinary compiler output — it only fills in the case that previously assembled to zero.

The 42 that did not compile are tests requiring features this target does not have; they
fail identically with either assembler.

## Linker — patches 0001 and 0002

**Executable content is byte-identical.** Code, data, read-only data, `.eh_frame` and the
symbol table match exactly. The only differences anywhere are inside DWARF sections, and
they are patch 0002 doing precisely what `ld-discard/zero-range` and `ld-discard/zero-rel`
assert — `_bfd_clear_contents` zeroing debug references to discarded sections.

The proof rather than the claim, over a 120-binary sample:

```
after --strip-debug: identical=120  differ=0
```

Section-level breakdown of one differing pair:

| section | result |
|---|---|
| `.text` | **identical** |
| `.rodata` | **identical** |
| `.data` | **identical** |
| `.eh_frame` | **identical** |
| `.symtab` | **identical** |
| `.debug_*` | differs |

All 6560 differing bytes in that binary fall inside DWARF sections; the first is at file
offset `0x16E06`, inside `.debug_line`, well past the end of every allocatable section.

For completeness: 1599 of the linked executables differ *before* stripping debug info.
That number on its own is misleading, which is why it is stated last — it is entirely
DWARF, and the `--strip-debug` comparison above is what establishes that.

## Execution

All 1609 `gcc.c-torture/execute` tests at `-O2`, built against the RTEMS
`microblaze/kcu105_qemu` BSP and run on QEMU `petalogix-s3adsp1800`:

| | |
|---|---:|
| pass | **1585** |
| fail | 13 |
| would not link | 6 |
| would not compile | 4 |

Every one of the 13 failures was re-run against **both** linkers:

```
  test                     pristine-ld  patched-ld
  20001011-1                FAIL FAIL
  20040409-1w               FAIL FAIL
  20040409-2w               FAIL FAIL
  20040409-3w               FAIL FAIL
  920612-1                  FAIL FAIL
  920711-1                  FAIL FAIL
  eeprof-1                  FAIL FAIL
  memcpy-1                  TIMEOUT TIMEOUT
  pr22493-1                 FAIL FAIL
  pr23047                   FAIL FAIL
  pr28982b                  TIMEOUT TIMEOUT
  pr57124                   FAIL FAIL
  stkalign                  TIMEOUT TIMEOUT
```

13 of 13 identical. **Zero regressions.** These are MicroBlaze and RTEMS environment
limitations — wide character support (`20040409-*w`), profiling (`eeprof-1`), stack
alignment (`stkalign`) — not anything the patches touch.

## Two traps worth knowing about

**Compare like with like.** The obvious move is to diff against the installed
`microblaze-rtems7` toolchain, which is the Xilinx binutils 2.36 snapshot. That would
attribute **eleven years of binutils history** to four patches. The comparison here is
pristine upstream `b7da195b94` (2.47.50.20260805) against the same tree with the series
applied — both built from the same source, same configuration, same host compiler.

**The BSP will not build without the RTEMS non-FDT fix.** With
`BSP_MICROBLAZE_FPGA_USE_FDT = False`, `bsps/microblaze/shared/fdt/microblaze-fdt-support.c`
fails with `-Werror=unused-parameter` on `compatible` and `prop_name`. That is the
concrete reason
[`../patches/rtems/0001-bsps-microblaze-Fix-build-without-BSP_MICROBLAZE_FPGA_USE_FDT.patch`](../patches/rtems/)
exists; apply it first or the harness cannot be built at all.

## Reproducing

```sh
# 1. two binutils trees, same version, one patched
../binutils-gdb/configure --target=microblaze-rtems7 --disable-gdb --disable-sim \
    --disable-gdbserver --disable-readline --disable-nls --disable-werror --with-system-zlib
make -j8 all-gas all-binutils all-ld     # once pristine, once with the series

# 2. a directory of tool symlinks for each, passed to gcc with -B
mkdir base pat
ln -s <pristine>/gas/as-new base/as ; ln -s <pristine>/ld/ld-new base/ld
ln -s <patched>/gas/as-new  pat/as  ; ln -s <patched>/ld/ld-new  pat/ld

# 3. an installed RTEMS microblaze BSP, with the non-FDT fix applied
# 4. wrap.c turns each test into an RTEMS application
```

`wrap.c` compiles the test with `-Dmain=torture_main` and calls it from `Init`. The
tests end in `exit (0)`, so the pass criterion is `[ RTEMS shutdown ]` **without**
`*** EXIT STATUS NOT ZERO ***`; `abort()` produces the latter. Verified against a
deliberately aborting program before trusting it.

Per-test result lists are in [`results/`](results/).
