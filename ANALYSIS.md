# MicroBlaze: linker relaxation silently corrupts relocation addends, miscompiling RTEMS at -O2

## Summary

`ld --relax` for MicroBlaze corrupts the addend of `R_MICROBLAZE_64` relocations that
have a non-zero addend. The addend loses 4 bytes for each `imm` instruction the
relaxation pass deleted ahead of it **in a sibling section of the same object file**.
There is no error and no warning — the program simply loads from the wrong address.

GCC's MicroBlaze `LINK_SPEC` passes `-relax` unconditionally, so every MicroBlaze link
is exposed by default.

The defect is in **binutils** (`bfd/elf32-microblaze.c`). It affects the Xilinx
binutils 2.36 snapshot used by the RTEMS MicroBlaze toolchain **and current upstream
binutils master** (2.47.50.20260805) — see "Upstream status" below. Neither GCC nor
RTEMS is at fault, but both need to react:
GCC because it enables the pass by default, RTEMS because it needs a workaround until
binutils is fixed.

## Impact on RTEMS

This is why `bspkcu105.yml` / `bspkcu105_qemu.yml` link `../../opto0`. Building the
MicroBlaze BSPs at `-O2` regresses 16 testsuite tests against `-O0`, all with a thread
identity / resource ownership signature:

```
psx10  psxcleanup  psxcond01  psxkey07  psxtmcond03  psxtmcond06  psxtmcond11
rtmonuse  sp32  sp46  sp60  sp69  spedfsched02  spintrcritical08
spratemon_err01  tm29
```

`-O0` masks it because at `-O0` GCC materialises the base symbol with a **zero** addend
and then uses a register offset (`lwi rD, rBase, 24`); zero addends are immune. At
`-O2` GCC folds the member offset into the relocation addend, and the bug bites.

## Root cause

`microblaze_elf_relax_section()` in `bfd/elf32-microblaze.c`, in the
"Look through all other sections" loop:

```c
	  irelscanend = irelocs + o->reloc_count;
	  for (irelscan = irelocs; irelscan < irelscanend; irelscan++)
	    {
	      ...
	      if (ELF32_R_TYPE (irelscan->r_info) == (int) R_MICROBLAZE_64
		  || ELF32_R_TYPE (irelscan->r_info) == (int) R_MICROBLAZE_TEXTREL_64)
		{
		  isym = isymbuf + ELF32_R_SYM (irelscan->r_info);   /* <-- unchecked index */

		  /* Look at the reloc only if the value has been resolved.  */
		  if (isym->st_shndx == shndx
		      && (ELF32_ST_TYPE (isym->st_info) == STT_SECTION))
		    {
		      ...
		      offset = calc_fixup (irelscan->r_addend, 0, sec);
		      immediate -= offset;
		      irelscan->r_addend -= offset;      /* <-- the corruption */
		    }
		}
```

The adjustment is only ever legitimate for a reference made through the **local section
symbol** of the section being relaxed. But the symbol index is not bounds-checked
before indexing `isymbuf`.

`isymbuf` comes from:

```c
  isymbuf = (Elf_Internal_Sym *) symtab_hdr->contents;
  symcount = symtab_hdr->sh_size / sizeof (Elf32_External_Sym);
  if (isymbuf == NULL)
    isymbuf = bfd_elf_get_elf_syms (abfd, symtab_hdr, symcount, 0, NULL, NULL, NULL);
```

`symtab_hdr->contents` is, by BFD convention, a **locals-only** cache of exactly
`symtab_hdr->sh_info` entries — that is what `init_reloc_cookie()` in `elflink.c`
installs, and it is populated by `--gc-sections`, which ld runs *before* relaxation.
So with `--gc-sections`, indexing that buffer with the symbol index of a **global**
symbol reads past the end of the allocation. If the out-of-bounds bytes happen to look
like `st_shndx == shndx && ELF32_ST_TYPE (st_info) == STT_SECTION`, the addend is
decremented.

This explains the `--gc-sections` dependency exactly: **without** `--gc-sections`,
`symtab_hdr->contents` is `NULL` at relax time, relax reads the full symbol table
itself, `isymbuf[idx]` is the genuine global symbol (`SHN_UNDEF`, `STT_NOTYPE`), the
guard fails deterministically, and no corruption occurs.

The same unguarded index appears in all four arms of that loop
(`R_MICROBLAZE_32`, `*_32_LO`, `R_MICROBLAZE_64`, `R_MICROBLAZE_64_PCREL`).

## Evidence

### The miscompilation

`cpukit/rtems/src/ratemoncreate.c` compiles `the_period->owner = _Thread_Get_executing()`
to, in `ratemoncreate.c.o`:

```
Disassembly of section .text.rtems_rate_monotonic_create:
  40:	imm 0
		40: R_MICROBLAZE_64	_Per_CPU_Information+0x18
  44:	lwi r8, r0, 0
  60:	swi r8, r19, 76            <- the_period->owner
```

`_Per_CPU_Information` links at `0x900195f4`; `offsetof(Per_CPU_Control, executing)`
is `0x18`, so the load must be from `0x9001960c`. The linked image contains:

```
90005040:	b0009001 	imm  -28671
90005044:	e9009608 	lwi  r8, r0, -27128      -> 0x90019608
```

`0x90019608` is `_Per_CPU_Information + 20` = `Per_CPU_Control::dispatch_necessary`.
Every rate monotonic period is created with an owner of 0 or 1, so
`rtems_rate_monotonic_period()` answers `RTEMS_NOT_OWNER_OF_RESOURCE` to its own owner,
and `rtems_rate_monotonic_get_status()` reports a bogus owner id.

### Controls, all in the same link

| relocation | addend | result |
|---|---|---|
| `_Rate_monotonic_Information` | `0x0` | correct |
| `_Rate_monotonic_Information` | `0x4` | correct |
| `_Rate_monotonic_Timeout` | `0x0` | correct |
| `_Per_CPU_Information` | `0x18` | **`+0x14` — off by 4** |
| `_Per_CPU_Information+0x18` in `threadselfid.c.o` (`_Thread_Self_id`) | `0x18` | correct |

So the symbol value is fine and only the non-zero addend is damaged, in one specific
object file.

### The fingerprint matches `calc_fixup`

`ratemoncreate.c.o` has a second code section, `.text._Rate_monotonic_Manager_initialization`:

```
object:                                linked:
   0: imm 0     (_Rate_monotonic_Information)     +0x00: imm -28671
   4: addik r5, r0, 0                             +0x04: addik r5, r0, -31680
   8: addik r1, r1, -28                           +0x08: addik r1, r1, -28
   c: swi r15, r1, 0                              +0x0c: swi r15, r1, 0
  10: imm 0     (PCREL _Objects_Initialize_...)   +0x10: brlid r15, 9836   <- imm deleted
  14: brlid r15, 0
```

One `imm` deleted at offset `0x10`. `calc_fixup(addend)` sums the deletions below
`addend`, so `fixup(0x0) = 0`, `fixup(0x4) = 0`, `fixup(0x18) = 4` — which is exactly
the table above. Note the deletion inside `rtems_rate_monotonic_create` itself is at
offset `0x2c`, which is **above** `0x18` and therefore cannot explain the damage; only
the sibling section's deletion can. The corruption comes from the other-sections loop.

### Caught in the act

I rebuilt the toolchain's `ld` from `binutils-gdb-7af075d` with the 13 Xilinx
`meta-xilinx` patches applied, and added a diagnostic at each
`isym = isymbuf + ELF32_R_SYM (irelscan->r_info);` that fires when the index is out of
bounds. Relinking the same objects reports:

```
MBDBG oob bfd=ratemoncreate.c.59.o
      relaxsec=.text._Rate_monotonic_Manager_initialization
      victimsec=.text.rtems_rate_monotonic_create
      rtype=5 symidx=21 sh_info=17 addend=0x18
      oob_shndx=4 oob_type=3 shndx=4 fixup=4   <<< GUARD PASSED - CORRUPTING
```

`readelf` confirms the preconditions: `.symtab` has `sh_info = 17`, and the relocation
is `00000040  00001505  R_MICROBLAZE_64  _Per_CPU_Information + 18`, symbol index
`0x15 = 21`. **21 >= 17**, so the read is 4 entries (96 bytes) past the end of a
17-entry locals-only buffer. The out-of-bounds bytes happened to read
`st_shndx = 4, STT_SECTION`, and `shndx` for the relaxing section is also 4.

Statistics for a single `sp69.exe` link: **1588 out-of-bounds symbol reads** across 44
object files, 25 of which passed the guard, 1 of which had a non-zero `calc_fixup` and
therefore corrupted a relocation.

## Fix

Two lines. Skip relocations against external symbols at the top of the loop — the loop
body is only ever meaningful for the local section symbol of the section being relaxed:

```diff
--- a/bfd/elf32-microblaze.c
+++ b/bfd/elf32-microblaze.c
@@
 	  irelscanend = irelocs + o->reloc_count;
 	  for (irelscan = irelocs; irelscan < irelscanend; irelscan++)
 	    {
+	      /* All the adjustments below apply only to references made
+		 through the local section symbol of the section being
+		 relaxed.  isymbuf holds at most symtab_hdr->sh_info
+		 entries -- with --gc-sections it is the locals-only cache
+		 installed by init_reloc_cookie -- so indexing it with the
+		 symbol index of a global symbol reads out of bounds and
+		 can spuriously satisfy the tests below.  */
+	      if (ELF32_R_SYM (irelscan->r_info) >= symtab_hdr->sh_info)
+		continue;
+
```

Verified: with this patch and relaxation still **enabled**, the same objects link to
the correct `lwi r8, r0, _Per_CPU_Information+0x18`, and `sp69` gets past the ownership
assertion. Identical outcome to `-Wl,--no-relax`.

Belt and braces, `microblaze_elf_relax_section()` should also stop taking
`symtab_hdr->contents` while computing `symcount` from `sh_size` — the two disagree
about what the buffer contains. Relax only ever legitimately needs local symbols, so
reading `sh_info` entries would be correct and would make the bounds check redundant.

## Upstream status

ASan-built linkers, self-contained reproducers, deterministic 5 runs out of 5:

| linker | route | ASan |
|---|---|---|
| Xilinx snapshot, 2.36.1.20210409 | `--gc-sections` | heap-buffer-overflow |
| upstream master, 2.47.50.20260805 | `.eh_frame` | heap-buffer-overflow |

One defect, two ways to install the locals-only symbol buffer that relaxation then
reads out of bounds. In 2.36 it was `init_reloc_cookie()` in `bfd/elflink.c`, under
`--gc-sections`; that block no longer exists in master, which is why the
`--gc-sections` reproducer goes quiet there. In master it is
`_bfd_elf_discard_section_eh_frame()` at `bfd/elf-eh-frame.c:1638`, reached from
`bfd_elf_discard_info()`.

The ordering is what makes it reachable. `ld/emultempl/elf.em`, the generic ELF
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

The buffer is installed and read out of bounds inside one function call, and a single
ASan trace shows both ends.

**Not a wider BFD problem — a copy defect.** This function was copied from
`sh_elf_relax_delete_bytes()` in `bfd/elf32-sh.c` when the port landed
(`7ba29e2a41`, 2009-08-06), and the copy dropped a bounds check the original already had.
`bfd/elf32-sh.c:1227-1228` has character-for-character the proposed fix, in the same
other-sections loop, four lines before the same `isymbuf` index at `:1231`. It has been
there since `252b5132c7` (1999-05-03) — ten years before MicroBlaze — and was present in
the sh file on the day the copy was made. The guard is standard elsewhere too
(`elf32-avr.c:2072`, `elf-m10200.c:636`), and MicroBlaze applies it correctly to the
section being relaxed (`elf32-microblaze.c:2021`). Only the *other-sections* loop is
unguarded.

`elf32-sh.c:1227` is the citation to use in the upstream submission — it is far stronger
than the AVR and m10200 ones, because it is the direct ancestor of the very code being
patched. Full provenance in [`RELAXATION-GUIDE.md`](RELAXATION-GUIDE.md).

`make check-ld` on upstream master, target `microblaze-xilinx-rtems7`: 476 expected
passes, 13 unexpected failures, and the baseline and patched result lists are
byte-identical. The patch changes no test outcome. There is no
`ld/testsuite/ld-microblaze` directory at all.

## An aside: why MicroBlaze `.eh_frame` warns

Not part of this bug, but it surfaced while building the reproducer and it explains
something RTEMS users see.

**Observation, not something I have proven end to end.** Three separate symptoms on
this target look like one root cause, and the connection is worth recording even though
I have not traced it through GAS:

1. `gas/all/simple-forward` fails — `.dc.b` and `.dc.w` of a label difference assemble
   to **zero**, while `.dc.l` is correct.
2. `gas/all/forward` is already xfailed for `microblaze-*-*` upstream, so the family is
   known to be broken here.
3. `.eh_frame` fails to parse, because it is built almost entirely from label
   differences.

MicroBlaze GAS emits an `R_MICROBLAZE_NONE` marker relocation for every *resolved*
label-difference expression — the same mechanism that produces the `R_MICROBLAZE_NONE`
entries next to conditional branches. In `.eh_frame`, which is built almost entirely
out of label differences (`.4byte .LFE - .LFB` and friends), those markers land in
`.rela.eh_frame` and desynchronise `ent->reloc_index`, so
`_bfd_elf_discard_section_eh_frame()` trips

```c
BFD_ASSERT (cookie->rel < cookie->relend
	    && cookie->rel->r_offset == ent->offset + 8);
```

This is the source of the `error in <file>(.eh_frame); no .eh_frame_hdr table will be
created` messages seen when linking libgcc objects, and it is presumably why the Xilinx
patch set carries `0003-Disable-the-warning-message-for-eh_frame_hdr.patch`. Silencing
the message does not fix the underlying reloc-marker mismatch — which is the point: if
the three symptoms above do share a cause, the Xilinx patch treats the most visible one
and leaves the assembler behaviour in place. Hand-assembling the CIE
and FDEs with literal lengths avoids it entirely, which is what the upstream reproducer
does so its input cannot be dismissed as malformed.

Not investigated further.

## Who needs to change

**binutils** — the actual defect, patch above. Live in the Xilinx 2.36 snapshot and in
current upstream master (`bfd/elf32-microblaze.c`, the `for (irelscan = irelocs; ...)`
loop). Worth a Sourceware Bugzilla entry against `ld` / MicroBlaze plus a patch to
binutils@sourceware.org, with the ASan reproducer and the `make check-ld` comparison.

**GCC** — not a bug, but complicit: `gcc/config/microblaze/microblaze.h`

```c
#define LINK_SPEC "%{shared:-shared} -N -relax \
```

turns on the defective pass for every MicroBlaze link, with no way to opt out short of
passing `-Wl,--no-relax`. Worth raising whether `-relax` should still be unconditional.
No GCC change is required for this bug.

**RTEMS** — needs the workaround now, since it cannot dictate the toolchain.
`-Wl,--no-relax` added to `ABI_FLAGS` in
`spec/build/bsps/microblaze/microblaze_fpga/abi.yml`, which covers the BSP, cpukit and
the installed pkg-config files.

## RTEMS test results

`microblaze/kcu105_qemu`, QEMU `petalogix-s3adsp1800`, 676 executables:

| | PASS | FAIL | XFAIL | SKIP |
|---|---:|---:|---:|---:|
| `-O0` (as shipped) | 618 | 22 | 27 | 7 |
| `-O2` | 605 | 35 | 27 | 8 |
| `-O2` + `-Wl,--no-relax` | **618** | **22** | **27** | **8** |

`-O2` with the workaround matches `-O0` exactly. Exactly two tests differ and they
cancel: `fsdosfsname01` FAIL -> PASS, and `sp69` PASS -> FAIL where the residual
failure is a 0.06% timer-accuracy assertion (`599,639,545` against a required
`600,000,000`) that also fails intermittently at `-O0` — an artifact of the emulated
timer frequency, not the port.

Text size, `minimum.norun.exe`:

| | text |
|---|---:|
| `-O0` | 68,133 |
| `-O2` | 32,017 |
| `-O2` + `-Wl,--no-relax` | 32,537 |

Disabling relaxation costs 520 bytes (1.6%) and keeps a 52% reduction against the `-O0`
build the BSPs ship today.

Disabling relaxation also removes the intermittent
`ld terminated with signal 11` failures seen while linking the testsuite: 4 per full
build with relaxation, 0 without.

## Reproduction

Toolchain: `microblaze-rtems7`, GCC 12.4.1 (Xilinx snapshot), binutils
2.36.1.20210409 (`binutils-gdb-7af075d` + 13 `meta-xilinx` `rel-v2021.1` patches),
built by the RSB from `config/7/rtems-microblaze.bset`.

```
# config.ini
[microblaze/kcu105_qemu]
BUILD_TESTS = True
OPTIMIZATION_FLAGS = -O2 -g
BSP_MICROBLAZE_FPGA_USE_FDT = False
BSP_MICROBLAZE_FPGA_CONSOLE_INTERRUPTS = True
BSP_MICROBLAZE_FPGA_UART_BASE = 0x84000000
BSP_MICROBLAZE_FPGA_UART_IRQ = 3
BSP_MICROBLAZE_FPGA_INTC_BASE = 0x81800000
BSP_MICROBLAZE_FPGA_TIMER_BASE = 0x83c00000
BSP_MICROBLAZE_FPGA_TIMER_FREQUENCY = 62000000
BSP_MICROBLAZE_FPGA_START_ADDR = 0x90000000
BSP_MICROBLAZE_FPGA_RAM_LENGTH = 0x4000000
```

Then:

```
microblaze-rtems7-objdump -dr build/.../cpukit/rtems/src/ratemoncreate.c.*.o
microblaze-rtems7-objdump -d  build/.../testsuites/sptests/sp69.exe
microblaze-rtems7-nm          build/.../testsuites/sptests/sp69.exe | grep _Per_CPU_Information
```

and compare the linked `lwi rD, r0, ...` against `_Per_CPU_Information + 0x18`.
Relinking the identical objects with `-Wl,--no-relax` gives the correct address.

Note `bsps/microblaze/shared/fdt/microblaze-fdt-support.c` does not compile at
`origin/main` with `BSP_MICROBLAZE_FPGA_USE_FDT = False`
(`-Werror=unused-parameter` on `compatible` / `prop_name`); that is an independent bug,
fixed separately.

A self-contained minimal reproducer is not practical: step 5 of the mechanism depends
on what the out-of-bounds read lands on, which is heap-layout dependent. Small test
cases with the identical instruction and relocation shape do not fire. The conditions
that must hold together are:

1. `-relax` (default) **and** `--gc-sections`
2. at least two relocated code sections in one object file (`-ffunction-sections`)
3. an `imm` deleted in the *other* section at an offset strictly below the victim addend
4. an `R_MICROBLAZE_64` relocation against a **global** symbol with a **non-zero** addend
5. the out-of-bounds `Elf_Internal_Sym` read landing on bytes that satisfy
   `st_shndx == shndx && ELF32_ST_TYPE (st_info) == STT_SECTION`

Building `ld` with ASan, or adding the diagnostic shown above, will report the
out-of-bounds read directly on any large MicroBlaze link.
