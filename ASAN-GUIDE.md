# Running the toolchain under AddressSanitizer

How the out-of-bounds read in this repository was found and confirmed, written up so it
can be repeated on other links and other targets.

## Read this first: what is being sanitized

**ASan here instruments the linker, not RTEMS.** `ld` is a program running on your Mac
or Linux box; it is compiled with `-fsanitize=address` and it checks *its own* memory
accesses while it processes your object files. The MicroBlaze code it produces is
completely uninstrumented, and the RTEMS image that comes out is byte-for-byte what an
uninstrumented linker would have produced.

That is what made the bug in this repository findable: the defect was in `ld`, so
sanitizing `ld` caught it.

**You cannot run the RTEMS testsuite itself under ASan.** ASan needs a runtime library
that hooks `malloc`, maintains shadow memory and prints reports, and none exists for
`microblaze-rtems7`:

```console
$ find ~/rtems/7 -name 'libasan*' -o -name 'libubsan*'
              # nothing

$ microblaze-rtems7-gcc -fsanitize=address -c t.c -o t.o
cc1: warning: '-fsanitize=address' and '-fsanitize=kernel-address' are not supported for this target
cc1: warning: '-fsanitize=address' not supported for this target
```

The compiler accepts the flag and then ignores it. See
[Sanitizing RTEMS itself](#sanitizing-rtems-itself) at the end for what *is* available
on the target — it is more limited, but not nothing.

So there are two useful things to do, and they are different:

| goal | how | covered here |
|---|---|---|
| find bugs **in the toolchain** while it builds RTEMS | ASan-built `ld`, run the whole RTEMS build through it | Parts 1–3 |
| find bugs **in RTEMS code** at runtime | no ASan available; UBSan-trap and friends | Part 5 |

---

## Part 1 — Build an ASan linker

### Get the exact sources your toolchain uses

Do not use a random binutils tarball. The RTEMS MicroBlaze toolchain is pinned by
`rtems/config/7/rtems-microblaze.bset`:

```
%define with_rtems_binutils tools/rtems-xilinx-binutils-2.36
%define with_rtems_gcc      tools/rtems-xilinx-gcc-12-newlib-head
```

which is the Xilinx snapshot `binutils-gdb-7af075d` **plus 13 patches**. The RSB has
already downloaded both:

```sh
SRC=~/src/rtems_builder/src/rsb/rtems/sources
PATCHES=~/src/rtems_builder/src/rsb/rtems/patches

mkdir -p ~/asan && cd ~/asan
tar xzf $SRC/binutils-gdb-7af075d.tar.gz
cd binutils-gdb-7af075d

for p in 0001-Add-wdc.ext.clear-and-wdc.ext.flush-insns.patch \
         0002-Add-mlittle-endian-and-mbig-endian-flags.patch \
         0003-Disable-the-warning-message-for-eh_frame_hdr.patch \
         0004-LOCAL-Fix-relaxation-of-assembler-resolved-reference.patch \
         0005-upstream-change-to-garbage-collection-sweep-causes-m.patch \
         0006-Fix-bug-in-TLSTPREL-Relocation.patch \
         0007-Added-Address-extension-instructions.patch \
         0008-fixing-the-MAX_OPCODES-to-correct-value.patch \
         0009-Add-new-bit-field-instructions.patch \
         0010-fixing-the-imm-bug.patch \
         0011-Patch-Microblaze-fixed-bug-in-GCC-so-that-It-will-su.patch \
         0012-fixing-the-constant-range-check-issue.patch \
         0013-Patch-Microblaze-Compiler-will-give-error-messages-i.patch ; do
  patch -p1 -N -s < $PATCHES/$p || echo "FAILED: $p"
done
```

**Skipping the patches will bite you.** Patch `0004` adds the `R_MICROBLAZE_32_NONE`
relocation (type 33). Without it, linking real RTEMS objects dies with:

```
ld: start.o: unsupported relocation type 0x21
ld: final link failed: bad value
```

The plain upstream tree is fine for a *minimal* testcase, but not for RTEMS.

### Configure and build

```sh
mkdir -p ~/asan/build && cd ~/asan/build

../binutils-gdb-7af075d/configure \
    --target=microblaze-rtems7 \
    --prefix=$HOME/asan/inst \
    --disable-gdb --disable-sim --disable-gdbserver \
    --disable-readline --disable-nls --disable-werror \
    --with-system-zlib \
    CC="clang -fsanitize=address -fno-omit-frame-pointer -g -O1" \
    LDFLAGS="-fsanitize=address"

make -j8 all-ld
```

Roughly 10 minutes. `ld/ld-new` is your sanitized linker.

`-O1` rather than `-O0`: ASan at `-O0` is very slow and `-O1` keeps stack traces
readable. `-fno-omit-frame-pointer` is what makes those traces usable at all.

**macOS gotcha.** The bundled zlib fails to compile: its classic-Mac-OS branch is
guarded on `TARGET_OS_MAC`, which modern macOS also defines, so it takes that path and
does `#define fdopen(fd,mode) NULL`, which then expands inside the SDK's own `fdopen`
declaration. `--with-system-zlib` does not prevent the bundled copy being built. Add
`-Dfdopen=fdopen` to `CC` — zlib guards its bad definition with `#ifndef fdopen`, so
defining it to itself skips it:

```sh
    CC="clang -fsanitize=address -fno-omit-frame-pointer -g -O1 -Dfdopen=fdopen" \
```

The same workaround is already in the RSB for the normal toolchain build.

### If you also want `as` and `objdump`

Only needed for the testsuite in Part 4:

```sh
make -j8 all-gas all-binutils
```

---

## Part 2 — Point the compiler at it

`gcc` finds `ld` by name on a search path, so give it a directory containing one:

```sh
mkdir -p ~/asan/wrap
ln -sf ~/asan/build/ld/ld-new ~/asan/wrap/ld
ln -sf ~/asan/build/ld/ld-new ~/asan/wrap/microblaze-rtems7-ld
```

Then add `-B` to any link:

```sh
microblaze-rtems7-gcc -B$HOME/asan/wrap/ ... -o prog.exe
```

`-B` puts that directory ahead of the compiler's own, so the sanitized `ld` is used
while everything else — the real `as`, the real libraries, the real specs — stays put.
Verify it took:

```sh
microblaze-rtems7-gcc -B$HOME/asan/wrap/ -print-prog-name=ld
```

### Running a single RTEMS link

The RTEMS build system knows the exact command. Delete a target and rebuild verbosely
to capture it:

```sh
cd rtems
rm -f build/microblaze/kcu105_qemu/testsuites/sptests/sp69.exe
./waf build --out=build -v -j1 2>&1 | grep sp69.exe
```

Then re-run that command from `build/microblaze/kcu105_qemu/`, adding
`-B$HOME/asan/wrap/`. That is how the report in this repository was produced.

### Running the whole RTEMS build through it

This is the interesting one — every link in the testsuite is roughly 700 chances to
trip over a toolchain bug. `ABI_FLAGS` reaches every link, so:

```ini
[microblaze/kcu105_qemu]
BUILD_TESTS = True
OPTIMIZATION_FLAGS = -O2 -g
ABI_FLAGS = -mlittle-endian -mno-xl-soft-div -mno-xl-soft-mul -Wl,-EL -B/home/you/asan/wrap/
```

then `./waf configure && ./waf build -k`, and collect everything ASan says:

```sh
./waf build -k 2>&1 | tee build-asan.log
grep -c "AddressSanitizer" build-asan.log
grep -A25 "ERROR: AddressSanitizer" build-asan.log | less
```

> **Not verified at this scale.** I ran single links this way, not a full 700-link
> build. Expect it to be slow — ASan costs roughly 2x CPU and a lot of RAM, and `-k`
> is essential so one abort does not stop the build. If ASan aborts a link, the `.exe`
> is missing rather than wrong, so the build will report failures that are really ASan
> catches; read the log, not the exit status.

Set `ASAN_OPTIONS=halt_on_error=0` to keep going past the first report, and
`detect_leaks=0` — `ld` leaks by design, it is a short-lived process, and leak reports
will bury the real findings. On macOS LeakSanitizer is off by default anyway.

---

## Part 3 — Reading a report

```
ERROR: AddressSanitizer: heap-buffer-overflow on address 0x6120000007fc
READ of size 4 at 0x6120000007fc thread T0
    #0 microblaze_elf_relax_section elf32-microblaze.c:2208     <- where it read
    #5 lang_relax_sections ldlang.c:8286
    #6 ldelf_map_segments ldelfgen.c:266
    #7 lang_process ldlang.c:8930

0x6120000007fc is located 156 bytes after 288-byte region       <- how far past
allocated by thread T0 here:
    #2 bfd_elf_get_elf_syms elf.c:565                           <- who allocated it
    #3 _bfd_elf_discard_section_eh_frame elf-eh-frame.c:1634
    #4 bfd_elf_discard_info elflink.c:15239
    #5 gldelf32microblaze_after_allocation eelf32microblaze.c:113
```

The **second** stack is the valuable half and the one people skip. It told us the buffer
came from `_bfd_elf_discard_section_eh_frame` under `after_allocation` — which is what
identified the mechanism, not just the symptom. Whenever ASan gives you an allocation
stack, read it before theorising.

Then do the arithmetic, because it usually names the object:

- 288-byte region / 32 bytes per `Elf_Internal_Sym` = **9 entries**, matching
  `sh_info` — so it is the locals-only symbol cache.
- Read at 288 + 156 = 444; 444 / 32 = entry **13**, remainder 28 = the offset of
  `st_shndx` within the struct.
- Entry 13 is a global symbol, read from a 9-entry buffer. `READ of size 4` is exactly
  the `st_shndx` field.

That is the whole bug, derived from the report.

---

## Part 4 — When ASan is not enough

ASan tells you a bad read happened. It does not tell you whether the value that came
back *mattered*. For this bug the read was always out of bounds but only sometimes
changed the output, so we needed to see which reads went on to corrupt something.

A `fprintf` in the right place answers that. Full patch in
[`repro/ld-instrumentation.patch`](repro/ld-instrumentation.patch); the shape is:

```c
  isym = isymbuf + ELF32_R_SYM (irelscan->r_info);
+ if (ELF32_R_SYM (irelscan->r_info) >= symtab_hdr->sh_info)
+   fprintf (stderr, "MBDBG oob bfd=%s relaxsec=%s victimsec=%s addend=0x%lx fixup=%lu%s\n",
+            abfd->filename, sec->name, o->name,
+            (unsigned long) irelscan->r_addend,
+            (unsigned long) calc_fixup (irelscan->r_addend, 0, sec),
+            (isym->st_shndx == shndx
+             && ELF32_ST_TYPE (isym->st_info) == STT_SECTION)
+            ? "  <<< GUARD PASSED - CORRUPTING" : "");
```

Rebuild with `make -j8 all-ld` — only `bfd` recompiles, about a minute — and link. On
one `sp69.exe` link that produced 1588 out-of-bounds reads, of which 25 passed the guard
and exactly 1 had a non-zero fixup and actually damaged a relocation. Sorting that
output is what turned "something is wrong" into a one-line diagnosis.

Use `--no-relax` and `--gc-sections` as A/B switches to bisect which linker phase is
responsible; that is how relaxation was implicated before any source was read.

---

## Sanitizing RTEMS itself

No ASan for the target, as established. What *is* available:

### UndefinedBehaviorSanitizer, in trap mode

Plain `-fsanitize=undefined` emits calls into `libubsan`:

```console
$ microblaze-rtems7-gcc -fsanitize=undefined -c ub.c -o ub.o
$ microblaze-rtems7-nm ub.o | grep -c __ubsan
4
```

Those are undefined at link. But adding `-fsanitize-undefined-trap-on-error` replaces
every call with an inline trap and needs **no runtime library at all**:

```console
$ microblaze-rtems7-gcc -fsanitize=undefined -fsanitize-undefined-trap-on-error -c ub.c -o ub.o
$ microblaze-rtems7-nm ub.o | grep -c __ubsan
0
```

So this is usable on bare-metal RTEMS today. It catches signed overflow, shifts past
the width of the type, misaligned and null pointer accesses, some array bounds
violations, and unreachable code — all things that bite MicroBlaze code and none of
which are caught by anything else in the build.

**Two caveats, both real.**

1. **A trap on MicroBlaze is an infinite loop.** `__builtin_trap()` compiles to
   `bri 0` — a branch to itself:

   ```console
   $ printf 'void t(void){ __builtin_trap(); }' > tr.c
   $ microblaze-rtems7-gcc -O1 -c tr.c -o tr.o && microblaze-rtems7-objdump -d tr.o
   00000000 <t>:
      0:	b8000000 	bri	0		// 0
   ```

   It does not fault, does not print, and does not reset. Under QEMU a UBSan hit shows
   up as a **hang**, which `mb-run.sh` records as `NO-OUTPUT` after the timeout —
   indistinguishable from an ordinary timeout without attaching gdb and reading the PC.
   Workable, but plan for it: run with `-s -S`, attach `microblaze-rtems7-gdb`, and
   when a test hangs, `info registers` and look up `pc` in the map file.

2. **Code growth.** A toy file went from 32 to 96 bytes of text. Do not scale that
   number up naively — it is three functions of almost nothing — but expect it to be
   significant, and do not ship it.

Enable it the same way as anything else, via `config.ini`:

```ini
OPTIMIZATION_FLAGS = -O2 -g -fsanitize=undefined -fsanitize-undefined-trap-on-error
```

I have not run the testsuite this way. If you do, expect new `NO-OUTPUT` results rather
than new `FAIL`s, and treat each one as a UBSan hit until proven a timeout.

### Things that already exist and cost nothing

- `CONFIGURE_STACK_CHECKER_ENABLED` — RTEMS's own stack overflow detection, and it
  actually reports rather than hanging.
- `-fstack-protector-strong` — `libssp.a` **is** present for this target
  (`~/rtems/7/lib/gcc/microblaze-rtems7/12.4.1/libssp.a`), unlike the sanitizer
  runtimes.
- The differential approach used elsewhere in this project: build the same source with
  GCC and with a second compiler and compare behaviour. Slower to set up, but it finds
  miscompilations that no sanitizer will, because it does not depend on the bug being
  a memory error.

### If you truly need ASan on RTEMS code

The realistic route is to compile the logic you care about for the **host** and run it
there under real ASan — practical for self-contained code such as protocol parsers,
CRCs, or the CCSDS layer, and not practical for anything touching the BSP or the
scheduler. That is a porting exercise, not a build flag.

---

## Summary

| | works | notes |
|---|---|---|
| ASan on `ld`, `as`, `objdump` | **yes** | found the bug in this repository |
| ASan on the whole RTEMS build via `ABI_FLAGS` | yes in principle | recipe above, not verified at full scale |
| ASan on RTEMS target code | **no** | no runtime for `microblaze-rtems7` |
| UBSan on target code, trap mode | **yes** | no runtime needed; traps are hangs, not faults |
| UBSan on target code, normal mode | no | needs `libubsan`, which does not exist here |
| `-fstack-protector-strong` | yes | `libssp.a` is present |

Everything marked "yes" without qualification was run. Anything not run is labelled as
such above.
