# Reproducer for current upstream binutils

Self-contained. Two assembly files and a linker script — no RTEMS, no C library, no
compiler. Reproduces the out-of-bounds read on **upstream binutils master**
(`b7da195b94`, 2.47.50.20260805), deterministically, 5 runs out of 5.

The other reproducer, [`../testcase/`](../testcase/), reaches the same defect through
`--gc-sections` and only works on binutils 2.36-era. This one reaches it through
`.eh_frame` and works on current master. See [`../upstream-check/`](../upstream-check/)
for why the two differ.

## Run it

```sh
microblaze-rtems7-as -mlittle-endian -o v.o relax-addend-eh.s
microblaze-rtems7-as -mlittle-endian -o s.o relax-addend-eh-support.s
ld -EL -relax --gc-sections -T relax-addend-eh.ld v.o s.o -o t.elf
```

With an ASan-built `ld`:

```
ERROR: AddressSanitizer: heap-buffer-overflow
READ of size 4
    #0 microblaze_elf_relax_section elf32-microblaze.c:2208
    #5 lang_relax_sections ldlang.c:8286
    #6 ldelf_map_segments ldelfgen.c:266
    #7 lang_process ldlang.c:8930

0x6120000007fc is located 156 bytes after 288-byte region
allocated by thread T0 here:
    #2 bfd_elf_get_elf_syms elf.c:565
    #3 _bfd_elf_discard_section_eh_frame elf-eh-frame.c:1634
    #4 bfd_elf_discard_info elflink.c:15239
    #5 gldelf32microblaze_after_allocation eelf32microblaze.c:113
```

Both halves of the bug are in that one trace. `after_allocation()` calls
`bfd_elf_discard_info()`, which allocates a **locals-only** symbol buffer and parks it
in `symtab_hdr->contents`; the same `after_allocation()` then reaches
`lang_relax_sections()`, which indexes that buffer with a **global** symbol index.

288 bytes = 9 local symbols x `sizeof (Elf_Internal_Sym)` (32). The read is 156 bytes
past the end — entry 13 plus 28, the offset of `st_shndx`. Entry 13 is `gvar`, the
global the relocation refers to. `READ of size 4` is the `st_shndx` field.

With the two-line fix applied to the same source: clean, 5 runs out of 5, and the
relocation resolves correctly.

## How it works

Three ingredients have to line up.

1. **A locals-only symbol cache installed before relaxation.**
   `_bfd_elf_discard_section_eh_frame()` calls `adjust_eh_frame_local_symbols()`, which
   caches `cookie->locsymcount` (= `sh_info`) entries in `symtab_hdr->contents` — but
   only if editing the section actually moved a **local symbol defined inside
   `.eh_frame`**. Hence `ehlocal`, and hence `dead_fn`: `dead_fn` is unreferenced, so
   `--gc-sections` drops it, so its FDE is removed, so the section shrinks, so
   `ehlocal` moves.

2. **`.eh_frame` must survive into the output.**
   `bfd_elf_discard_info()` starts with
   `o = bfd_get_section_by_name (info->output_bfd, ".eh_frame")` and does nothing if
   that is `NULL`. Under `--gc-sections` the default linker script lets `.eh_frame` be
   swept, so the whole path is skipped — this is why the script here uses
   `KEEP (*(.eh_frame))`. Without the `KEEP`, nothing happens and the bug appears
   absent.

3. **A relaxable IMM below the victim addend, in a sibling section.**
   `.text.aaa_relaxed` has an `imm` + `brlid` pair that relaxation deletes.
   `.text.zzz_victim`, a different section in the same object, holds
   `R_MICROBLAZE_64 gvar + 0x18`. Relaxing the first walks the relocations of the
   second, and that is where the unchecked index is.

Note the branch target is placed in `.text.zz_support` so it is laid out *after* the
relaxed section. A backward reference is not relaxed and the test would exercise
nothing.

## Why the CIE and FDEs are hand-assembled

`.eh_frame` here uses literal lengths and CIE pointers rather than the usual
label-difference expressions, e.g. `.4byte 16` instead of `.4byte .Lcie_end - .Lcie_start`.

MicroBlaze GAS emits an `R_MICROBLAZE_NONE` marker relocation for every resolved label
difference. Those land in `.rela.eh_frame` and desynchronise `ent->reloc_index`, so
`_bfd_elf_discard_section_eh_frame()` trips

```c
BFD_ASSERT (cookie->rel < cookie->relend
	    && cookie->rel->r_offset == ent->offset + 8);
```

The first draft of this test produced 7 relocations where 2 were wanted, and the
assertion fired on every link. Literals bring `.rela.eh_frame` down to exactly the two
`R_MICROBLAZE_32` FDE initial-location relocations, and the assertion goes away. The
out-of-bounds read is unaffected either way — this is only so the input cannot be
dismissed as malformed.

`.cfi_*` directives are not an option: MicroBlaze GAS answers
`Error: CFI is not supported for this target`.

## ld testsuite

`make check-ld`, target `microblaze-xilinx-rtems7`, upstream master:

| | expected passes | unexpected failures | expected failures | untested | unsupported |
|---|---:|---:|---:|---:|---:|
| baseline | 476 | 13 | 14 | 28 | 223 |
| with the patch | 476 | 13 | 14 | 28 | 223 |

The full `PASS`/`FAIL`/`XFAIL`/`UNTESTED`/`UNSUPPORTED` lists are **byte-identical**
between the two runs — the patch changes no test outcome. Both `.sum` files are here
for checking.

The 13 failures are pre-existing and unrelated: 8 are `sysroot-prefix` variants
(host environment), and 5 are `ld-discard/zero-range`, `ld-discard/zero-rel`,
`ld-elf/linkonce1`, `ld-elf/linkonce2`, `ld-elf/pr24511`.

Worth noting: there is **no `ld/testsuite/ld-microblaze` directory** in binutils.
MicroBlaze has no target-specific linker tests at all, which is some of the reason a
defect this old went unnoticed.
