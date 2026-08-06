# binutils testsuite, baseline vs patched

The validation that belongs in a binutils submission: binutils' own `make check`,
whole suite, with and without the patch. Target `microblaze-xilinx-rtems7`, upstream
master `b7da195b94` (2.47.50.20260805).

RTEMS testsuite results are **not** validation for a binutils change. They are why the
bug matters, not evidence that the patch is correct. Those numbers live in the
top-level [`README.md`](../README.md) and should stay out of the patch submission
except as motivation.

## Result

Baseline is **unmodified upstream master `b7da195b94`**, verified to contain no part
of the fix before the run. An earlier version of this page compared against a tree
that already had the fix applied — the numbers happened to be the same, but the
comparison was meaningless. Corrected here.

```
make -k check
```

| component | baseline | patched | delta |
|---|---|---|---|
| gas | 323 pass, 2 fail | 323 pass, 2 fail | none |
| binutils | 92 pass, 17 fail | 92 pass, 17 fail | none |
| ld | 476 pass, 13 fail | **478 pass**, 13 fail | **+2** |
| **total** | **891 pass, 32 fail** | **893 pass, 32 fail** | **+2 pass** |

Diffing the full `PASS`/`FAIL`/`XFAIL`/`XPASS`/`UNRESOLVED`/`UNTESTED`/`UNSUPPORTED`
lists:

- `gas` — **identical**
- `binutils` — **identical**
- `ld` — identical except the two lines added by the patch:

```
> PASS: MicroBlaze relaxation preserves R_MICROBLAZE_32 addends
> PASS: MicroBlaze relaxation preserves R_MICROBLAZE_64 addends
```

So the only change the patch makes to the entire binutils testsuite is the two tests it
adds. Nothing else moves, in any direction.

## The 32 pre-existing failures

Present identically with and without the patch, and all host artifacts rather than
target problems — this is macOS/arm64, and most involve assembling or archive handling
in the harness rather than MicroBlaze code generation.

**gas (2)** — `simple forward references`, `linking reloc_sym.x`

**binutils (17)** — `ar long file names`, `archive with empty element`,
`ar foreign object`, six `nm` variants, `objcopy -i --interleave-width`,
`objcopy tek2bin`, two `binary symbol` cases, `objdump (assembling bintest.s)`,
two `readelf` corrupt-input cases, `size (assembling)`

**ld (13)** — `ld-discard/zero-range`, `ld-discard/zero-rel`, `ld-elf/linkonce1`,
`ld-elf/linkonce2`, `ld-elf/pr24511`, and eight `sysroot-prefix` variants

The eight `sysroot-prefix` failures are path-handling differences on this host. A
reviewer running on Linux should expect a different, probably smaller, pre-existing
failure count — what matters is that the delta is zero either way.

## Reproducing

```sh
../binutils-gdb/configure --target=microblaze-rtems7 \
    --disable-gdb --disable-sim --disable-gdbserver --disable-readline \
    --disable-nls --disable-werror --with-system-zlib
make -j8 all-gas all-binutils all-ld
make -k check
```

On macOS add `-Dfdopen=fdopen` to `CC`; the bundled zlib takes its classic-Mac-OS
branch because `TARGET_OS_MAC` is defined there too.

Needs dejagnu. The raw `.sum` files for both runs are in this directory.

## Caveat

Fetching a newer master was rate-limited by sourceware (HTTP 429) at the time of this
run, so this is one day behind tip. Worth re-running against current master before
sending.
