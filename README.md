# MicroBlaze linker relaxation corrupts relocation addends

`ld --relax` for MicroBlaze silently corrupts the addend of `R_MICROBLAZE_64`
relocations that have a non-zero addend. No error, no warning — the program just
loads from the wrong address.

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so **every MicroBlaze
link is exposed by default**.

The defect is in **binutils**, `bfd/elf32-microblaze.c`. It is present both in the
Xilinx binutils 2.36 snapshot used by the RTEMS MicroBlaze toolchain **and in current
upstream binutils master**.

This repository holds the root-cause analysis, the evidence, and the patches.

## The one-line version

```
the_period->owner = _Thread_Get_executing();
```

compiles to a relocation against `_Per_CPU_Information + 0x18`
(`offsetof(Per_CPU_Control, executing)`) and links as
`_Per_CPU_Information + 0x14` — which is `dispatch_necessary`. RTEMS then hands out
the wrong executing thread and resource ownership breaks system-wide.

## Why it matters to RTEMS

This is why `bspkcu105.yml` and `bspkcu105_qemu.yml` link `../../opto0` — only 6 of
~170 BSPs in the tree are built at `-O0`. Building at `-O2` regressed 16 tests, all
with a thread-identity / resource-ownership signature, so the BSPs shipped `-O0`
instead. `-O0` masks the bug because at `-O0` GCC emits a **zero** addend and uses a
register offset; zero addends are immune.

Cost of the workaround versus the `-O0` build the BSPs ship today
(`minimum.norun.exe`, text bytes):

| | text | vs `-O0` |
|---|---:|---:|
| `-O0` (as shipped) | 68,133 | — |
| `-O2` | 32,017 | −53% |
| `-O2` + `-Wl,--no-relax` | 32,537 | −52% |

Relaxation is worth 520 bytes. The `-O2` win survives essentially intact.

## Test results

`microblaze/kcu105_qemu`, QEMU `petalogix-s3adsp1800`, 676 executables:

| | PASS | FAIL | XFAIL | SKIP |
|---|---:|---:|---:|---:|
| `-O0` (as shipped) | 618 | 22 | 27 | 7 |
| `-O2` | 605 | 35 | 27 | 8 |
| `-O2` + `-Wl,--no-relax` | **618** | **22** | **27** | **8** |

`-O2` with the workaround matches `-O0` exactly. Per-test verdicts are in
[`results/`](results/).

## Contents

| path | what |
|---|---|
| [`ANALYSIS.md`](ANALYSIS.md) | full root-cause writeup: mechanism, evidence, controls, reproduction |
| [`patches/binutils/`](patches/binutils/) | the real fix — 2 lines in `bfd/elf32-microblaze.c` |
| [`patches/rtems/`](patches/rtems/) | RTEMS-side workaround (`-Wl,--no-relax`) + an unrelated non-FDT build fix |
| [`evidence/`](evidence/) | object disassembly, instrumented `ld` traces |
| [`repro/`](repro/) | BSP config, QEMU test runner, reference scanner, `ld` instrumentation |
| [`results/`](results/) | per-test verdicts for the three runs |

## Root cause in brief

`microblaze_elf_relax_section()`, in the "Look through all other sections" loop:

```c
isym = isymbuf + ELF32_R_SYM (irelscan->r_info);   /* index never bounds-checked */

/* Look at the reloc only if the value has been resolved.  */
if (isym->st_shndx == shndx
    && (ELF32_ST_TYPE (isym->st_info) == STT_SECTION))
  {
    ...
    irelscan->r_addend -= calc_fixup (irelscan->r_addend, 0, sec);
  }
```

The adjustment is only ever legitimate for a reference made through the **local section
symbol** of the section being relaxed, but the symbol index is not checked against
`symtab_hdr->sh_info` before indexing `isymbuf`.

`isymbuf` comes from `symtab_hdr->contents`, which by BFD convention holds only
`sh_info` entries — the locals-only cache that `init_reloc_cookie()` installs, and
which is populated by `--gc-sections`, run **before** relaxation. Indexing it with a
*global* symbol's index reads past the end of the allocation. When those bytes happen
to look like `st_shndx == shndx && STT_SECTION`, the addend is decremented by the
number of `imm` instructions relaxation deleted below it.

That fully explains the `--gc-sections` dependency: without it, `symtab_hdr->contents`
is `NULL` at relax time, relax reads the whole symbol table itself, the genuine global
symbol is `SHN_UNDEF`/`STT_NOTYPE`, the guard fails deterministically, and nothing is
corrupted.

## The fix

```diff
 	  for (irelscan = irelocs; irelscan < irelscanend; irelscan++)
 	    {
+	      if (ELF32_R_SYM (irelscan->r_info) >= symtab_hdr->sh_info)
+		continue;
```

Verified: with this applied and relaxation still **enabled**, the same objects link to
the correct address and the failing test gets past its assertion — identical outcome
to `-Wl,--no-relax`.

## Who needs to change

- **binutils** — the actual defect. Unfixed in upstream master. Patch in
  [`patches/binutils/`](patches/binutils/).
- **GCC** — not a bug, but `gcc/config/microblaze/microblaze.h` `LINK_SPEC` has
  `-relax` unconditionally, which is why everyone is exposed. Worth asking whether that
  should still be the default.
- **RTEMS** — needs the workaround now, since it cannot dictate the toolchain.

## Environment

`microblaze-rtems7` toolchain built by the RTEMS Source Builder from
`config/7/rtems-microblaze.bset`:

- GCC 12.4.1 20240905, Xilinx snapshot `gcc-87a5641`
- binutils 2.36.1.20210409, Xilinx snapshot `binutils-gdb-7af075d` plus the 13
  `meta-xilinx` `rel-v2021.1` MicroBlaze patches
- newlib `7d4336cf`
- RTEMS `main` (`fa81c05170`)
- QEMU `qemu-system-microblazeel`, machine `petalogix-s3adsp1800`
