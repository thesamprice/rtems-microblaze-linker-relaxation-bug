# MicroBlaze linker relaxation corrupts relocation addends

`ld --relax` for MicroBlaze silently corrupts the addend of `R_MICROBLAZE_64`
relocations that have a non-zero addend. No error, no warning — the program just
loads from the wrong address.

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so **every MicroBlaze
link is exposed by default**.

The defect is in **binutils**, `bfd/elf32-microblaze.c`. It affects the Xilinx
binutils 2.36 snapshot used by the RTEMS MicroBlaze toolchain **and current upstream
binutils master** (2.47.50.20260805), demonstrated in both cases with an ASan-built
linker and a self-contained reproducer — see [Upstream status](#upstream-status).

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
| [`testcase-upstream/`](testcase-upstream/) | **reproducer for current binutils master** — via `.eh_frame`, plus `make check-ld` results |
| [`testcase/`](testcase/) | reproducer for 2.36-era — via `--gc-sections`, plus an unexecuted dejagnu stub |
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

## Minimal reproducers

Two of them, both self-contained — no RTEMS, no C library, no compiler.
[`testcase-upstream/`](testcase-upstream/) is the one to use against current binutils;
[`testcase/`](testcase/) reaches the same defect via `--gc-sections` and works on
2.36-era. Under an ASan-built `ld` the unfixed linker reports, on every run:

```
ERROR: AddressSanitizer: heap-buffer-overflow
READ of size 4
    #0 microblaze_elf_relax_section elf32-microblaze.c:2155
    ...
    #5 lang_relax_sections ldlang.c:7675

0x61000000037c is located 124 bytes after 192-byte region
allocated by thread T0 here:
    #2 bfd_elf_get_elf_syms elf.c:498
    #3 _bfd_elf_gc_mark elflink.c:13720
    #6 bfd_elf_gc_sections elflink.c:14277
```

192 bytes is `sh_info` (6) x `sizeof (Elf_Internal_Sym)` (32) — the locals-only
cache — and the read is at entry 9, the global the relocation refers to. With the
fix the same link is clean.

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

## Upstream status

Measured, not inferred. ASan-built linkers, deterministic, 5 runs out of 5 each:

| linker | reproducer | ASan | verdict |
|---|---|---|---|
| Xilinx snapshot, 2.36.1.20210409 | [`testcase/`](testcase/), via `--gc-sections` | heap-buffer-overflow | **affected** |
| upstream master, 2.47.50.20260805 | [`testcase-upstream/`](testcase-upstream/), via `.eh_frame` | heap-buffer-overflow | **affected** |

Same defect, two ways in. What changed between the versions is only *which* code
installs the locals-only symbol buffer that relaxation then reads out of bounds:

- **2.36**: `init_reloc_cookie()` in `bfd/elflink.c` cached it under `--gc-sections`.
  That block is gone in master, which is why the first reproducer goes quiet there —
  and why an earlier draft of this repository wrongly concluded upstream was unaffected.
- **master**: `_bfd_elf_discard_section_eh_frame()` still installs it, at
  `bfd/elf-eh-frame.c:1638`, from `bfd_elf_discard_info()`.

And it is installed in exactly the wrong place. `ld/emultempl/elf.em`, the generic ELF
emulation every non-Linux MicroBlaze target uses:

```c
static void
gld${EMULATION_NAME}_after_allocation (void)
{
  int need_layout = bfd_elf_discard_info (&link_info);   /* installs the cache */
  ...
    ldelf_map_segments (need_layout);                    /* calls lang_relax_sections */
}
```

One ASan trace catches both halves:

```
    #0 microblaze_elf_relax_section elf32-microblaze.c:2208
    #5 lang_relax_sections ldlang.c:8286
    #6 ldelf_map_segments ldelfgen.c:266

allocated by thread T0 here:
    #3 _bfd_elf_discard_section_eh_frame elf-eh-frame.c:1634
    #4 bfd_elf_discard_info elflink.c:15239
    #5 gldelf32microblaze_after_allocation eelf32microblaze.c:113
```

**This is not a wider BFD problem.** The guarded idiom is standard elsewhere —
`elf32-avr.c:2028`, `elf-m10200.c:642` — and MicroBlaze gets it right for the section
being relaxed (`elf32-microblaze.c:2021`). Only its *other-sections* loop is unguarded.
Just three files in `bfd/` have such a loop, and the two SH ones do not index `isymbuf`
by relocation symbol inside it. MicroBlaze is the outlier; the fix does not need to grow.

### ld testsuite

`make check-ld`, target `microblaze-xilinx-rtems7`, upstream master: **476 expected
passes, 13 unexpected failures, baseline and patched byte-identical.** The patch changes
no test outcome. The 13 are pre-existing and unrelated — 8 `sysroot-prefix` variants
(host environment), plus `ld-discard/zero-range`, `ld-discard/zero-rel`,
`ld-elf/linkonce1`, `ld-elf/linkonce2`, `ld-elf/pr24511`. Both `.sum` files are in
[`testcase-upstream/`](testcase-upstream/).

There is no `ld/testsuite/ld-microblaze` directory in binutils — MicroBlaze has no
target-specific linker tests at all, which is some of the reason a defect this old went
unnoticed.

## Who needs to change

- **binutils** — the actual defect, live in both 2.36-era and current master. Patch in
  [`patches/binutils/`](patches/binutils/); two lines, no test-outcome change.
- **GCC** — not a bug, but `gcc/config/microblaze/microblaze.h` `LINK_SPEC` has
  `-relax` unconditionally, which is why everyone is exposed. Worth asking whether that
  should still be the default.
- **RTEMS** — needs the workaround now. The MicroBlaze toolchain is pinned to the
  Xilinx binutils 2.36 snapshot by `config/7/rtems-microblaze.bset`, which is squarely
  in the affected range. Moving that pin to a modern binutils would also resolve it,
  and is the better long-term answer, but that is a much larger change than
  `-Wl,--no-relax`.

## Environment

`microblaze-rtems7` toolchain built by the RTEMS Source Builder from
`config/7/rtems-microblaze.bset`:

- GCC 12.4.1 20240905, Xilinx snapshot `gcc-87a5641`
- binutils 2.36.1.20210409, Xilinx snapshot `binutils-gdb-7af075d` plus the 13
  `meta-xilinx` `rel-v2021.1` MicroBlaze patches
- newlib `7d4336cf`
- RTEMS `main` (`fa81c05170`)
- QEMU `qemu-system-microblazeel`, machine `petalogix-s3adsp1800`
