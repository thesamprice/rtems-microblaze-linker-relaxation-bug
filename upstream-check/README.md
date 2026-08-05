# Upstream check

Same two object files, same command line, two linkers, both built with
`-fsanitize=address`.

| log | linker | result |
|---|---|---|
| `binutils-2.36-asan.log` | Xilinx snapshot `binutils-gdb-7af075d` + 13 meta-xilinx patches, 2.36.1.20210409 | heap-buffer-overflow, every run |
| `binutils-2.47.50-asan.log` | upstream master `b7da195b94`, 2.47.50.20260805 | clean |

The difference is not in `elf32-microblaze.c`. Both versions have the same unchecked

```c
isym = isymbuf + ELF32_R_SYM (irelscan->r_info);
```

The difference is `init_reloc_cookie()` in `bfd/elflink.c`.

2.36 reads the local symbols and caches them:

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

2.47.50 does not read symbols at all — the function only computes `num_sym`,
`locsymcount`, `extsymoff` and `r_sym_shift`.

Consequence, traced at the point where relaxation picks up the buffer:

```
XIL-CACHE bfd=relax-addend.o sec=.text.aaa_relaxed contents=CACHED(locals-only) sh_info=6 symcount=10
UP-CACHE  bfd=relax-addend.o sec=.text.aaa_relaxed contents=NULL(full read)     sh_info=6 symcount=10
```

With the full table in hand, index 9 is in bounds and resolves to the real `gvar`
symbol — `SHN_UNDEF`, `STT_NOTYPE` — so
`isym->st_shndx == shndx && ELF32_ST_TYPE (isym->st_info) == STT_SECTION` fails
deterministically and the addend is left alone.

I did not bisect which upstream commit removed the caching; it is somewhere between
2.36 and 2.47.50 and had nothing to do with MicroBlaze.

## What is still true upstream

- The unchecked index is still present in `bfd/elf32-microblaze.c`, in all four
  relocation arms of the `for (irelscan = irelocs; ...)` loop.
- `bfd/elf-eh-frame.c:1638` still does
  `symtab_hdr->contents = (unsigned char *) locsyms;` with a locals-only buffer.

So the precondition is not provably unreachable. I tried to trigger it through
`.eh_frame` and did not succeed — MicroBlaze `as` rejects `.cfi_*` directives, and a
C-compiled `-fasynchronous-unwind-tables` variant did not reproduce either. Treat it
as latent.
