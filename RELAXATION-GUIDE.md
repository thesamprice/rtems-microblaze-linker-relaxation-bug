# A guide to MicroBlaze linker relaxation in BFD

This is the background document for the bug in [`ANALYSIS.md`](ANALYSIS.md). It explains
how the code being patched actually works: why MicroBlaze needs relaxation, how the
linker gets to `microblaze_elf_relax_section()`, what every structure it touches means,
and where the real documentation lives — which, as it turns out, is mostly nowhere.

Read [`README.md`](README.md) first for what the bug is. Read this if you have to
*change* `bfd/elf32-microblaze.c` and want to know what you are standing on.

1. [Why MicroBlaze needs relaxation at all](#1-why-microblaze-needs-relaxation-at-all)
2. [How the linker gets there](#2-how-the-linker-gets-there)
3. [The structures](#3-the-structures)
4. [The `symtab_hdr->contents` convention — the crux](#4-the-symtab_hdr-contents-convention--the-crux)
5. [Walking through `microblaze_elf_relax_section`](#5-walking-through-microblaze_elf_relax_section)
6. [Provenance and maintenance history](#6-provenance-and-maintenance-history)
7. [Other defects in the code as it stands](#7-other-defects-in-the-code-as-it-stands)
8. [Where the documentation is](#8-where-the-documentation-is)
9. [Working on this code](#9-working-on-this-code)

**The short version.** MicroBlaze needs two instructions for a 32-bit constant, and
relaxation deletes the first one when the value turns out to fit in 16 bits. Doing that
means renumbering every offset, addend and symbol in the object — and one of those
renumbering loops indexes a symbol cache that is shorter than it thinks. The loop was
copied from `bfd/elf32-sh.c` in 2009, and the copy dropped sh's bounds check. §6 has the
receipts.

All citations are `file:line` against binutils-gdb master. Line numbers were taken at
`9a54c021d9` and verified byte-identical to `b7da195b94`, the baseline the patch series
in [`patches/binutils/`](patches/binutils/) applies to — so every line number here is
also valid against the patches.

---

## 1. Why MicroBlaze needs relaxation at all

Every MicroBlaze instruction is 32 bits wide. Type B instructions spend 16 of those bits
on an immediate, which the hardware **sign-extends to 32 bits**. UG984 ch.2:

> Type B instructions have one source register and a 16-bit immediate operand (which can
> be extended to 32 bits by preceding the Type B instruction with an `imm` instruction).

The `imm` instruction (opcode `101100`, UG984 p.269) carries the *upper* 16 bits in its
own immediate field and locks them for exactly one following instruction, which supplies
the lower 16. The pair is atomic — the hardware does not take an interrupt between them.

So a full 32-bit constant costs two instructions:

```
	imm	0x9001		; upper half
	lwi	r8, r0, 0x95f4	; lower half -> address 0x900195f4
```

The assembler cannot know a symbol's final address, so it is **pessimistic**: it always
emits the two-word `imm`+insn sequence, and marks it with one of three "64" relocations —
`R_MICROBLAZE_64` (absolute), `R_MICROBLAZE_64_PCREL`, `R_MICROBLAZE_TEXTREL_64`. The
"64" names the *pair width*, not a field width; all three HOWTOs declare `bitsize = 16`
and `dst_mask = 0x0000ffff` with the comment *"Table-entry not really used"*
(`bfd/elf32-microblaze.c:87`, `:117`, `:297`).

**Relaxation is the linker undoing that pessimism.** Once addresses are assigned, a value
that survives a 16→32 sign extension does not need the `imm` at all, and the prefix can be
deleted — 8 bytes become 4. That decision is one test, `bfd/elf32-microblaze.c:1966-1967`:

```c
      if ((symval & 0xffff8000) == 0
	  || (symval & 0xffff8000) == 0xffff8000)
```

Bits 31..15 all zero (value in `[0, 0x7fff]`) or all one (value in
`[0xffff8000, 0xffffffff]`). Anything else keeps its `imm`.

When the `imm` goes, the relocation is rewritten in place to the single-word `_LO` form
(`:1975-1992`):

| before | after |
|---|---|
| `R_MICROBLAZE_64` | `R_MICROBLAZE_32_LO` |
| `R_MICROBLAZE_64_PCREL` | `R_MICROBLAZE_32_PCREL_LO` |
| `R_MICROBLAZE_TEXTREL_64` | `R_MICROBLAZE_TEXTREL_32_LO` |

Deleting an `imm` can bring *another* symbol into 16-bit range, so the pass sets
`*again = true` (`:2360`) and the linker runs the whole thing round again until nothing
more shrinks. **Relaxation here only ever deletes bytes** — the shrink-only invariant that
the rest of BFD assumes everywhere and states nowhere.

GCC turns this on for you whether you asked or not:
`gcc/config/microblaze/microblaze.h` has `-relax` unconditionally in `LINK_SPEC`.

---

## 2. How the linker gets there

This is the chain from the command line to the backend hook. Every hop is a real
`file:line`.

```
ld/lexsup.c:454              "--relax" -> OPTION_RELAX
ld/lexsup.c:1364               ENABLE_RELAXATION
ld/ldmain.h:57                 -> link_info.disable_target_specific_optimizations = 0
ld/ldmain.c:786              link_info.relax_pass = 1          (MicroBlaze uses the default)
ld/ldmain.c:971              main() -> lang_process ()
ld/ldlang.c:8567             lang_process ()
ld/ldlang.c:8927               ldemul_after_allocation ()
ld/emultempl/elf.em:182          gld<emul>_after_allocation ()
ld/emultempl/elf.em:184            bfd_elf_discard_info ()     <-- installs the poisoned cache
ld/emultempl/elf.em:189            ldelf_map_segments ()
ld/ldelfgen.c:266                    lang_relax_sections ()
ld/ldlang.c:8247                     lang_relax_sections ()
ld/ldlang.c:8264                       do { relax_trip++
ld/ldlang.c:8283                            lang_size_sections (&relax_again, false)
ld/ldlang.c:6560                              bfd_relax_section (i->owner, i, &link_info, &again)
bfd/bfd-in2.h:2777                            -> BFD_SEND (abfd, _bfd_relax_section, ...)
bfd/targets.c:463                             BFD_JUMP_TABLE_LINK slot
bfd/elfxx-target.h:1116                       BFD_JUMP_TABLE_LINK (bfd_elfNN)
bfd/elf32-microblaze.c:3530                   #define bfd_elf32_bfd_relax_section \
                                                      microblaze_elf_relax_section
bfd/elf32-microblaze.c:1821                   microblaze_elf_relax_section ()
ld/ldlang.c:8285                       } while (relax_again)
```

Three things in this chain matter for the bug.

**`bfd_elf_discard_info` runs before relaxation, in the same function.**
`ld/emultempl/elf.em:184` calls it; `:189` then calls `ldelf_map_segments`, which reaches
`lang_relax_sections` at `ld/ldelfgen.c:266`. Inside that earlier call,
`_bfd_elf_discard_section_eh_frame()` installs a locals-only symbol cache
(`bfd/elflink.c:15230` → `bfd/elf-eh-frame.c:1638`). The relax pass then reads out of the
end of it. One ASan backtrace catches both ends because they are one call apart.

Every non-Linux MicroBlaze target uses this emulation: `ld/emulparams/elf32microblaze.sh:23`
sets `TEMPLATE_NAME=elf` with no `LDEMUL_AFTER_ALLOCATION` override, and the same holds for
`elf32microblazeel.sh`, `elf32mb_linux.sh`, `elf32mbel_linux.sh`.

**`--relax` is not a boolean.** There is no `command_line.relax`. The state lives in
`link_info.disable_target_specific_optimizations` (`include/bfdlink.h:629`), a tri-state
driven through `ld/ldmain.h:44-58`:

| value | meaning |
|---|---|
| `-1` | default — relaxation off (`ld/ldmain.c:758`) |
| `0` | enabled by the user (`--relax`) |
| `1` | enabled by the target/emulation |
| `2` | disabled by the user (`--no-relax`) |

`ld` uses `getopt_long_only` (`ld/lexsup.c:801`), which is why GCC's single-dash `-relax`
matches the `TWO_DASHES` option. A gotcha worth knowing: a multiple-definition error
silently disables relaxation entirely (`ld/ldmain.c:1604-1608`).

**The `*again` fixed point.** `ld/ldlang.c:8244-8299`:

```c
      int i = link_info.relax_pass;          /* count of passes on entry  */
      link_info.relax_pass = 0;              /* now means "current pass index" */
      while (i--)
	{
	  link_info.relax_trip = -1;
	  do
	    {
	      link_info.relax_trip++;
	      ...
	      lang_size_sections (&relax_again, false);
	    }
	  while (relax_again);
	  link_info.relax_pass++;
	}
```

`relax_pass` is an in/out variable with two different meanings. MicroBlaze takes the
default of `1`, so there is exactly one outer pass with `relax_pass == 0` throughout, and
MicroBlaze reads neither `relax_pass` nor `relax_trip` — zero occurrences in
`elf32-microblaze.c`. Contrast RISC-V (`bfd/elfnn-riscv.c:4911-4932`) and Xtensa
(`bfd/elf32-xtensa.c:6839-6902`), both of which partition their work across explicit
passes and are the two best-written relaxers in the tree to read for comparison.

Note also `ld/ldlang.c:6563` ORs into `*relax` and never clears it: **one section returning
`true` re-runs every section.**

One more asymmetry worth knowing. The generic fallback refuses `-r` with `--relax`
(`bfd/reloc.c:7979-7991`, the familiar *"--relax and -r may not be used together"*), but
MicroBlaze overrides the hook and silently no-ops instead (`bfd/elf32-microblaze.c:1848`),
so `ld -r --relax` on MicroBlaze produces no diagnostic at all.

---

## 3. The structures

Reference map for everything the relax pass touches. `include/bfdlink.h` is at the top
level, **not** `bfd/bfdlink.h`.

### `asection` — `bfd/bfd-in2.h:450`, source `bfd/section.c:160`

The distinction that matters to a relax pass is `size` versus `rawsize`
(`bfd/bfd-in2.h:686-699`):

> `size` — the size of the section in *octets*, as it will be output.
> `rawsize` — for input sections, the original size on disk. **This field should be set
> for any section whose size is changed by linker relaxation.**

| field | bfd-in2.h | section.c |
|---|---|---|
| `flags` | :475 | :186 |
| `size` | :689 | :400 |
| `rawsize` | :699 | :410 |
| `output_offset` | :711 | :422 |
| `output_section` | :714 | :425 |
| `used_by_bfd` | :767 | :478 |

Relevant flags: `SEC_RELOC` (`0x4`, :489), `SEC_CODE` (`0x10`, :495),
`SEC_HAS_CONTENTS` (`0x100`, :518), `SEC_LINKER_CREATED` (`0x100000`, :594).
`microblaze_elf_relax_section` gates on `SEC_RELOC | SEC_CODE` at
`bfd/elf32-microblaze.c:1849-1850`.

### `Elf_Internal_Shdr` — `include/elf/internal.h:102`

`sh_size` (:109), `sh_info` (:111), plus two fields BFD adds that are **not in the ELF
spec** — `bfd_section` (:116) and `contents` (:117), flagged by the comment at :115
(*"The internal rep also has some cached info associated with it."*).

**`sh_info` on `SHT_SYMTAB` is the load-bearing fact in this whole bug.** Per the ELF
gABI it is one greater than the index of the last local symbol — equivalently, the count
of leading `STB_LOCAL` entries, since ELF requires all locals to precede all globals. BFD
leans on this everywhere: `bfd/elflink.c:13880-13881`, `:11405-11406`, `:4837`; the output
side sets it at `bfd/elf.c:8761`.

### `Elf_Internal_Sym` / `Elf_Internal_Rela` — `include/elf/internal.h:130` / `:155`

`st_value` :131, `st_size` :132, `st_info` :134, `st_shndx` :137.
`r_offset` :156, `r_info` :157, `r_addend` :158.

The accessor macros are in `include/elf/common.h`, not `external.h`:
`ELF32_R_SYM` :1173 (`(i) >> 8`), `ELF32_R_TYPE` :1174 (`(i) & 0xff`), `ELF32_R_INFO` :1175,
`ELF_ST_TYPE` :1114, `ELF32_ST_TYPE` :1120.

`Elf_Internal_Rel` no longer exists — modern BFD uses `Elf_Internal_Rela` for both REL and
RELA, zeroing `r_addend` for REL.

### `struct bfd_link_hash_entry` — `include/bfdlink.h:101`

`type` (:107) and the union `u` (:136-200); `u.def.section` :170, `u.def.value` :172.
`enum bfd_link_hash_type` at :72 — the relax pass only acts on `bfd_link_hash_defined`
(:77) and `bfd_link_hash_defweak` (:78). `struct elf_link_hash_entry` wraps it at
`bfd/elf-bfd.h:132` with `root` at :134.

### `struct bfd_link_info` — `include/bfdlink.h:340`

`keep_memory` :417, `disable_target_specific_optimizations` :629, `relax_pass` :691,
`relax_trip` :696. There is **no** `relocatable` field — `bfd_link_relocatable()` at :332
derives it from `type` (:343).

### `elf_obj_tdata` and the accessor macros — `bfd/elf-bfd.h:2129`

```
:2284  elf_tdata(bfd)          ((bfd)->tdata.elf_obj_data)
:2303  elf_symtab_hdr(bfd)     (elf_tdata(bfd)->symtab_hdr)
:2318  elf_sym_hashes(bfd)     (elf_tdata(bfd)->sym_hashes)
:1950  elf_section_data(sec)   ((struct bfd_elf_section_data *)(sec)->used_by_bfd)
```

`elf_sym_hashes(abfd)` holds `symcount - sh_info` entries (allocated at
`bfd/elflink.c:4837`, `:4853`) and is indexed **from zero**, where index 0 is the first
global — i.e. symtab index `sh_info`. That is why the relax pass subtracts `sh_info` at
`bfd/elf32-microblaze.c:1934`.

### The MicroBlaze per-section payload — `bfd/elf32-microblaze.c:718-740`

```c
struct relax_table
{
  bfd_vma addr;   /* Address where bytes may be deleted.  */
  size_t size;    /* Number of bytes to be deleted.  */
};

struct _microblaze_elf_section_data
{
  struct bfd_elf_section_data elf;   /* must be first  */
  size_t relax_count;
  struct relax_table *relax;
};

#define microblaze_elf_section_data(sec) \
  ((struct _microblaze_elf_section_data *) elf_section_data (sec))
```

The standard BFD subclassing idiom: the generic `struct bfd_elf_section_data`
(`bfd/elf-bfd.h:1876`) is embedded **first**, so the downcast in the macro is sound.
Allocated by `microblaze_elf_new_section_hook` at `:742-753`, which stores it into
`sec->used_by_bfd` and then chains to `_bfd_elf_new_section_hook`.

`relax[]` is the deletion list: each entry says "`size` bytes disappear at `addr`".
`calc_fixup(start, size, sec)` (`:1769-1788`) sums the deletions in a range and is the
single primitive the whole pass is built on — every offset, addend, symbol value and
symbol size is corrected by subtracting a `calc_fixup`.

### `struct elf_reloc_cookie` — `bfd/elf-bfd.h:913-924`

```c
struct elf_reloc_cookie
{
  bfd *abfd;
  Elf_Internal_Rela *rels, *rel, *relend;
  unsigned int num_sym;      /* Number of symbols in .symtab.  */
  unsigned int locsymcount;  /* Number of symbols that may be local syms.  */
  unsigned int extsymoff;    /* Symbol index of first possible global sym.  */
  int r_sym_shift;
};
```

There is **no `locsyms` member in current master** — older binutils had one, which is part
of why the 2.36-era and modern reproducers differ. `init_reloc_cookie`
(`bfd/elflink.c:13862-13890`) sets `locsymcount = extsymoff = sh_info` (:13880-13881) and
**reads no symbols at all** in master. `fini_reloc_cookie` (:13894-13898) is an **empty
function** — nothing a cookie consumer cached is ever freed.

---

## 4. The `symtab_hdr->contents` convention — the crux

Everything about this bug reduces to one unwritten rule.

**The rule.** For an input BFD, `symtab_hdr->contents` is an untagged cache of
`Elf_Internal_Sym` whose only guarantee is that it holds **at least `sh_info` entries —
the local symbols**. There is no length field, no sentinel, no discriminator. *A reader
cannot tell a locals-only cache from a full one.*

The contract is set by the canonical consumer, `elf_link_input_bfd`
(`bfd/elflink.c:11419-11434`), which reads exactly `sh_info` entries and never more:

```c
  isymbuf = (Elf_Internal_Sym *) symtab_hdr->contents;
  if (isymbuf == NULL && locsymcount != 0)
    isymbuf = bfd_elf_get_elf_syms (input_bfd, symtab_hdr, locsymcount, 0, ...);
  ...
  isymend = PTR_ADD (isymbuf, locsymcount);
```

**The clearest in-tree statement of the rule is the comment SPU wrote when it needed to
break it** — `bfd/elf32-spu.c:3015-3021`:

```c
      /* Don't use cached symbols since the generic ELF linker
	 code only reads local symbols, and we need globals too.  */
      free (symtab_hdr->contents);
      symtab_hdr->contents = NULL;
      syms = bfd_elf_get_elf_syms (ibfd, symtab_hdr, symcount, 0, NULL, NULL, NULL);
      symtab_hdr->contents = (void *) syms;
```

That is the correct pattern for a backend that needs globals: **discard the cache first,
never trust it.** SPU and MicroBlaze are the only two backends in `bfd/` that install a
full symbol table. SPU does it correctly. MicroBlaze does not.

### `bfd_elf_get_elf_syms()` — `bfd/elf.c:441`

```c
Elf_Internal_Sym *
bfd_elf_get_elf_syms (bfd *ibfd, Elf_Internal_Shdr *symtab_hdr,
		      size_t symcount, size_t symoffset, ...)
```

`symcount` is how many entries the returned buffer will contain — **the number the caller
must remember, because it is not recorded anywhere reachable from `symtab_hdr`.**
`symoffset` is the starting symtab index. Two canonical call shapes:

- `(…, sh_info, 0, …)` — locals only. What almost everyone does.
- `(…, symcount - sh_info, sh_info, …)` — globals only, as `bfd/elflink.c:4844` does.

### Who installs the cache

Roughly forty sites across `bfd/` write `symtab_hdr->contents` for an input BFD. **All but
two install exactly `sh_info` entries** — including `bfd/elfxx-x86.c:1148`,
`bfd/elf32-avr.c:3595`, `bfd/elf32-sh.c:661`, `bfd/elf-m10300.c` (17 sites),
`bfd/elf-m10200.c` (8 sites), `bfd/elfnn-riscv.c:5036`, `bfd/elf32-xtensa.c:6833`,
`bfd/elf32-hppa.c:2510`, `bfd/elf64-ppc.c` (9 sites), `bfd/elf32-arm.c:6777`.

The two that install a **full** symbol table:

| site | verdict |
|---|---|
| `bfd/elf32-spu.c:3022` | **correct** — frees and NULLs the cache first (`:3017-3018`) with the comment above |
| `bfd/elf32-microblaze.c:2337` | **incorrect** — adopts whatever was already cached |

The one that matters for the modern reproducer is
**`_bfd_elf_discard_section_eh_frame()`, `bfd/elf-eh-frame.c:1638`**:

```c
  if (changed)
    {
      Elf_Internal_Sym *locsyms = adjust_eh_frame_local_symbols (sec, cookie);
      if (locsyms != NULL)
	{
	  Elf_Internal_Shdr *symtab_hdr = &elf_symtab_hdr (abfd);
	  symtab_hdr->contents = (unsigned char *) locsyms;   /* line 1638 */
	}
    }
```

The buffer comes from `adjust_eh_frame_local_symbols` (`:1448-1493`), which reads
`cookie->locsymcount` entries at `:1468-1470` — and `locsymcount == sh_info`
(`bfd/elflink.c:13880`). **Entry count installed: `sh_info`.** It is installed only when a
local symbol in `.eh_frame` actually moved (the guard at `:1489-1492`), and it is never
freed, because `fini_reloc_cookie` is empty.

For the 2.36-era reproducer the installer was `init_reloc_cookie()` under `--gc-sections`.
**That is gone in master** — `bfd/elflink.c:13862-13890` now contains no assignment to any
`contents` field and no call to `bfd_elf_get_elf_syms`. If you are debugging a vendor tree
(Xilinx ships 2.36), check that function in *your* source; the behaviour genuinely differs
between versions. This is the reason an earlier draft of this repository wrongly concluded
upstream was unaffected: the old route went quiet, the defect did not.

### What MicroBlaze does with it

`bfd/elf32-microblaze.c:1862-1869`:

```c
  symtab_hdr = &elf_symtab_hdr (abfd);
  isymbuf = (Elf_Internal_Sym *) symtab_hdr->contents;
  symcount =  symtab_hdr->sh_size / sizeof (Elf32_External_Sym);
  if (isymbuf == NULL)
    isymbuf = bfd_elf_get_elf_syms (abfd, symtab_hdr, symcount, 0, NULL, NULL, NULL);
  BFD_ASSERT (isymbuf != NULL);
```

It **adopts an existing cache unconditionally**, then assumes that buffer holds `symcount`
= *all* symbols. Those two lines disagree about what the buffer contains, and nothing
reconciles them. It then indexes with unclamped `ELF32_R_SYM(...)` at seven sites:

| site | guarded? |
|---|---|
| `:1917` | yes — `:1912` `ELF32_R_SYM (...) < symtab_hdr->sh_info` |
| `:2023` | yes — `:2021`, same test |
| `:2090` | **no** |
| `:2122` | **no** |
| `:2159` | **no** |
| `:2205` | **no** — this is the one that corrupts `_Per_CPU_Information + 0x18` |
| `:2239` | **no** |

The five unguarded sites are all inside the *"Look through all other sections"* loop
(`:2064`), and each dereferences `isym->st_shndx` / `isym->st_info` immediately. The fix in
[`patches/binutils/0001`](patches/binutils/) adds the same guard the other two sites
already have, once, at the top of that loop.

---

## 5. Walking through `microblaze_elf_relax_section`

`bfd/elf32-microblaze.c:1821-2370`. Six phases. It has **no header comment** — compare
`bfd/elfnn-riscv.c:4911-4915`, which explains its pass structure before the first line of
code.

**Phase 0 — bail out (`:1843-1869`).** `*again = false`. Skip unless this is a
non-relocatable link of a section with both `SEC_RELOC` and `SEC_CODE` and a non-NULL
`sdata`. Initialise `sec->size` from `sec->rawsize` on first entry. Then acquire `isymbuf`
as above.

**Phase 1 — decide what to delete (`:1884-1994`).** Walk this section's relocations. For
each `R_MICROBLAZE_64`, `_64_PCREL` or `_TEXTREL_64`, resolve the target: local symbols via
`isymbuf` and `_bfd_elf_rela_local_sym` (`:1912-1928`, correctly guarded by `sh_info`),
globals via `elf_sym_hashes` (`:1929-1948`). Adjust for PC- or text-relative form
(`:1950-1964`). Apply the sign-extension test (`:1966`). If it passes, append an entry to
`sdata->relax[]` and rewrite the relocation to its `_LO` form.

Nothing has been deleted yet. Phase 1 only builds the deletion list.

**Phase 2 — fix up this section's own relocations (`:1996-2062`).** Every reloc offset
moves down by `calc_fixup(r_offset)` (`:2007`). Addends of `_64`/`_32_LO`/`_TEXTREL_*`
relocations are corrected **only for references through the local section symbol of the
section being relaxed** — that is what the guarded test at `:2021-2027` checks, and it is
the *correct* form of the check that the next phase is missing. The `_NONE`/`_32_NONE`/
`_64_NONE` arms (`:2030-2059`) handle already-resolved PC-relative pairs by rewriting the
instruction immediate directly.

**Phase 3 — fix up every *other* section of the same object (`:2064-2285`).** This is where
the bug lives. For each sibling section with relocations, scan them and apply the same
kind of addend correction. The intent is identical to phase 2 — catch references made
through this section's local section symbol from elsewhere in the same object file — but
the `sh_info` guard was not carried across. Five unguarded `isymbuf + ELF32_R_SYM(...)`
reads, each immediately dereferenced.

The arms are, in source order: `R_MICROBLAZE_32`/`_32_NONE` (`:2087`), with
`_32_SYM_OP_SYM` nested inside it (`:2120`); `_32_PCREL_LO`/`_32_LO`/`_TEXTREL_32_LO`
(`:2153`); `_64`/`_TEXTREL_64` (`:2201`); `_64_PCREL` (`:2237`). Each repeats the same
twenty-line "load the section contents if we have not already" block — five near-identical
copies, which is a good part of why the missing guard is hard to see by eye.

**Phase 4 — move the symbols (`:2287-2315`).** Local symbols defined in this section have
`st_value` and `st_size` reduced by `calc_fixup` (`:2289-2297`); this loop is correctly
bounded by `sh_info` at `:2288`. Globals are then walked through `elf_sym_hashes`
(`:2300-2315`).

**Phase 5 — actually delete the bytes (`:2317-2338`).** One `memmove` per deletion,
`sec->size` reduced as it goes, then the relocs, contents and `isymbuf` are cached back
into the section and `symtab_hdr`. `*again = true` if anything was deleted (`:2360`),
which contradicts the comment at `:1843-1844` claiming the pass runs once per section.

---

## 6. Provenance and maintenance history

The obvious question about a defect this old is how it survived. The history answers it
precisely: **the code was copied from another backend in 2009, the copy dropped a bounds
check the original already had, and every later hardening sweep that fixed the original
skipped MicroBlaze.**

### Origin

| | |
|---|---|
| commit | `7ba29e2a41ab1802c0e56ce97b290d5f0aece80e` |
| date | 2009-08-06 |
| committer | Nick Clifton (landing a Xilinx drop; 15 `bfd/` files) |
| subject | *Add support for Xilinx MicroBlaze processor.* |

`bfd/elf32-microblaze.c` has never been renamed, and `microblaze_elf_relax_section` was
present in that first commit (at line 1274 of 3058), along with `calc_fixup`, the
*"Look through all other sections"* comment, and the `irelscanend` loop. Relaxation is
original Xilinx-drop code, not a later addition.

### It was copied from `bfd/elf32-sh.c`

Specifically from `sh_elf_relax_delete_bytes()`, which itself descends from
`sh_relax_delete_bytes()` in `coff-sh.c`. Confidence is very high, on identifiers that
appear in **only three files in all of `bfd/`** — `elf32-microblaze.c`, `elf32-sh.c`,
`coff-sh.c`, and nothing else:

- the variable names `irelscan`, `irelscanend`, `nraddr`, `ocontents`
- the comment *"We always cache the relocs. Perhaps, if info->keep_memory is FALSE, we
  should free them, if we are permitted to."*
- the comment *"We always cache the section contents."*
- the loop predicate `if (o == sec || (o->flags & SEC_RELOC) == 0 || o->reloc_count == 0)
  continue;`

The broader idioms — *"Adjust the local symbols defined in this section"*, *"Get the new
reloc address"* — are shared by about twenty backends and prove nothing on their own. The
three-file set does. MicroBlaze uses the ELF API (`_bfd_elf_link_read_relocs`,
`Elf_Internal_Rela`), so the parent is `elf32-sh.c` rather than the COFF original.

The clincher is an edit. sh's comment ends *"…if we are permitted to, when we leave
`sh_coff_relax_section`."* The MicroBlaze copy keeps the comment verbatim but **deletes the
sh-specific trailing clause** — the signature of a deliberate copy-and-adapt, not
convergent evolution.

### The guard was dropped at copy time

This is the finding that matters. `bfd/elf32-sh.c` has, in its other-sections loop:

```c
	  if (ELF32_R_SYM (irelscan->r_info) >= symtab_hdr->sh_info)
	    continue;

	  isym = isymbuf + ELF32_R_SYM (irelscan->r_info);
```

That guard is in **the first commit in binutils git history** — `252b5132c7`, 1999-05-03,
the CVS→git seed. It was therefore already ten years old and demonstrably present in
`elf32-sh.c` **on the very day MicroBlaze landed**: `git show 7ba29e2a41:bfd/elf32-sh.c`
has it at line 1230.

The MicroBlaze copy from that same commit has no `sh_info` reference anywhere in its
other-sections loop. The author kept sh's `sh_info` guards in the *same-section* loop
(today's `:1912` and `:2021`) and dropped the one in the *other-sections* loop (today's
`:2090`, `:2122`, `:2159`, `:2205`, `:2239`).

**So this is not a case of the ancestor being fixed while MicroBlaze was not. It is a copy
defect, present from the first line of the port, on 2009-08-06.**

The two backends also diverged on how they obtain the buffer, which is what turns a missing
guard into a heap overflow:

```
bfd/elf32-sh.c:574-582                    bfd/elf32-microblaze.c:1862-1869
  isymbuf = symtab_hdr->contents;           isymbuf = symtab_hdr->contents;
  if (isymbuf == NULL)                      symcount = symtab_hdr->sh_size
    isymbuf = bfd_elf_get_elf_syms (                   / sizeof (Elf32_External_Sym);
      abfd, symtab_hdr,                     if (isymbuf == NULL)
      symtab_hdr->sh_info, 0, ...);           isymbuf = bfd_elf_get_elf_syms (
  if (isymbuf == NULL)                          abfd, symtab_hdr, symcount, 0, ...);
    goto error_return;                      BFD_ASSERT (isymbuf != NULL);
```

sh reads **`sh_info` locals**, which matches the `symtab_hdr->contents` convention in §4,
and **errors out** on NULL. MicroBlaze reads **all `sh_size/16` symbols** when it allocates
the buffer itself, yet happily consumes a `sh_info`-sized buffer installed by someone
else — and on NULL it only `BFD_ASSERT`s, which prints and continues (§7.6).

### And then the sweeps skipped it

`elf32-sh.c` has since been hardened again. `3a574cce26` (2023-02-22, Alan Modra,
*"Test SEC_HAS_CONTENTS in relax routines"*) swept **23 `bfd/` files** — `coff-sh.c`,
`elf-m10200.c`, `elf32-arc.c`, `elf32-avr.c`, `elf32-cr16.c`, `elf32-crx.c`,
`elf32-epiphany.c`, `elf32-ft32.c`, `elf32-h8300.c`, `elf32-ip2k.c`, `elf32-m32c.c`,
`elf32-m68hc11.c`, `elf32-msp430.c`, `elf32-pru.c`, `elf32-rl78.c`, `elf32-rx.c`,
`elf32-sh.c`, `elf32-v850.c`, `elf64-alpha.c`, `elf64-ia64-vms.c`, `elfnn-ia64.c`,
`elfnn-riscv.c`, `elfxx-mips.c`.

**`bfd/elf32-microblaze.c` is absent from that list**, and it touched exactly the two places
MicroBlaze also has. Today `:1847` and `:2071` still lack the test. (In fairness the
prologue at `:1847` does test `SEC_CODE`, which in practice implies contents, so that hunk
is largely moot; the other-sections loop at `:2071` tests neither, and that is a real gap.)

It is a pattern, not an isolated miss:

| commit | date | subject | `bfd/` files | MicroBlaze? |
|---|---|---|---|---|
| `1f4361a77b` | 2020-02-19 | `_bfd_mul_overflow` | 21 | no |
| `2bb3687ba8` | 2020-02-19 | `_bfd_alloc_and_read` | 33 | no |
| `56ba7527d2` | 2022-12-16 | `bfd_get_relocated_section_contents` NULL buffer | 18 | no |
| `81ff113f78` | 2023-02-22 | Test `SEC_HAS_CONTENTS` before reading contents | 21 | no |
| `3a574cce26` | 2023-02-22 | Test `SEC_HAS_CONTENTS` in relax routines | 23 | no |
| `3a8864b3aa` | 2025-01-13 | reloc caching | 4 | no |
| `4b738eecc0` | 2025-10-30 | Sanity check `elf_sym_hashes` indexing | 6 | no |

The last one is almost painful in hindsight. Its commit message reads: *"I'm a little
surprised we haven't already had fuzzing reports of indexing off the end of sym_hashes.
The idea here is to preempt such bugs."* It hardened `_bfd_elf_get_link_hash_entry`,
`elf-eh-frame.c`, x86 and ppc64 — and did not reach the hand-rolled
`elf_sym_hashes (abfd)[sym_index]` at `bfd/elf32-microblaze.c:2304`.

**No commit in the entire history of `bfd/elf32-microblaze.c` has ever added a bounds check
to the relax function.**

### Seventeen years of maintenance, in one table

`bfd/elf32-microblaze.c` has **107 commits** (2009-08-06 → 2026-05-07). Thirteen are pure
copyright-year bumps. Of the rest, the overwhelming majority are tree-wide mechanical
sweeps: Alan Modra has 65 commits, H.J. Lu 13, Nick Clifton 10 — `bfd_boolean`→`bool`,
`%pA`/`%pB` message conversion, whitespace, `bfd_size_type`→`size_t`, the
`bfd_section_*` macros, dyn_relocs consolidation. Genuine MicroBlaze-specific work is a
thin seam of about a dozen commits by Michael Eager, Neal Frager, Rich Felker and
Gopi Kumar Bulusu.

The relax function itself has **17 commits in 17 years**:

| commit | date | author | nature |
|---|---|---|---|
| `7ba29e2a41a` | 2009-08-06 | Nick Clifton | **origin** (Xilinx drop) |
| `91d6fa6a035` | 2009-12-11 | Nick Clifton | mechanical (`-Wshadow`) |
| `f23200ada9c` | 2012-11-09 | Michael Eager | functional (microblazeel) |
| `886e427f80b` | 2012-12-18 | Michael Eager | **bug fix** — PR ld/14736 |
| `0e1862bb401` | 2015-08-18 | H.J. Lu | mechanical (`output_type`) |
| `07d6d2b8345` | 2017-12-06 | Alan Modra | mechanical (whitespace) |
| `3f0a5f17d7f` | 2018-04-17 | Michael Eager | functional (TEXTREL relocs) |
| `c95949892f6` | 2020-05-20 | Alan Modra | mechanical (`free()` tidy) |
| `0a1b45a20ea` | 2021-03-31 | Alan Modra | mechanical (`bool`) |
| `9bc8e54b1f1` | 2021-12-03 | Simon Marchi | mechanical (clang 13 `-Wunused`) |
| `9751574e09a` | 2022-04-03 | Alan Modra | refactor (relax table → target data) |
| `6bbf249557b` | 2023-10-05 | Neal Frager | functional (bit-field insns) |
| `a3f61244835` | 2023-10-07 | Michael J. Eager | **revert of the above, two days later** |
| `d605374748f` | 2023-10-17 | Neal Frager | functional (`R_MICROBLAZE_32_NONE`) |
| `364081efa5d` | 2023-11-10 | Michael J. Eager | mechanical (formatting) |
| `1cfce7750ae` | 2025-07-18 | Alan Modra | mechanical (unused var) |
| `b8b225cc68c` | 2026-04-17 | Alan Modra | mechanical (`elf_symtab_hdr`) |

`calc_fixup` has **five commits ever**.

**Exactly one bug fix has ever been made to MicroBlaze relaxation** — `886e427f80`
(2012-12-18, PR ld/14736), which changed `calc_fixup (addr, sec)` to
`calc_fixup (start, size, sec)` and added the end-of-range test. Two zero-maintenance gaps
bracket it: 2012-12 → 2018-04 (5 years 4 months) and 2018-04 → 2023-10 (5 years 6 months),
with no functional change of any kind in either.

`gas/config/tc-microblaze.c` has the same profile: 75 commits, ~60% Modra/Clifton sweeps,
a Beulich cleanup run in 2024-25, and a handful of real Xilinx changes.

### Why nobody noticed

`ld/testsuite/ld-microblaze/` **has never existed upstream**. Compare its peers:

| directory | first commit |
|---|---|
| `ld-sh` | 1999-05-03 (initial import) |
| `ld-h8300` | 2002-11-15 |
| `ld-crx` | 2004-09-03 |
| `ld-mn10300` | 2007-10-19 — *"Add MN10300 linker relaxation support…"* |
| `ld-nds32` | 2013-12-13 |
| `ld-avr` | 2014-04-10 |
| `ld-pru` | 2016-12-30 |
| `ld-msp430-elf` | 2017-08-29 |
| `ld-riscv-elf` | 2017-09-23 |
| **`ld-microblaze`** | **never** |

The only thing in the tree that has ever exercised MicroBlaze relaxation is a *linker* test
parked in the *gas* testsuite — `gas/testsuite/gas/microblaze/relax_size.exp`, smuggled in
by `886e427f80`, the 2012 bug fix. It defines its own `ld_run`/`readelf_run` helpers, is
gated on `microblaze*-*-elf`, and diffs `readelf -s` output only: symbol values and section
sizes after relaxation, never reloc addends in other sections. Its inputs declare no global
symbols at all. It cannot reach this code path, and it has been touched once since (2020,
tcl hygiene).

That is the whole story. Copied code, one guard dropped, no tests, no architecture
maintainer (§8), and seventeen years of sweeps that went around it.

---

## 7. Other defects in the code as it stands

The relaxation bug this repository documents is not the only thing wrong with this
function. What follows is a review of the rest of it.

**Provenance and confidence.** These were found by reading the code against the BFD
helpers and against the equivalent code in AVR, m10200 and h8300 — the backends that share
this function's ancestry. **They are not reproduced, and none has a test case here.**
That is a weaker standard of evidence than the rest of this repository, which is built on
ASan traces and testsuite deltas, and they are presented at that lower confidence
deliberately. Treat them as leads for someone with a build tree, not as established
results. Severity ordering is my judgement.

Line numbers are `bfd/elf32-microblaze.c` at `b7da195b94`.

### 7.1 Double-free of cached section contents under `--no-keep-memory`

`:1907` publishes the freshly-read section contents into the BFD-wide cache:

```c
1907	      elf_section_data (sec)->this_hdr.contents = contents;
```

and `:2343-2351` then frees the same buffer without clearing the cache entry:

```c
2345	      if (!link_info->keep_memory)
2346		free (free_contents);
```

Three consumers then hold a dangling pointer: `bfd/elflink.c:11716-11718`
(`elf_link_input_bfd` reads freed memory into the output image), `bfd/elf.c:10216-10221`
(`_bfd_elf_free_cached_info` **frees it again**), and this function's own other-sections
loop on a later section, which reads *and writes* through it.

Trigger: `ld --relax --no-keep-memory` on any code section that has relaxable relocations
but where none are in range — `contents` gets allocated and published, `relax_count` stays
0, so the block at `:2331-2338` that would have transferred ownership is skipped.

AVR gets this right at `bfd/elf32-avr.c:3155-3165`, guarding the free with
`elf_section_data (sec)->this_hdr.contents != contents`.

### 7.2 Double-free of cached relocations on the second relax trip

`:1871-1875` sets `free_relocs = internal_relocs` whenever `keep_memory` is false. But
`_bfd_elf_link_info_read_relocs` short-circuits on a cached array
(`bfd/elflink.c:2910-2911`), so on any trip after the one that ran `:2331`
(`elf_section_data (sec)->relocs = internal_relocs`), `internal_relocs` **is** the cached
array — and `:2340` frees it while the cache still points there.

Since the pass sets `*again = true`, the second trip always happens. AVR again has the
guard: `bfd/elf32-avr.c:3167-3168`.

Both 7.1 and 7.2 are gated on `--no-keep-memory`, which is why the RTEMS builds never hit
them.

### 7.3 Symbol sizes are computed from the already-adjusted symbol value

`:2293-2295`, and identically for globals at `:2309-2313`:

```c
2293	      isym->st_value -= calc_fixup (isym->st_value, 0, sec);
2294	      if (isym->st_size)
2295		isym->st_size -= calc_fixup (isym->st_value, isym->st_size, sec);
```

`calc_fixup` works entirely in **pre-relaxation** coordinates — `relax[i].addr` holds
original `r_offset` values. Line 2293 rewrites `st_value` into *post*-relaxation
coordinates, and line 2295 then feeds that back in, shifting the window
`[start, start+size)` down by the number of bytes deleted below the symbol.

Worked example. `.text` has `f1` at `0x00` size `0x40`, `f2` at `0x40` size `0x10`, and
relaxation deletes the `imm` at `0x3c`:

| | computed | correct |
|---|---|---|
| `f2` new `st_value` | `0x3c` | `0x3c` ✓ |
| `f2` new `st_size` | `calc_fixup(0x3c, 0x10)` = 4 → `0x0c` | `calc_fixup(0x40, 0x10)` = 0 → `0x10` |

`f2` lost no bytes, but its recorded size shrinks by 4. The mirror case under-shrinks: a
deletion inside the symbol's last few bytes is missed entirely.

This is metadata corruption only — no wrong instruction is emitted — which is presumably
why it has gone unnoticed. It shows up as wrong `nm -S` sizes, wrong `objdump -d` function
boundaries, bad GDB frame attribution at function tails, and misattributed addresses in
anything that consumes `st_size` (RTEMS symbol tables, profilers, backtracers).

Fix: save the original value before the first subtraction and pass that to both calls.

### 7.4 The `R_MICROBLAZE_32_SYM_OP_SYM` arm is unreachable

`:2120` is an `else if` on the **inner** test at `:2093`, and both sit inside the outer
type test at `:2087`:

```
2087  if (type == R_MICROBLAZE_32 || type == R_MICROBLAZE_32_NONE)
2089    {
2093      if (isym->st_shndx == shndx && ELF32_ST_TYPE (...) == STT_SECTION)
2095        { ... }
2120      else if (type == R_MICROBLAZE_32_SYM_OP_SYM)     <-- unreachable
2121        { ... }
2152    }
2153  else if (type == 32_PCREL_LO || 32_LO || TEXTREL_32_LO)
```

`R_MICROBLAZE_32` is 1, `_32_NONE` is 33, `_32_SYM_OP_SYM` is 10. The outer condition and
the inner `else if` are mutually exclusive, so `:2121-2151` has **never executed since the
port was written in 2009**. It should be a sibling of the `:2087` test.

Two things follow, and they matter together:

- Symbol-difference values (`.long A - B`) in a sibling section that bracket deleted
  instructions are never corrected. `relocate_section` handles this relocation with
  `break; /* Do nothing. */` (`:1273-1274`), so the value lives entirely in the section
  contents — nothing else fixes it up.
- **Un-nesting the arm would not fix that.** The dead code reads `ocontents` and then only
  adjusts `irelscan->r_addend`, which `relocate_section` ignores for this type. It never
  writes `ocontents`. It also adds `isym->st_value` to the `calc_fixup` argument
  (`:2147-2150`), inconsistent with every other `calc_fixup` call in the function.

So the honest report is "this arm is dead **and** wrong", not "move a brace". Un-nesting it
alone would activate thirty lines that have never run.

### 7.5 Two memory leaks

**`sdata->relax`** — `:1878` allocates unconditionally, overwriting the previous pointer.
It is freed only when `relax_count == 0` (`:2356`) or on error (`:2366`). The
`relax_count > 0` path returns with `*again = true` and the buffer live, and the next trip
overwrites the pointer. `(reloc_count + 1) * 16` bytes per section per productive trip, on
every `--relax` link.

**`isymbuf`** — `bfd_elf_get_elf_syms` (`:1867`) returns a fresh `bfd_malloc`'d buffer, and
the only place it is given an owner is `:2337`, which is **inside** the
`relax_count > 0` block. Every section that does not relax — the majority, plus the final
trip of every section that does — leaks the whole symbol table. On current master
`symtab_hdr->contents` is usually NULL at relax time, so this fires for most objects.

AVR's `retrieve_local_syms` (`bfd/elf32-avr.c:2191-2206`) is the shape to copy: read
`sh_info` entries and install them into `symtab_hdr->contents` **immediately**, so
ownership is never ambiguous. Doing that here would also make the buffer's length and its
declared meaning agree, which is half of the fix for the main bug.

### 7.6 `BFD_ASSERT` is not a check

`:1869` `BFD_ASSERT (isymbuf != NULL);` — and `:1936` `BFD_ASSERT (h != NULL);`.

`BFD_ASSERT` (`bfd/libbfd.h:738-741`) calls `bfd_assert` (`bfd/bfd.c:2303-2308`), which
prints a line and **returns**. It is not `ATTRIBUTE_NORETURN` — only `_bfd_abort` is — and
there is no debug-only variant. So a failed assertion falls straight through into the
NULL dereference at `:1917`.

`bfd_elf_get_elf_syms` returns NULL on allocation failure, on a short read of a truncated
object, and unconditionally when `symcount == 0` (`bfd/elf.c:466-467`) — reachable on a
stripped object that has a `.rela.text` but no `.symtab`. Should be
`if (isymbuf == NULL) goto error_return;`.

### 7.7 `sec->rawsize` is never set for the section being shrunk

`bfd/bfd-in2.h:691-698` says `rawsize` "should be set for any section whose size is changed
by linker relaxation". Nothing here does that for `sec` before `:2327` shrinks it — while
`:2105`, `:2135`, `:2177`, `:2221`, `:2257` set it opportunistically for *other* sections.
That inconsistency is the tell.

Consequences: `bfd_get_section_limit_octets` (`bfd/bfd-in2.h:2510-2516`) bounds
`bfd_get_section_contents` by `rawsize` when set, so a re-read of a shrunken section is
silently truncated; and `ld/ldlang.c:5814-5818` uses `i->rawsize && i->rawsize != i->size`
to raise the fatal *"Relaxation not supported with --enable-non-contiguous-regions"*
diagnostic, which on MicroBlaze is therefore unreliable. In practice `ld/ldlang.c:8094`
covers the first case, but the backend is relying on the driver.

### 7.8 Both immediate-reading arms take the target address from a field that carries none

`:2190-2197` (the `_32_LO` / `_32_PCREL_LO` / `_TEXTREL_32_LO` arm):

```c
2190	      unsigned long instr = bfd_get_32 (abfd, ocontents + irelscan->r_offset);
2191	      immediate = instr & 0x0000ffff;
2192	      target_address = immediate;
2193	      offset = calc_fixup (target_address, 0, sec);
2194	      immediate -= offset;                            /* dead store */
2195	      irelscan->r_addend -= offset;
2196	      microblaze_bfd_write_imm_value_32 (abfd, ocontents + irelscan->r_offset,
2197						 irelscan->r_addend);
```

Three problems. `immediate` is a **dead store** at `:2194` — the write at `:2196` uses
`r_addend`. The 16-bit field is **not sign-extended**, so a negative displacement `0xffe8`
becomes `0x0000ffe8` and `calc_fixup` sums every deletion in the section. And most
importantly, all three of these HOWTOs are `partial_inplace = false, src_mask = 0` — pure
RELA, where the in-place field carries no information at all and `_bfd_final_link_relocate`
ignores it. The authoritative offset is `r_addend`, which is exactly what the sibling
`R_MICROBLAZE_64` arm uses at `:2233`.

In a freshly assembled object the field is zero, so the arm is inert today — but `:2196`
still unconditionally stuffs `r_addend` into two bytes of *another section's contents*.
**That is an amplification path for the main bug**: whenever the out-of-bounds `isym` read
happens to satisfy `st_shndx == shndx && STT_SECTION` for a `_32_LO` relocation, this write
fires. The known symptom is "one addend silently decremented"; this arm can turn the same
bad guard into "two arbitrary bytes of an arbitrary section overwritten". Worth adding to
the upstream report.

The `R_MICROBLAZE_64_PCREL` arm at `:2269-2281` has the same wrong source but writes
`immediate` back rather than `r_addend`. Neither is right; they are wrong differently.

### 7.9 Smaller items

- **`:1999`** `shndx = _bfd_elf_section_from_bfd_section (abfd, sec);` — return unchecked.
  On `SHN_BAD` every `st_shndx == shndx` guard fails, so no relocation and no symbol is
  adjusted, **while `:2318-2329` still deletes the instructions**. Silent miscompile
  rather than an error.
- **`r_offset` is never bounds-checked** before indexing section contents (`:2042`,
  `:2056`, `:2190`, `:2269`, `:2280`). `elf_link_read_relocs_from_section` validates
  `ELF32_R_SYM` but not `r_offset` (`bfd/elflink.c:2843-2874`), so a crafted object gives
  an out-of-bounds read and a 4-byte out-of-bounds write in the linker.
- **`calc_fixup` assumes `relax[]` is sorted ascending** (`:1781` `break`). The table is
  built in relocation order and nothing sorts it. GAS emits in offset order in practice,
  so this is latent.
- **`memmove` length underflow** (`:2323`): `len` is `size_t`, so two deletable relocations
  sharing an `r_offset` would underflow it. Requires crafted input.
- **`sym_hash` is dereferenced at `:2305` with no NULL check** while `:1936` bothers to
  assert. `elf_sym_hashes` is `bfd_zalloc`'d and the fill loop has `continue` paths that
  leave entries NULL. But AVR, m10200 and h8300 all do exactly the same thing, so this is
  a shared BFD wart rather than a MicroBlaze finding.

### 7.10 Checked and found fine

Recorded so the coverage is legible: the relax-table sizing and sentinel bounds; the
`memmove` and `sec->size` arithmetic (all in one pre-relaxation coordinate system); the
`*again` convergence (the comment at `:1843` is stale, but the loop does terminate — a
relocation can be deleted at most once because trip *N* rewrites it to a `_LO` type that
the trip-1 filter no longer accepts); the hard-coded `true` at `:2079`, which is
**required**, not a bug, because the loop mutates addends in place and only `keep_memory`
preserves them; the `symcount` expression at `:2301`, which matches
`bfd/elflink.c:4832-4856` exactly; indirect/warning symbol unwrapping, which is not needed
because `bfd/elflink.c:5379` stores the unwrapped entry.

One disagreement worth recording rather than resolving. The full-table store at `:2337`
violates the locals-only convention described in §4, but every *consumer* in BFD reads only
a `sh_info`-length prefix, and ownership is consistent (`bfd_elf_get_elf_syms` returns
`bfd_malloc`'d memory; `_bfd_elf_free_cached_info` frees it at `bfd/elf.c:10235`). So the
store is a latent convention violation, not an independently exploitable defect — **all
the harm is on the read side**, which is the bug in `ANALYSIS.md`. It still ought to be
fixed, because the next person to add a full-table consumer will be caught by it.

---

## 8. Where the documentation is

Short answer: there is almost none, and that is itself a finding.

### The relax API

`grep -rni relax bfd/doc/` returns **five lines**, all in the internals manual —
`bfd/doc/bfdint.texi:852-856`, quoted in full:

> `_bfd_relax_section` — Try to use relaxation to shrink the size of a section. This is
> called by the linker when the `-relax` option is used. This is called via
> `bfd_relax_section`. Most targets do not support any sort of relaxation.

That is the entire prose documentation of the relaxation API in binutils. **Zero hits in
`bfd.texi`** — the relax API is not in the user-facing BFD manual at all. `bfd/doc/`
generates `reloc.texi`, `targets.texi`, `section.texi` and `linker.texi` at build time from
the `.c` files (`bfd/doc/local.mk:46-56`), and that list **excludes `bfd/elflink.c`**, so
every relaxation-adjacent comment in `elflink.c` is invisible to the manual.

**The `*again` out-parameter is documented nowhere in BFD.** Not in `reloc.c`, `targets.c`,
`section.c`, `linker.c`, `bfd-in2.h`, `elf-bfd.h`, or any doc file. Its semantics exist
only as emergent behaviour of `ld/ldlang.c:8258-8285` and the OR at `ld/ldlang.c:6563`.
**The shrink-only rule is likewise never stated**; the nearest gesture is
`bfd/section.c:127` ("attached to data which can be shrunk").

The best conceptual prose that *is* in the manual is `bfd/section.c:122-128`:

> The `link_order` is used by the linker to perform relaxing on final code. The compiler
> creates code which is as big as necessary to make it work without relaxing, and the user
> can select whether to relax. […] The linker runs around the relocations to see if any are
> attached to data which can be shrunk, if so it does it on a `link_order` by `link_order`
> basis.

It never names `bfd_relax_section`. BFD says as much about itself in `bfd/README:7-12`:
*"The documentation on using BFD is scanty and may be occasionally incorrect."*

`ld/ld.texi:2485-2525` documents `--relax`, opening with *"An option with machine dependent
effects."* Its cross-reference list at `:2495-2506` names H8/300, Xtensa, M68HC11 and
PowerPC ELF32 — **MicroBlaze is absent, and there is no MicroBlaze section anywhere in
`ld.texi`**. `relax_pass` and `relax_trip` are never mentioned. `ld/ldint.texi`, the ld
internals manual, contains **zero** occurrences of "relax".

**Best reading order if you are new to this:**

1. `bfd/section.c:110-128` — the only conceptual paragraph
2. `bfd/doc/bfdint.texi:852-856` — the API, such as it is
3. `ld/ldlang.c:8244-8299` — the real contract, in code
4. `bfd/elfnn-riscv.c:4911-4932` — the cleanest idiomatic relaxer
5. `bfd/elf32-xtensa.c:6839-6902` — the best architectural map of a multi-pass one

### The structures

- **ELF gABI** — <https://www.sco.com/developers/gabi/latest/contents.html>, ch.4 Object
  Files. The `sh_info`-for-`SHT_SYMTAB` rule is in the Section Header table there. Mirror:
  <https://refspecs.linuxfoundation.org/elf/gabi4+/contents.html>
- **BFD internals** — `bfd/doc/bfdint.texi`; the structure definitions themselves in
  `include/elf/internal.h`, `bfd/elf-bfd.h`, `include/bfdlink.h` are better documented by
  their comments than by any manual.
- **MicroBlaze psABI** — **there is none in the tree.** `include/elf/microblaze.h` says
  only *"This file holds definitions specific to the MICROBLAZE ELF ABI"* (`:22`) with no
  URL, no UG number and no revision. The ABI is asserted, not referenced.
- **Xilinx UG984** — ch.4 (ABI, p.185-196) and ch.5 (ISA, p.197-end). The `imm`
  instruction is on p.269.

### The relocation types — `include/elf/microblaze.h:30-65`

The relaxation-relevant subset, with HOWTO facts from `microblaze_elf_howto_raw`
(`bfd/elf32-microblaze.c:41-542`):

| # | name | HOWTO | notes |
|---|---|---|---|
| 0 | `R_MICROBLAZE_NONE` | :43 | does nothing |
| 1 | `R_MICROBLAZE_32` | :60 | plain 32-bit absolute |
| 3 | `R_MICROBLAZE_64_PCREL` | :88 | bitsize 16, *"Table-entry not really used"*; the PC-relative `imm`+insn pair |
| 4 | `R_MICROBLAZE_32_PCREL_LO` | :103 | the result of relaxing #3 |
| 5 | `R_MICROBLAZE_64` | :118 | bitsize 16; the absolute `imm`+insn pair |
| 6 | `R_MICROBLAZE_32_LO` | :133 | the result of relaxing #5 |
| 9 | `R_MICROBLAZE_64_NONE` | :193 | *"Used for relaxation"*; a resolved PC-relative pair |
| 10 | `R_MICROBLAZE_32_SYM_OP_SYM` | :208 | symbol-minus-symbol; how `.debug_*` survives relaxation |
| 31 | `R_MICROBLAZE_TEXTREL_64` | :298 | the text-relative `imm`+insn pair |
| 32 | `R_MICROBLAZE_TEXTREL_32_LO` | **none** | **has no HOWTO entry** — 33 `HOWTO()` invocations for 34 reloc numbers; `microblaze_elf_howto_table[32]` is left NULL, yet `:1987` rewrites relocations *into* this type |
| 33 | `R_MICROBLAZE_32_NONE` | :178 | declares `size = 2` with `bitsize = 32` — inconsistent with `R_MICROBLAZE_32` at :60, which uses `size = 4` |

The four most relaxation-relevant relocations — `_NONE`, `_64_NONE`, `_32_NONE`,
`_32_SYM_OP_SYM` — carry **no comment at all** in the header.

### Tests

**`ld/testsuite/ld-microblaze/` does not exist upstream.** Grepping all of
`ld/testsuite/` for "microblaze" finds only target-*exclusion* lines in generic tests.
There are zero linker-side MicroBlaze tests, which is a large part of why a defect this old
went unnoticed. The series in [`patches/binutils/`](patches/binutils/) adds the first ones.

The only thing in the tree that exercises `--relax` on MicroBlaze at all lives in the *gas*
testsuite — `gas/testsuite/gas/microblaze/relax_size.exp:16-24` — and it cannot reach this
bug. It drives `ld` through a hand-rolled wrapper, is gated on `microblaze*-*-elf` (so
`microblaze-linux-gnu` never runs it), and asserts on **`readelf -s` output only**: symbol
values and sizes, never section contents or instruction encodings. Its two inputs
(`relax_size.s`, `relax_size2.s`) declare no `.global` symbols at all, so `sh_info` covers
every symbol, there are zero globals, and there is no `.eh_frame`. Every code path this bug
lives on is unreachable from it.

### Maintainers

`MAINTAINERS` has **no per-architecture list and no MicroBlaze entry**; `bfd/`, `ld/`,
`gas/` and `binutils/` are covered collectively at `:16-22`, with patches going to
binutils@sourceware.org. The only MicroBlaze maintainer of record anywhere in the tree is a
*GDB target* entry (`gdb/MAINTAINERS:374-376`). **There is no BFD/LD MicroBlaze
maintainer.**

---

## 9. Working on this code

### Reproducing the bug

Two self-contained reproducers, no RTEMS, no C library, no compiler:

- [`testcase-upstream/`](testcase-upstream/) — for **current master**. Reaches the defect
  through `.eh_frame`, because that is what installs the locals-only cache today.
- [`testcase/`](testcase/) — for **2.36-era** (the Xilinx snapshot RTEMS pins). Reaches it
  through `--gc-sections`, via the `init_reloc_cookie()` route that no longer exists.

Use the right one for the tree you are on, or you will conclude the bug is absent. That is
exactly the mistake an earlier draft of this repository made.

You need an ASan-built `ld` — [`ASAN-GUIDE.md`](ASAN-GUIDE.md) covers building one and
what can and cannot be sanitized. Without ASan the corruption is silent by construction:
the out-of-bounds read only does damage when the bytes it lands on happen to satisfy
`st_shndx == shndx && STT_SECTION`, so a small test case with the identical instruction and
relocation shape usually reads harmless garbage and does nothing.

### Debugging by hand

If you cannot build with ASan, add a diagnostic at each
`isym = isymbuf + ELF32_R_SYM (irelscan->r_info);` that fires when the index is
`>= symtab_hdr->sh_info` and prints the BFD, both section names, the relocation type, the
index, `sh_info`, the addend and the resulting `calc_fixup`. That is what
[`repro/ld-instrumentation.patch`](repro/) does, and on a real MicroBlaze link it reports
out-of-bounds reads immediately — 1588 of them in a single `sp69.exe` link, of which 25
passed the guard and 1 actually corrupted a relocation.

### Things that will mislead you

- **`--relax` is on by default.** GCC's `LINK_SPEC` passes `-relax` unconditionally, so
  "I didn't ask for relaxation" is not true on this target.
- **A multiple-definition error silently disables relaxation** (`ld/ldmain.c:1604-1608`).
  A link that errors and a link that succeeds are not running the same passes.
- **`-O0` is immune.** At `-O0` GCC emits a zero addend and a register offset; zero addends
  cannot be damaged by `calc_fixup`. Every bisection through optimisation levels will point
  at the compiler.
- **The gas testsuite's `relax_size.exp` is a linker test.** If you are looking for where
  MicroBlaze relaxation is tested, it is not under `ld/testsuite/`. And it cannot reach
  this code path — see §6.
- **Line numbers move.** `bfd/bfd-in2.h` is generated; cite the `.c` doc-comment sources
  (`bfd/section.c`, `bfd/reloc.c`, `bfd/targets.c`) when you want a stable reference.

### If you are changing the relax pass

- Add a test to `ld/testsuite/ld-microblaze/`. The series in
  [`patches/binutils/`](patches/binutils/) creates that directory; before it, the target
  had no linker tests at all. `microblaze.exp` is auto-discovered — `ld/Makefile.am`
  passes only `--srcdir` and there is no manifest to update.
- **Check that your test fails without your fix.** The three tests added by patch 0001
  pass with *and* without the bfd guard in a normal build; only ASan distinguishes them.
  That is disclosed honestly in the commit message, and it is the right call — but it
  means a green dejagnu run proves nothing here.
- Model new code on the `R_MICROBLAZE_64` arm at `:2201-2236`, which takes its target
  address from `r_addend` — the RELA-authoritative source. Do not model it on the
  `_32_LO` arm at `:2190`, which reads the in-place field (§7.8).
- Read `bfd/elf32-avr.c`'s `retrieve_local_syms` and its `error_return` path before
  touching anything to do with `isymbuf` ownership. It is the same code family, done
  correctly.
