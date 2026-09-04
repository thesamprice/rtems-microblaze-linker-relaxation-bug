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

## Status
Independent, arch-neutral determinism fix; **not sent upstream**. Also staged
for the Buildroot 2.45.1 tree
(`board/qemu/patches/binutils/0006-bfd-dwarf2-addr2line-tiebreak.patch`).
Wanted by any tcgcov user who symbolizes with `addr2line -i`.
