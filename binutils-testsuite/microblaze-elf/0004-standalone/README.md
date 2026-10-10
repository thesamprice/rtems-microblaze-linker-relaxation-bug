# 0004 standalone A/B: `BFD_RELOC_8`/`BFD_RELOC_16` fixup cases

`make check-gas`, whole gas suite, **0004 alone** — not the series — on pristine upstream
master `f621e384d9c` (2.47.50.20260920), target `microblaze-elf`.

Configured `--target=microblaze-elf --disable-gdb --disable-sim --disable-werror
--with-system-zlib --disable-nls`, built `all-gas all-binutils all-ld`.

| | stock | with 0004 |
|---|---|---|
| expected passes | 327 | **329** |
| unexpected failures | 1 | **0** |
| expected failures | 1 | **0** |
| unsupported | 10 | 10 |
| unexpected successes | 0 | 0 |

The two tests that move, and the only ones that move:

```
stock      FAIL:  simple forward references     (gas/all/gas.exp)
stock      XFAIL: forward references            (gas/all/gas.exp)
patched    both PASS; no FAIL, XFAIL or XPASS remains
```

`forward references` was xfailed for `microblaze-*-*`; 0004 removes that xfail in the same
patch, which is why the expected-failure count goes to zero rather than staying at one.

Re-measured 2026-09-21 after the patch was corrected to also fix the now-stale comment
above that `#xfail:` line (it still read "mep and microblaze use complex relocs").  The
comment is inert to DejaGnu, and the numbers are identical to the first run.

## Build `ld`, or the numbers lie

A first run built only `all-gas all-binutils` and reported 322/6 stock, 324/5 patched, with
five extra failures in `gas/microblaze/relax_size.exp` and `gas/microblaze/reloc_sym.exp`.
Those are artefacts: `reloc_sym.exp` links and disassembles, so without `ld` in the build
tree it fails for reasons that have nothing to do with the assembler. With `all-ld` built
the five disappear and the counts above are what the suite actually reports.
