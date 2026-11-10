# GCC and binutils commit-message study

Evidence behind [`../STYLE.md`](../STYLE.md), collected 2026-11-08.

| File | What it is |
|---|---|
| [GCC.md](GCC.md) | Style guide for GCC: what the push hook and the documentation require, what most commits do, how to write one |
| [BINUTILS.md](BINUTILS.md) | The same for binutils, with a table of differences from GCC |
| [STATS.md](STATS.md) | Distributions and correlations: length against size, type, subsystem, complexity and author |
| [EXAMPLES.md](EXAMPLES.md) | 36 real commits judged good or weak, with reasons |
| [TEMPLATES.md](TEMPLATES.md) | Messages for bug fixes, optimisations, refactors, tests, back-end changes and one-liners |
| [SOURCES.md](SOURCES.md) | The official rules with sources, the LLM policies, and 25 archived review comments asking for better messages |
| `data/` | The stratified samples and the per-commit judgments behind EXAMPLES.md |

Check a message: `tools/review-commit-msg.py patches/<series>`.

## Labels

Every conclusion carries one:

- **REQUIRED**: an official rule, with its source.  For GCC, "enforced"
  means the push hook rejects the commit.
- **CONVENTION**: what most upstream commits do, with counts.  Frequency
  is not a rule; plenty of accepted commits break each convention.
- **RECOMMENDED**: this study's advice, derived from the data and the
  review comments.

## Method

1. **Population.** The 4000 most recent non-merge commits of gcc master
   (2026-06 to 2026-11) and of binutils-gdb master restricted to binutils
   directories (2024-03 to 2026-11), bot commits excluded.  Each message
   split into subject, explanation, ChangeLog block and trailers, with
   size and complexity measures from the diff
   (`tools/style-study/collect.py`, `stats.py`).
2. **Deep samples.** 140 GCC and 117 binutils commits, stratified by
   change type and size, each read in full with its diff and judged for
   problem statement, rationale, testing, length fit and semantic
   complexity (`data/deep-*.tsv`).  MicroBlaze was not oversampled.
3. **Official rules.** gcc.gnu.org contribute, gitwrite, codingconventions,
   dco and ai-policy pages; GCC's `contrib/gcc-changelog/git_commit.py`,
   read and run; `binutils/MAINTAINERS`; list announcements; archived
   review comments.

## Limits

- The change-type classifier used for the population tables is a regex
  heuristic, wrong for about a third of commits.  The deep-sample counts
  use corrected types.
- Complexity in the deep samples was judged with the message visible, so
  the length-complexity correlation may be partly circular.
- sourceware.org/binutils/wiki and inbox.sourceware.org thread pages were
  behind a bot wall; review quotes come from the list's monthly archives,
  and the inbox URLs in SOURCES.md were built from Message-IDs and not
  opened.
- The judgments of good and weak are this study's; they are labelled
  RECOMMENDED for that reason.

To rerun: shallow-clone both repositories since 2024-01-01, then
`python3 tools/style-study/collect.py REPO.git gcc 4000 gcc.jsonl` (and
`binutils`), and `python3 tools/style-study/stats.py` in the same
directory.
