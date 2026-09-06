# binutils 0005: addr2line tie-break by DIE offset, not pointer

**Patch:** `patches/binutils/0005-bfd-dwarf2-tiebreak-by-die-offset.patch`
**Files:** `bfd/dwarf2.c` (+ `dw2-inline-tie` regression test)

## What it does
`lookup_address_in_function_table` picks, among functions whose range contains
the address, the smallest range; equal-length ties (an inlined subroutine
covering exactly the containing subprogram's range) were broken by comparing
the two `struct funcinfo *` pointers. Those come from `bfd_zalloc`, so the
winner tracked heap layout and `addr2line -f -i` named a different inlined
function run to run (23/200 runs differed on an RTEMS riscv image). The fix
orders by `unit_offset` (DIE offset), which reproduces the pre-2016
`function_table` walk order and does not move with the heap. Arch-neutral.

## Upstream audit — NOT landed
Current master `bfd/dwarf2.c` `lookup_address_in_function_table` (`:3311`) still
breaks the tie with `arange->high - arange->low == best_fit_len && funcinfo >
best_fit` at `:3369-3370` — a raw **pointer** comparison, not `unit_offset`
(verified by fetch, 2026-09-04). Not merged.

## Existing deep doc
`patches/binutils/README.md` — "**0005**" summary (the 23/200 non-reproducible
run, the `dw2-inline-tie` regression-pin rationale, riscv64 236→237).

## Strongest cross-arch citation
Arch-independent by nature — every `addr2line -i` consumer on every target is
affected. The correctness oracle is DWARF structure itself: an inlined
subroutine's DIE is always a child of (later than) its subprogram's, so
ordering equals by greater `unit_offset` deterministically picks the innermost
routine, which is what the loop's own comment says it should do and what the
pre-`089e3718bd8` `unit->function_table` prepend-walk effectively did.

## Testcase portability (reviewer feedback, 2026-09-06)

A reviewer running the new `dw2-inline-tie` test on `ia64-*` and `alpha-*` saw

    .../binutils/addr2line: DWARF error: mangled line number section

The cause is the assembler, not the test's logic: on ia64/alpha `md_cons_align`
forces every `cons` (`.dc.a`, `.4byte`, ...) to its natural alignment, so gas
inserts a padding `0x00` before the hand-written `DW_LNE_set_address` address in
the `.debug_line` program.  The extended-opcode length field (`1 + address_size`)
does not count that byte, so the reader desyncs and reports the line section as
mangled.

This cannot be fixed by re-encoding: the line program has two `set_address`
operands a fixed 10 bytes apart, so they are never both aligned (10 is not a
multiple of 4 or 8) no matter how the header is padded — even upstream `dw2-1.S`
has one of its two `set_address` addresses land unaligned.  The fix is therefore
to skip the two assembler-quirk targets, exactly as `binutils-all/testranges.d`
(another hand-written DWARF test) already does with `#notarget: ia64-*-*`.  The
`.d` now carries `#notarget: ia64-*-* alpha*-*-*`; the bfd tie-break under test
is target-neutral and still runs everywhere else.

## Status
Independent, arch-neutral determinism fix; **not sent upstream**. Also staged
for the Buildroot 2.45.1 tree
(`board/qemu/patches/binutils/0006-bfd-dwarf2-addr2line-tiebreak.patch`).
Wanted by any tcgcov user who symbolizes with `addr2line -i`.
