# binutils: MicroBlaze relaxation, symbol table

Two patches against `bfd/elf32-microblaze.c`, sent as one series. Both are
defects in `microblaze_elf_relax_section()`'s symbol adjustment, independent
of the relocation addend corruption this repository is named for
(`a639e0adaf2`, landed 2026-08-13), and both still reproduce on master.

Kept out of [`../binutils/`](../binutils/) on purpose: that directory is
unrelated gas, `.eh_frame` and PLT work, and bundling the two would split
reviewer attention.

| # | what | effect |
|---|---|---|
| 0001 | don't adjust a wrapped symbol twice (copy the `--wrap` guard from `elf32-ft32.c`) | `__wrap_SYMBOL` resolves before its own first instruction; DejaGnu's `testglue.c` never writes its status line, so every MicroBlaze execution test is reported as status 2 |
| 0002 | measure the `st_size` fixup from the symbol's pre-relaxation value | a function's size can overlap the next function, so `objdump --disassemble=` and debugger function bounds disagree with the code |

0001 has a runtime consequence; 0002 affects `st_size` only. 0002 touches
lines adjacent to 0001, so apply in order.

Analysis, with the measurements and the cross-backend survey:
[`0001`](../../analysis/binutils-0013-relax-wrap-double-adjust.md),
[`0002`](../../analysis/binutils-0014-relax-st_size-from-old-value.md). The
file numbers there are the repo's older bookkeeping (0013, 0014); the series
numbers here are what reviewers see.

## Generating and sending

```sh
BINUTILS_TREE=~/src/binutils-gdb BINUTILS_BASE=origin/master ./tools/make-outbox.sh
python3 tools/check-patch-style.py patches/binutils-relax
git send-email --confirm=never --to=binutils@sourceware.org \
    --cc=eager@eagercon.com --cc=amodra@gmail.com \
    outbox/binutils-relax/*.patch
```

`outbox/binutils-relax/` is generated; never hand-edit it. The message and
diff live here, reviewer notes go in `NNNN-*.notes`, and
[`../STYLE.md`](../STYLE.md) is the house style both are written to.

**Add your own `Signed-off-by:` before sending.** It is a statement about
provenance and is deliberately not generated.

## Status

Written against `6d71cb48957`; `git am`s clean onto `origin/master`
`90a7bfab3c3` (2026-09-01). Not sent upstream yet.

`ld` testsuite on `microblaze-elf`, measured both ways with the two new tests
present in each case:

| | passes | unexpected failures |
|---|---|---|
| neither patch | 480 | 2 |
| both patches | 482 | 0 |

`microblaze.exp` alone: 3 passes and 2 failures without, 5 passes without
failures with. Reverting only the `bfd/elf32-microblaze.c` hunk of either
patch fails exactly that patch's test and leaves the other's passing.
