# binutils testsuite, baseline vs patched

Binutils' own `make check`, whole suite, with and without the patch. Target
`microblaze-xilinx-rtems7`, upstream master `b7da195b94` (2.47.50.20260805).

RTEMS testsuite results are **not** validation for a binutils change. They are why the
bug matters, not evidence that the patch is correct.

Baseline is **unmodified upstream master**, verified to contain no part of the fix
before the run.

## Result

| component | baseline | patched | delta |
|---|---|---|---|
| gas | 324 pass, 1 fail | 324 pass, 1 fail | none |
| binutils | 239 pass, 0 fail | 239 pass, 0 fail | none |
| ld | 472 pass, 5 fail | **474 pass**, 5 fail | **+2** |
| **total** | **1035 pass, 6 fail** | **1037 pass, 6 fail** | **+2 pass** |

Diffing the full `PASS`/`FAIL`/`XFAIL`/`XPASS`/`UNRESOLVED`/`UNTESTED`/`UNSUPPORTED`
lists: `gas` and `binutils` **identical**, `ld` identical except

```
> PASS: MicroBlaze relaxation preserves R_MICROBLAZE_32 addends
> PASS: MicroBlaze relaxation preserves R_MICROBLAZE_64 addends
```

The only change the patch makes to the entire binutils testsuite is the two tests it
adds.

## Two corrections to earlier versions of this page

Recorded rather than quietly fixed.

**The linker was built with AddressSanitizer.** On macOS an ASan-instrumented binary
prints `malloc: nano zone abandoned due to inability to reserve vm space` on startup.
That text lands in tool output and breaks every test that matches output exactly. It
accounted for **16 of the 32 failures** previously reported here, and none of them are
real. Rebuilt without ASan, `binutils` goes from 92 pass / 17 fail to **239 pass /
0 fail**, and the eight `sysroot-prefix` failures disappear entirely.

**The remaining failures were called "host artifacts". They are not.** All six are
MicroBlaze-related. That claim was made without checking and was wrong.

## The 6 real failures — all MicroBlaze

Present identically with and without the patch. None are caused by it, and none are
host problems.

### Relocations against discarded sections (4)

`ld-discard/zero-range`, `ld-discard/zero-rel`, `ld-elf/linkonce1`, `ld-elf/linkonce2`

```
regexp "^.*(NONE|unused|UNUSED).*\*ABS\*$"
line   "00000000 R_MICROBLAZE_32   foo"
```

When a linkonce/comdat section is discarded, relocations pointing into it must be
neutralised. Every ELF backend does this with one idiom:

```c
      if (discarded_section (sec))
	RELOC_AGAINST_DISCARDED_SECTION (info, input_bfd, input_section,
					 rel, 1, relend, R_<TARGET>_NONE,
					 howto, 0, contents);
```

**`bfd/elf32-microblaze.c` does not contain `RELOC_AGAINST_DISCARDED_SECTION` at all.**
60 other `bfd/elf*.c` files do. Its absence is consistent with all four failures: the
relocation survives and resolves against a dead symbol, so debug sections end up with
garbage where zero is expected.

This looks like a second, independent MicroBlaze linker bug. Not fixed here — it is a
separate change needing its own testing, and bundling it would sink an otherwise simple
patch.

### `.dc.b` / `.dc.w` of a label difference assemble to zero (1)

`gas: simple forward references`

```
regexp "^ 0000 0c000000 (0c000000 0c000000|...) .*$"
line   " 0000 00000000 00000000 0000000c           "
```

The test emits `L1-L0` as a byte, a halfword and a word. The word is correct
(`0000000c`); the byte and the halfword both come out **zero**.

The `.d` file's own comment is apt: *"Others emit incorrect relocs which lead to
incorrect results after linking."* Its `xfail` list is `am33 crx mn10300` and does not
include MicroBlaze. The sibling test `gas/all/forward` **is** already xfailed for
`microblaze-*-*` upstream, so this family is known to be broken on this target;
`simple-forward` simply was not caught.

The same underlying behaviour shows up elsewhere: MicroBlaze GAS emits an
`R_MICROBLAZE_NONE` marker for every *resolved* label difference. `.eh_frame` is built
almost entirely from label differences, which desynchronises `ent->reloc_index` in
`_bfd_elf_discard_section_eh_frame` and produces the
`error in <file>(.eh_frame); no .eh_frame_hdr table will be created` messages that the
Xilinx patch set silences rather than fixes.

### Missing `__init_array_start` (1)

`ld-elf/pr24511` — a known limitation whose `xfail` misses this triple:

```
#xfail: ... microblaze*-*-elf* ...
```

Our target is `microblaze-xilinx-rtems7`, which does not match `microblaze*-*-elf*`.
The MicroBlaze linker script does not `PROVIDE_HIDDEN` the init/fini array symbols, as
the test's comment anticipates for targets with their own scripts. Either the xfail
should be widened to `microblaze*-*-*` or the script should define them — a small
upstream fix either way, independent of this patch.

## Reproducing

```sh
../binutils-gdb/configure --target=microblaze-rtems7 \
    --disable-gdb --disable-sim --disable-gdbserver --disable-readline \
    --disable-nls --disable-werror --with-system-zlib
make -j8 all-gas all-binutils all-ld
make -k check
```

**Do not build with ASan for a testsuite run** — see the corrections above. Use a
separate ASan build for the reproducer in
[`../testcase-upstream/`](../testcase-upstream/).

On macOS add `-Dfdopen=fdopen` to `CC`; the bundled zlib takes its classic-Mac-OS
branch because `TARGET_OS_MAC` is defined there too.

Needs dejagnu. Raw `.sum` files for all six runs are in this directory.

## Caveat

Fetching a newer master was rate-limited by sourceware (HTTP 429), so this is one day
behind tip. Worth re-running against current master before sending.
