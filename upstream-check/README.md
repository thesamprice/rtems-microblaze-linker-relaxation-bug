# Upstream status

**Current position: the defect is live in upstream binutils master.** Demonstrated with
an ASan-built linker and a self-contained reproducer, deterministically, 5 runs out of 5.

This file also records how that conclusion was reached, because an intermediate
measurement pointed the other way and the reasoning is worth keeping.

## What happened

The first reproducer ([`../testcase/`](../testcase/)) reaches the bug through
`--gc-sections`. It fires on the Xilinx binutils 2.36 snapshot and is clean on
upstream master:

| linker | first reproducer (`--gc-sections`) |
|---|---|
| Xilinx snapshot, 2.36.1.20210409 | heap-buffer-overflow, 5/5 |
| upstream master, 2.47.50.20260805 | clean |

That is a real difference and the cause is real, but the conclusion drawn from it —
"not reproducible upstream" — was wrong, because it generalised from a single route.

### Why the first reproducer goes quiet upstream

`init_reloc_cookie()` in `bfd/elflink.c`. In 2.36 it read the local symbols and cached
them:

```c
  cookie->locsymcount = symtab_hdr->sh_info;          /* locals only */
  cookie->locsyms = (Elf_Internal_Sym *) symtab_hdr->contents;
  if (cookie->locsyms == NULL && cookie->locsymcount != 0)
    {
      cookie->locsyms = bfd_elf_get_elf_syms (abfd, symtab_hdr,
					      cookie->locsymcount, 0, ...);
      if (info->keep_memory)
	symtab_hdr->contents = (bfd_byte *) cookie->locsyms;
    }
```

In current master that block is gone; the function only computes counts. So
`--gc-sections` no longer leaves a locals-only buffer, relaxation reads the full symbol
table itself, and the unchecked index lands in bounds on the genuine global symbol
(`SHN_UNDEF`, `STT_NOTYPE`). The guard then fails and the addend survives. Traced
directly:

```
XIL-CACHE bfd=relax-addend.o sec=.text.aaa_relaxed contents=CACHED(locals-only) sh_info=6 symcount=10
UP-CACHE  bfd=relax-addend.o sec=.text.aaa_relaxed contents=NULL(full read)     sh_info=6 symcount=10
```

I did not bisect which commit removed the caching; it is somewhere between 2.36 and
2.47.50 and had nothing to do with MicroBlaze.

### The route that is still open

`init_reloc_cookie()` was never the only writer of `symtab_hdr->contents`.
`bfd/elf-eh-frame.c:1638` still does:

```c
  if (changed)
    {
      Elf_Internal_Sym *locsyms = adjust_eh_frame_local_symbols (sec, cookie);
      if (locsyms != NULL)
	symtab_hdr->contents = (unsigned char *) locsyms;   /* cookie->locsymcount entries */
    }
```

and it runs in exactly the wrong place. In `ld/emultempl/elf.em`, the generic ELF
emulation that every non-Linux MicroBlaze target uses:

```c
static void
gld${EMULATION_NAME}_after_allocation (void)
{
  int need_layout = bfd_elf_discard_info (&link_info);   /* installs the cache */
  ...
    ldelf_map_segments (need_layout);                    /* calls lang_relax_sections */
}
```

The cache is installed and then read out of bounds within a single function call.
[`../testcase-upstream/`](../testcase-upstream/) drives that path and produces:

```
    #0 microblaze_elf_relax_section elf32-microblaze.c:2208
    #5 lang_relax_sections ldlang.c:8286
    #6 ldelf_map_segments ldelfgen.c:266

allocated by thread T0 here:
    #3 _bfd_elf_discard_section_eh_frame elf-eh-frame.c:1634
    #4 bfd_elf_discard_info elflink.c:15239
    #5 gldelf32microblaze_after_allocation eelf32microblaze.c:113
```

The blocker that hid this initially was mundane: under `--gc-sections` the default
linker script lets `.eh_frame` be swept out of the output, and
`bfd_elf_discard_info()` begins with
`o = bfd_get_section_by_name (info->output_bfd, ".eh_frame"); if (o != NULL)`. No
output section, no editing, no cache. A script with `KEEP (*(.eh_frame))` opens it.

## Summary

| route | 2.36 | master |
|---|---|---|
| `--gc-sections` via `init_reloc_cookie()` | affected | closed by refactor |
| `.eh_frame` via `_bfd_elf_discard_section_eh_frame()` | affected | **affected** |

Both routes are the same defect: `microblaze_elf_relax_section()` indexing a
locals-only symbol buffer with a global symbol's index. Only the thing that installs
the buffer differs.

## Is this a wider BFD problem?

**No — MicroBlaze looks like the outlier.** Checked, so that a maintainer does not have
to.

The guarded idiom is standard elsewhere. `elf32-avr.c:2028` and `elf-m10200.c:642` both
do exactly what MicroBlaze fails to do:

```c
  if (ELF32_R_SYM (irel->r_info) < symtab_hdr->sh_info)
    {
      /* A local symbol.  */
      isym = isymbuf + ELF32_R_SYM (irel->r_info);
```

MicroBlaze itself gets this right for the section being relaxed —
`elf32-microblaze.c:2021` has the same guard. What is unguarded is the *other-sections*
loop, at lines 2090 and 2122, which walks the relocations of every other section in the
same BFD.

Only three files in `bfd/` have such a loop at all — `coff-sh.c`, `elf32-sh.c` and
`elf32-microblaze.c` — and the two SH ones do not index `isymbuf` by relocation symbol
inside it; they match on relocation type and offset. So this is a MicroBlaze-specific
defect, not a class, and the fix does not need to grow.

## Reproducing the comparison

Both linkers built the same way:

```sh
../binutils-gdb/configure --target=microblaze-rtems7 \
    --disable-gdb --disable-sim --disable-gdbserver --disable-readline \
    --disable-nls --disable-werror --with-system-zlib \
    CC="clang -fsanitize=address -fno-omit-frame-pointer -g -O1" \
    LDFLAGS="-fsanitize=address"
make -j8 all-ld
```

On macOS add `-Dfdopen=fdopen` to `CC`; the bundled zlib's classic-Mac-OS branch is
guarded on `TARGET_OS_MAC`, which modern macOS also defines.

`binutils-2.36-asan.log` and `binutils-2.47.50-asan.log` in this directory are the
first-reproducer runs. The upstream-reproducer logs and the `make check-ld` results are
in [`../testcase-upstream/`](../testcase-upstream/).
