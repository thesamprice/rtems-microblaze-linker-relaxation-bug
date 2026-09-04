# Rework against current upstream (2026-09-04)

After the audit found that several early patches had already been merged, the
whole series was re-checked against **current** upstream master, not the base
commits: binutils `193340ad3`, gcc master `08794c636` (via the gcc-mirror), and
glibc `fe03757f`. The result: nothing needs a content rebase. Two patches are
now redundant and were dropped from the active set; every other patch still
applies cleanly to today's master.

## What was dropped

| Patch | Why |
|---|---|
| binutils 0001 (relaxation OOB) | merged upstream 2026-08-13; `git apply` to master fails because the fix is already there (`elf32-microblaze.c:2125`). The `.patch` and `ANALYSIS.md` are kept as the record of the original bug. |
| binutils 0002 (discarded sections) | merged upstream 2026-08-13; `RELOC_AGAINST_DISCARDED_SECTION` is already at `elf32-microblaze.c:1120`. |

Also already upstream, and never ours to submit: the libgcc signal-frame
unwinder — Ramin Moussavi's `4ef64ad1a` (gcc 15.3 / 16.2), carried in
`patches/linux/ramin-0001-...` only as the thing to add to an old toolchain.
Our `patches/gcc/0001` is the glibc *correction* to that upstream file, not the
file itself.

## What still applies (verified by `git apply` to current master)

| Series | Against | Result |
|---|---|---|
| binutils 0003-0009 | master `193340ad3` | applies clean as an ordered series |
| gcc 0001, 0002 | master `08794c636` | apply clean |
| glibc 0001-0007 | master `fe03757f` | applies clean as an ordered series |

The apply order matters: binutils 0009 needs 0006 first (both touch
`tc-microblaze.h` and `cfi.d`); glibc 0005 needs 0003 (both touch `start.S`) and
0006 needs 0004 (both touch the linux Makefile). Applied in number order the
series are conflict-free.

## Tested on the reworked binutils

Built binutils from **current master `193340ad3` plus 0003-0009** and ran the
MicroBlaze suites (host-side, no qemu):

```
gas  gas/microblaze/*.exp   : 10 expected passes, 0 fail
ld   ld-microblaze + eh*    :  6 expected passes, 0 fail
```

Green on today's upstream, same as against the base commit. The gcc and glibc
patch content is unchanged from the runs recorded in
`../glibc-longjmp-chk/evidence/`, so those results stand; a full gcc+glibc
rebuild on the bumped bases would reproduce them and was not repeated here. The
harness (`../harness/run.sh`) now pins these master commits and applies
`patches/binutils/000[3-9]` (the still-open set) rather than `000[6-9]`.

## Net effect on the submission set

- **binutils:** submit 0003, 0004, 0006, 0007, 0008, 0009; 0005 (arch-neutral
  addr2line) separately; 0001, 0002 done.
- **gcc:** submit 0001 (as a fix to Ramin's file) and 0002 (needs binutils 0009).
- **glibc:** submit 0001-0007, after the cancellation-path reconciliation in
  [MERGE-AUDIT.md](MERGE-AUDIT.md).
