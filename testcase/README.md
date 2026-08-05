# Minimal testcase

A self-contained, deterministic reproducer for the out-of-bounds read in
`microblaze_elf_relax_section()`. Two assembly files, no RTEMS, no C library,
no compiler — just `as` and `ld`.

## Files

| file | what |
|---|---|
| `relax-addend.s` | the object under test: a relaxing section and a victim section |
| `relax-addend-support.s` | the branch target and `gvar`, laid out after |
| `relax-addend.d` | dejagnu `run_dump_test` stub for `ld/testsuite/ld-microblaze/` — **never executed**, see below |
| `asan-before-fix.log` | ASan report from the unfixed linker |
| `asan-after-fix.log` | same link with the fix — clean |

## Run it

```sh
microblaze-rtems7-as -mlittle-endian -o relax-addend.o relax-addend.s
microblaze-rtems7-as -mlittle-endian -o support.o    relax-addend-support.s
microblaze-rtems7-ld -EL -relax --gc-sections -e _start -Ttext=0x90000000 \
    relax-addend.o support.o -o t.elf

microblaze-rtems7-nm t.elf | grep gvar          # gvar = 0x90000050
microblaze-rtems7-objdump -d t.elf | sed -n '/<zzz_victim>:/,/rtsd/p'
```

`zzz_victim` must load from `gvar + 0x18` = `0x90000068`:

```
9000001c:	b0009000 	imm	-28672
90000020:	e8600068 	lwi	r3, r0, 104
```

A linker that corrupts the addend emits `e8600064` (`gvar + 0x14`).

## What it does and does not guarantee

The **out-of-bounds read is deterministic** — it happens on every run, and ASan
reports it every time. That is the defect.

Whether that read leads to a corrupted addend depends on what is in the adjacent
heap: the guard

```c
isym->st_shndx == shndx && ELF32_ST_TYPE (isym->st_info) == STT_SECTION
```

has to be satisfied by whatever bytes happen to be there. On macOS/arm64 with a
link this small, the bytes past the buffer read as zero and the addend survives —
so `objdump` alone shows a correct link even on an unfixed linker. In a large
link (the RTEMS testsuite: 44 objects, 1588 out-of-bounds reads in a single
`ld` invocation) the bytes eventually do satisfy it and a relocation is silently
damaged.

So:

- **`relax-addend.d`** is a regression test. It pins the correct output and will
  catch a future linker that corrupts the addend deterministically. It will not
  reliably fail on today's unfixed linker.

  **It has never been executed.** There is no `ld/testsuite/ld-microblaze/` directory
  in binutils and no `.exp` driver for this target, so nothing runs it. It is included
  as a starting point for someone adding linker tests to MicroBlaze, not as a working
  test, and not as coverage for this bug — it pins correct output rather than detecting
  the defect.
- **ASan** is the reliable detector, and is what the report below is based on.

## ASan

Build the linker with ASan:

```sh
../binutils-gdb/configure --target=microblaze-rtems7 \
    --disable-gdb --disable-sim --disable-gdbserver --disable-readline \
    --disable-nls --disable-werror --with-system-zlib \
    CC="clang -fsanitize=address -fno-omit-frame-pointer -g -O1" \
    LDFLAGS="-fsanitize=address"
make -j8 all-ld
```

On macOS the bundled zlib needs `-Dfdopen=fdopen` added to `CC` as well; its
classic-Mac-OS branch is guarded on `TARGET_OS_MAC`, which modern macOS also
defines.

Then link the testcase. Unfixed:

```
==16687==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x61000000037c
READ of size 4 at 0x61000000037c thread T0
    #0 microblaze_elf_relax_section elf32-microblaze.c:2155
    #1 lang_size_sections_1 ldlang.c:6088
    ...
    #5 lang_relax_sections ldlang.c:7675

0x61000000037c is located 124 bytes after 192-byte region [0x610000000240,0x610000000300)
allocated by thread T0 here:
    #1 bfd_malloc libbfd.c:275
    #2 bfd_elf_get_elf_syms elf.c:498
    #3 _bfd_elf_gc_mark elflink.c:13720
    #4 _bfd_elf_gc_mark_reloc elflink.c:13681
    #5 _bfd_elf_gc_mark elflink.c:13725
    #6 bfd_elf_gc_sections elflink.c:14277
```

Every element of the diagnosis is in that report:

- **`elf32-microblaze.c:2155`** is `if (isym->st_shndx == shndx` in the
  `R_MICROBLAZE_64` arm of the "Look through all other sections" loop, reached
  from `lang_relax_sections`.
- **The allocation is made by `bfd_elf_get_elf_syms` under `_bfd_elf_gc_mark`**,
  i.e. by `--gc-sections`, which is exactly the locals-only cache
  `init_reloc_cookie()` installs in `symtab_hdr->contents`.
- **192 bytes** = `sh_info` (6) x `sizeof (Elf_Internal_Sym)` (32). The buffer
  really does hold only the local symbols.
- **124 bytes past the end** = offset 316 = entry 9 (`9 * 32 = 288`) plus 28,
  the offset of `st_shndx`. Symbol 9 is `gvar`, the global the relocation refers
  to. **`READ of size 4`** is the `st_shndx` field.

With the fix applied, the same link is clean and the addend is correct.

Reproduced 5/5 runs unfixed, 0/3 fixed.
