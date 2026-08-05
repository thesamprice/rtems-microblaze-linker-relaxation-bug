# MicroBlaze linker relaxation corrupts relocation addends

`ld --relax` for MicroBlaze silently corrupts the addend of `R_MICROBLAZE_64`
relocations that have a non-zero addend. No error, no warning — the program just
loads from the wrong address.

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so **every MicroBlaze
link is exposed by default**.

The defect is in **binutils**, `bfd/elf32-microblaze.c`, and it bites the Xilinx
binutils 2.36 snapshot used by the RTEMS MicroBlaze toolchain.

**It does not reproduce on current upstream binutils** (2.47.50, master of
2026-08-05) — see [Upstream status](#upstream-status). The unchecked array index is
still there, but an unrelated refactor removed the thing that made it reachable.

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
| [`testcase/`](testcase/) | **minimal deterministic reproducer** — two `.s` files, an ASan report, and a dejagnu test |
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

## Minimal reproducer

Two assembly files, no RTEMS, no compiler — see [`testcase/`](testcase/). Under an
ASan-built `ld` the unfixed linker reports, on every run:

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

Measured, not inferred. Identical object files, identical command line, both linkers
built with ASan:

| linker | ASan | linked address | verdict |
|---|---|---|---|
| Xilinx snapshot, binutils 2.36.1 | heap-buffer-overflow, 5/5 runs | corrupt in a large link | **affected** |
| upstream master, 2.47.50.20260805 | clean, 0/3 runs | correct | **not reproducible** |

The reason is not a fix to `elf32-microblaze.c`. It is `init_reloc_cookie()` in
`bfd/elflink.c`. In 2.36 it read the symbol table and cached it:

```c
  cookie->locsymcount = symtab_hdr->sh_info;      /* locals only */
  cookie->locsyms = (Elf_Internal_Sym *) symtab_hdr->contents;
  if (cookie->locsyms == NULL && cookie->locsymcount != 0)
    {
      cookie->locsyms = bfd_elf_get_elf_syms (abfd, symtab_hdr,
					      cookie->locsymcount, 0, ...);
      if (info->keep_memory)
	symtab_hdr->contents = (bfd_byte *) cookie->locsyms;   /* sh_info entries */
    }
```

In current master that whole block is gone — `init_reloc_cookie()` only computes
counts. So `--gc-sections` no longer leaves a locals-only buffer in
`symtab_hdr->contents`, relaxation reads the **full** symbol table itself, and the
unchecked index lands in bounds on the genuine global symbol (`SHN_UNDEF`,
`STT_NOTYPE`). The guard then fails deterministically and no addend is touched.
Traced directly:

```
XIL-CACHE bfd=relax-addend.o sec=.text.aaa_relaxed contents=CACHED(locals-only) sh_info=6 symcount=10
UP-CACHE  bfd=relax-addend.o sec=.text.aaa_relaxed contents=NULL(full read)     sh_info=6 symcount=11
```

So this reads as **fixed upstream by accident**, as a side effect of a refactor that
had nothing to do with MicroBlaze.

Two caveats, so nobody over-reads that:

1. The **unchecked index is still in upstream master** (`bfd/elf32-microblaze.c`, the
   `for (irelscan = irelocs; ...)` loop, all four relocation arms). Nothing stops it
   reading out of bounds the moment anything else populates `symtab_hdr->contents`
   with a locals-only buffer.
2. Something else still does exactly that: `bfd/elf-eh-frame.c:1638`,
   `symtab_hdr->contents = (unsigned char *) locsyms;`, on the `.eh_frame` editing
   path. I tried and **failed** to build a trigger through it, so this is a
   theoretical concern rather than a demonstrated one — but it is why the patch is
   still worth applying.

The patch is therefore offered as **hardening of a latent out-of-bounds read**, not as
a fix for a live upstream regression. That is the honest framing.

## Who needs to change

- **binutils** — the actual defect. Live in 2.36-era; latent but unchecked in master.
  Patch in [`patches/binutils/`](patches/binutils/).
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
