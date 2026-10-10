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
| binutils 0001 (relaxation OOB) | merged upstream 2026-08-13; `git apply` to master fails because the fix is already there (`elf32-microblaze.c:2125`). The `.patch` is kept under `patches/binutils/landed/` and `ANALYSIS.md` documents the bug. |
| binutils 0002 (discarded sections) | merged upstream 2026-08-13; `RELOC_AGAINST_DISCARDED_SECTION` is already at `elf32-microblaze.c:1120`. |

Also already upstream, and never ours to submit: the libgcc signal-frame
unwinder — Ramin Moussavi's `4ef64ad1a` (gcc 15.3 / 16.2), carried in
`patches/gcc/landed/ramin-0001-...` only as the thing to add to an old toolchain.
Our `patches/gcc/0001` is the glibc *correction* to that upstream file, not the
file itself.

## What still applies (verified by `git apply` to current master)

| Series | Against | Result |
|---|---|---|
| binutils 0003-0009 | master `193340ad3` | applies clean as an ordered series |
| gcc 0001, 0002 | master `08794c636` | apply clean |
| glibc 0001-0007 (old numbering; now `patches/glibc/0001-0004, 0007-0009`) | master `fe03757f` | applies clean as an ordered series |

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

- **binutils:** submit 0003, 0004, 0006, 0007, 0008, 0009, 0010; 0001, 0002 done;
  0005 (arch-neutral addr2line) removed 2026-09-08, handled outside this repo.
- **gcc:** submit 0001 (as a fix to Ramin's file) and 0002 (needs binutils 0009).
- **glibc:** submit the series (consolidated 2026-09-08 into `patches/glibc/0001-0009`, reconciliation done) — originally 0001-0007 after the cancellation-path reconciliation in
  [MERGE-AUDIT.md](MERGE-AUDIT.md).

## Re-check 2026-09-08: Ramin's OpenADK work

Checked binutils master `d715260f4`, gcc master (2026-09-08), glibc master, Linux
mainline/linux-next, RTEMS main, and Ramin Moussavi's commit trail (GitHub,
OpenADK `wbx-github/openadk`, sourceware and kernel patchwork).

| Patch | Result |
|---|---|
| RTEMS FDT fix | **landed** — Sebastian Huber `91401c423f` (2026-08-17), identical code. Moved to `patches/rtems/landed/`. |
| `ramin-0001` libgcc unwinder | already in gcc master/releases/gcc-15; moved from `patches/linux/` to `patches/gcc/landed/`. |
| Linux 0001-0004 | **superseded and landed**: Ramin's series (2026-08-21) covers the same four fixes (his entry.S form restores `PTO` instead of lowering r1) and is in Michal Simek's MicroBlaze tree, merged into linux-next 2026-09-07 (`730e01d93249`, `c5947d28c209`, `da6829138a39`, `c35d40a3efd2`, `ca35dd21a5f8`). Ours moved to `patches/linux/superseded/`, his to `patches/linux/landed/`. Not in a Linus release yet. |
| binutils 0003-0010 | still open; no MicroBlaze commits since 0002 landed. |
| gcc 0001, 0002 | still open; OpenADK carries only the upstream unwinder form, no glibc correction; `microblaze.h` still `DW_EH_PE_aligned`. |
| glibc (all) | still open; zero MicroBlaze changes upstream in 2026; Ramin works on uClibc-ng. |
| RTEMS relax 0001/0002 | local; RTEMS main `abi.yml` still has empty `ldflags`. |

New from Ramin: the libgcc `moddi3.S` fix (wrong since 2010, hangs on LE),
now carried as `patches/gcc/ramin-0002-...` (applies to gcc master). His
OpenADK backports of Gopi's PR118280/PR103383 are backports of commits that
are already in gcc master (`7894c00982`, `9e3e6ceb3b`), so nothing to carry;
likewise Gopi's native-Linux gdb (`d62f64e17b3`, 2026-05-07).

Correction: an earlier pass the same day said the kernel series was in
neither linux-next nor patchwork. It missed the 2026-09-07 linux-next merge;
the file-level grep (`abi_gap`, `ret_from_trap_no_rval`, `MSR_CC`,
`sys_sigaltstack`, `PTO`) against linux-next is the check that settled it.

## Housekeeping 2026-09-08: one glibc series

The two glibc patch folders were merged into `patches/glibc/` as one series:
old EH 0001-0004 keep their numbers, the cancellation branch's 0001/0002
became 0005/0006, and EH 0005-0007 became 0007-0009. The `syscall_cancel.S`
hunk of the CFI patch (now 0007) was dropped, since the tail-call in 0006
leaves no frame to describe. `glibc-longjmp-chk/` keeps its README, evidence
and the Neal correspondence only. The series was re-checked with
`git apply --check` in order against glibc master (see below).

Re-verified after the consolidation: `patches/glibc/0001-0009` apply cleanly in
order (`git apply`, each on top of the previous) to glibc master `04e750e7`
(2026-09-08).

## Re-check 2026-09-20: the addr2line patch landed

Fetched all five upstreams again. Heads checked: binutils `f621e384d9c`
(2026-09-20), glibc `d5bd0f22305` (2026-09-16), gcc mirror `549ec717abb`
(2026-09-14 — the GitHub gcc-mirror lags sourceware by a few days), Linux
mainline `93f51579e7df` (7.3-rc4), RTEMS main.

**One patch landed: the arch-neutral `bfd/dwarf2.c` addr2line tie-break**, this
repo's old 0005 — removed here on 2026-09-08 and sent standalone from the tcgcov
work.

| | |
|---|---|
| commit | `b2e68bf063e595a12329dc7aba0393621e6591f3` |
| authored | Samuel Price, 2026-09-15 |
| committed | Alan Modra, 2026-09-18 |
| files | `bfd/dwarf2.c`, `binutils/testsuite/binutils-all/dw2-inline-tie.S`, `.d`, `addr2line.exp` (+228 -4) |

v3 went in **verbatim** — diffed against
`claude-mb/addr2line-tie-v2/v3-0001-bfd-dwarf2-break-equal-range-function-ties-by-DIE.patch`,
the `dwarf2.c` hunk and the test are byte-identical and only the `Signed-off-by`
/ `Assisted-by` trailers were added. Three rounds on the list (v1 2026-08-18,
v2 2026-09-10, v3 2026-09-16 on patchwork).

### Nothing else moved

| Series | Result |
|---|---|
| binutils 0003, 0004, 0006-0010 | still open. The only MicroBlaze-subject commits upstream since 0002 are still ours (`a639e0adaf2`, `f55053f1dc9`). |
| gcc 0001, 0002 | still open; the only `gcc/config/microblaze` or `libgcc/config/microblaze` commit since June is Joel Sherrill's `271186ef4` (`rtems.h`, 2026-09-04), unrelated. |
| gcc `ramin-0002` (moddi3) | still open — upstream `moddi3.S` has no `__MICROBLAZEEL__` handling. Not on gcc-patches. |
| glibc 0001-0009 | still open, and **not yet sent**: sourceware patchwork has no glibc submissions from `thesamprice@gmail.com`, and glibc master has had no MicroBlaze commit in 2026 beyond Adhemerval's arch-neutral `c626d764d7`. |
| Linux (Ramin's five) | still **not in mainline**. `compare` of `730e01d93249`, `c5947d28c209` and `ca35dd21a5f8` against `torvalds/linux` master returns `diverged`; mainline is 7.3-rc4, so they ride the 7.4 merge window. Michal's tree / linux-next only. |
| RTEMS | unchanged — `91401c423f70` landed 2026-08-17, nothing left. |

### Upstream churn to be aware of

Two Alan Modra commits since the last re-check touch files our binutils series
also touches. `e189bfd9b49` (*use linker created stub bfd for dynobj*,
2026-08-06) rewrote 19 lines of `bfd/elf32-microblaze.c` itself; `2093ffeb9ef`
(*Constify struct bfd_link_order args*, 2026-08-21) touched `bfd/reloc.c`,
`bfd-in2.h` and `libbfd.h`, which 0009 also edits. Neither conflicts — see the
apply check below — but 0007, 0008 and 0009 are the patches that would notice if
that area moves again.

### Apply check on today's upstream

All three outbox series `git am` clean, in mail order, no fuzz, in a throwaway
worktree on each tree's current master:

| series | base | result |
|---|---|---|
| `outbox/binutils/0001-0007` | binutils `f621e384d9c` | 7/7 applied |
| `outbox/glibc/0001-0009` | glibc `d5bd0f22305` | 9/9 applied |
| `outbox/gcc-0001`, `outbox/gcc-0002`, `patches/gcc/ramin-0002` | gcc `549ec717abb` | 3/3 applied (one pre-existing trailing-whitespace warning in `moddi3.S`) |

Caveat on the gcc line: `claude-mb/gcc-master` is a **shallow** clone grafted at
`13529401b` (2026-06-27), so its log only proves the absence of *recent*
landings. The gcc claims above are backed by file content (`linux-unwind.h`
present, `moddi3.S` unpatched, `microblaze.h` still `DW_EH_PE_aligned`) rather
than by history.

### Still blocking a send

`outbox/binutils/0006` (the pr24511 xfail, repo 0003) still has **no
`#noxfail: microblaze*-linux*` line**, so it XPASSes on `microblaze*-linux*`.
That has been the stated blocker since the first audit and is unchanged.

## Re-check 2026-09-27: the whole v3 series landed

Fetched binutils again; master is now `90a7bfab3c3`. **All four patches of the
v3 series are upstream**, committed by Michael J. Eager about eleven hours after
they were sent — a different committer from the first three, which went through
Alan Modra.

| repo # | upstream | committed | what |
|---|---|---|---|
| 0004 | `ee6b7f5bb8e` | 2026-09-24 08:25 | add the `BFD_RELOC_8`/`BFD_RELOC_16` cases |
| 0011 | `5047dd4a3a2` | 08:26 | `md_number_to_chars` in `md_apply_fix` |
| 0010 | `ad8ac4b8993` | 08:28 | gas.exp: exclude microblazeel from diff1 *and* end |
| 0012 | `0dabe1eeb6d` | 08:30 | `md_number_to_chars` in `md_assemble` |

Verified in upstream master by content, not just by log subject:
`tc-microblaze.c` has 4 uses of `INST_IMM_OFFSET` and **zero** references to
`INST_BYTE`, so the macros really are gone and the new name went in unchanged;
`forward.d` carries both the widened xfail and the corrected comment;
`gas.exp` has `microblaze*-*-*` at lines 73 and 475.

That makes **seven** patches from this repo upstream: the relaxation miscompile,
discarded sections, the addr2line tie-break, and these four.

### How it got from one patch to four

0004 went out alone (v1, 2026-09-20). Neal Frager reviewed it and asked for the
now-stale comment in `forward.d` to go too — v2, 2026-09-22. Michael Eager then
asked for `md_number_to_chars` "like aarch64, mips, sparc" and said cleaning up
the other `BFD_RELOC_MICROBLAZE_*` cases the same way would be welcome. v3
delivered both and grew two more patches:

- **0010** gained a second hunk. Testing `microblazeel-elf` for the first time
  showed `gas.exp` excludes MicroBlaze from *two* tests, `diff1` and `end`, and
  both guards said `microblaze-*-*` — which does not match the little-endian
  triplet. The original 0010 widened only the `diff1` guard. With both widened,
  microblazeel goes to zero unexpected failures.
- **0012** finished the conversion in `md_assemble`, which let the four
  `INST_BYTE0..3` macros be deleted.

### Still open

binutils **0003** (the `pr24511` xfail, still needing its `#noxfail:
microblaze*-linux*` line), **0006** (gas CFI — the keystone for the whole
exception-handling chain), **0007**, **0008** and **0009**. No other MicroBlaze
commits upstream since 2026-09-01, so nothing else moved. `outbox/binutils/` is
regenerated as a 5-patch series on `90a7bfab3c3`.

### Two defects that shipped in the v3 cover letter

Recorded so a future series does not repeat them. Neither affects the committed
code, and neither was worth a resend.

- The `Samuel Price (4):` shortlog block appears **twice**. Caused by stashing
  the cover-letter body across a `format-patch` regeneration and reinserting it,
  after which `format-patch` appended its own copy.
- It says "Net effect on tc-microblaze.c: 26 insertions, 80 deletions". The real
  figure for that file is **+24 −84** (+28 −88 across all three files).

Also: the series was sent in two invocations, because the first stopped after
1/4 — `sendemail.annotate yes` opens an editor per message and
`sendemail.confirm always` prompts per message, neither of which works
non-interactively. 2/4-4/4 went out separately with `--no-annotate
--confirm=never --in-reply-to` the cover letter, so threading is correct but the
Message-Id stems differ between 0/4-1/4 and 2/4-4/4.
