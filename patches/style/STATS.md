# Commit-message statistics: GCC and binutils

Data collected 2026-11-08 from the upstream master branches: the 4000
most recent non-merge commits of each project, excluding bot commits
(daily bumps, date updates, copyright years, regeneration).  For
binutils-gdb, commits touching only gdb, gdbserver, gdbsupport or sim are
also excluded, so its 4000 commits span 2024-03 to 2026-11; GCC's span
2026-06 to 2026-11.  Scripts: `tools/style-study/collect.py` and
`tools/style-study/stats.py`.

Each message is split into subject, **explanation** (free text, with the
ChangeLog block, `PR` lines, trailers and indented quotes removed),
ChangeLog block and trailers.  "Size" is non-test, non-ChangeLog lines
added plus deleted.  The change-type column is a regex heuristic over the
subject and paths; the deep samples below found it wrong for about a
third of commits, so treat the per-type rows as rough.

Everything in this file is **observed**, not a rule.

## Headline: length follows complexity, not size

Two stratified samples (140 GCC, 117 binutils commits; `data/deep-*.tsv`)
were read in full with their diffs, and each change was given a semantic
complexity score from 1 (obvious) to 5 (hard to understand) by the
reader.  Explanation length against that score:

| | rho(words, judged complexity) | rho(words, lines changed) |
|---|---:|---:|
| GCC | 0.58 | 0.18 |
| binutils | 0.64 | 0.08 |

| judged complexity | GCC median words (p90) | binutils median words (p90) |
|---|---:|---:|
| 1 | 18 (76) | 13 (33) |
| 2 | 37 (85) | 30 (83) |
| 3 | 87 (196) | 80 (171) |
| 4 | 143 (285) | 124 (291) |

Caveat: the reader scored complexity with the message in front of them,
so some circularity is possible.  The same readers judged message length
against the change: GCC 114 fit, 22 too short, 4 too long; binutils 94
fit, 20 too short, 3 too long.  Too-short messages cluster at complexity
2-3 (GCC 19 of 22), where authors assume the diff explains itself.

None of the 25 archived maintainer review comments collected for this
study asked for a shorter message; all asked for more explanation, a
testing statement, or a fix to format (SOURCES.md, section 5).

## GCC population: 4000 commits, 2026-06-25 to 2026-11-08

Bot commits (daily bumps, date updates, copyright years, regeneration) are excluded.  "Explanation" means the body with the ChangeLog block, PR lines, trailers and indented quotes removed.  Sizes count non-test, non-ChangeLog lines added plus deleted.

### Explanation length by patch size

| lines changed | commits | no explanation | median words | p75 | p90 | median lines |
|---|---:|---:|---:|---:|---:|---:|
| 1-10 | 1086 | 9% | 36 | 76 | 119 | 4 |
| 11-50 | 1309 | 6% | 49 | 101 | 172 | 5 |
| 51-300 | 870 | 7% | 63 | 130 | 235 | 7 |
| >300 | 216 | 12% | 54 | 119 | 216 | 7 |
| tests/docs only | 519 | 8% | 27 | 52 | 89 | 3 |

### By change type (heuristic classification from subject and paths)

| type | commits | median words | p90 | rationale words | testing stated | PR cited | cites a commit | quotes code/output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| bugfix | 1437 | 57 | 196 | 49% | 61% | 76% | 12% | 19% |
| refactor | 674 | 39 | 148 | 38% | 43% | 14% | 7% | 14% |
| other | 559 | 45 | 168 | 40% | 45% | 12% | 8% | 17% |
| test | 517 | 27 | 89 | 42% | 97% | 32% | 15% | 10% |
| feature | 473 | 35 | 143 | 29% | 53% | 5% | 3% | 19% |
| docs | 303 | 54 | 163 | 40% | 51% | 35% | 10% | 23% |
| mechanical | 37 | 4 | 59 | 14% | 11% | 8% | 16% | 8% |

### By subsystem (first non-test file)

| subsystem | commits | median words | p90 | ChangeLog block | testing stated |
|---|---:|---:|---:|---:|---:|
| gcc middle-end | 1232 | 60 | 193 | 100% | 53% |
| gcc/config (back ends) | 745 | 65 | 181 | 100% | 63% |
| gcc/testsuite only | 478 | 26 | 89 | 99% | 97% |
| gcc/rust (front end) | 323 | 21 | 66 | 100% | 58% |
| libstdc++-v3 | 215 | 53 | 209 | 99% | 59% |
| gcc/fortran (front end) | 184 | 34 | 152 | 100% | 69% |
| gcc/cobol (front end) | 153 | 30 | 80 | 100% | 16% |
| gcc/cp (front end) | 140 | 76 | 190 | 100% | 65% |
| gcc/ada (front end) | 92 | 26 | 83 | 100% | 17% |
| gcc/algol68 (front end) | 49 | 1 | 89 | 100% | 33% |
| libgfortran | 39 | 68 | 185 | 100% | 72% |
| libgomp | 36 | 58 | 300 | 100% | 44% |
| gcc/c-family (front end) | 33 | 71 | 226 | 100% | 70% |
| libgcc | 28 | 36 | 198 | 100% | 29% |

### Correlation of explanation length with patch measures (Spearman rho)

| measure | all | bugfix | feature | refactor |
|---|---:|---:|---:|---:|
| code_changed | 0.19 | 0.29 | 0.29 | 0.18 |
| code_files | -0.04 | 0.08 | 0.01 | -0.10 |
| hunks | 0.19 | 0.29 | 0.24 | 0.13 |
| functions | 0.03 | 0.17 | 0.12 | 0.02 |
| complexity | 0.16 | 0.26 | 0.27 | 0.13 |

### Form

- Subject length: median 57, p90 75, 14% over 72.  Component prefix ("x: ..."): 83%.  Ends with a full stop: 13%.
- Explanation lines over 72 columns: in 35% of commits with an explanation.
- ChangeLog block in the message: 100% overall.
- Mentions testing: 58%.  First person (I/we): 29% of commits with an explanation.
- Paragraphs in the explanation: median 2, p90 6.
- Trailers: signed-off-by 37.6%, reviewed-by 7.4%, assisted-by 4.4%, co-authored-by 2.7%, suggested-by 0.2%, reported-by 0.2%, signed-of-by 0.0%, cc 0.0%.
- Most common subject prefixes: `gccrs` 350, `libstdc++` 210, `RISC-V` 207, `cobol` 184, `testsuite` 135, `fortran` 134, `aarch64` 128, `c++` 113, `i386` 97, `Ada` 69, `match.pd` 58, `a68` 53, `match` 51, `AVR` 46, `rs6000` 43.

### Frequent authors: explanation length

| author | commits | median words | p90 | ChangeLog block | testing stated |
|---|---:|---:|---:|---:|---:|
| Richard Biener | 223 | 35 | 121 | 100% | 4% |
| Kyrylo Tkachov | 218 | 126 | 261 | 100% | 83% |
| Jakub Jelinek | 163 | 112 | 273 | 100% | 33% |
| Pan Li | 132 | 17 | 66 | 100% | 77% |
| Philip Herron | 94 | 2 | 60 | 100% | 60% |
| Aldy Hernandez | 85 | 61 | 157 | 100% | 86% |
| James K. Lowden | 84 | 23 | 57 | 100% | 5% |
| Jerry DeLisle | 83 | 57 | 165 | 100% | 93% |
| Andrea Pinski | 78 | 65 | 128 | 100% | 95% |
| Eric Botcazou | 74 | 31 | 84 | 100% | 24% |

## binutils population: 4000 commits, 2024-03-19 to 2026-11-08

Bot commits (daily bumps, date updates, copyright years, regeneration) are excluded; so are commits touching only gdb, gdbserver, gdbsupport or sim.  "Explanation" means the body with the ChangeLog block, PR lines, trailers and indented quotes removed.  Sizes count non-test, non-ChangeLog lines added plus deleted.

### Explanation length by patch size

| lines changed | commits | no explanation | median words | p75 | p90 | median lines |
|---|---:|---:|---:|---:|---:|---:|
| 1-10 | 1295 | 16% | 22 | 45 | 82 | 3 |
| 11-50 | 1121 | 10% | 36 | 68 | 118 | 4 |
| 51-300 | 775 | 8% | 45 | 92 | 162 | 5 |
| >300 | 310 | 16% | 36 | 85 | 168 | 5 |
| tests/docs only | 499 | 15% | 26 | 47 | 92 | 3 |

### By change type (heuristic classification from subject and paths)

| type | commits | median words | p90 | rationale words | testing stated | PR cited | cites a commit | quotes code/output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| other | 959 | 35 | 136 | 35% | 17% | 10% | 12% | 14% |
| bugfix | 885 | 36 | 130 | 33% | 16% | 13% | 14% | 14% |
| refactor | 679 | 31 | 99 | 25% | 10% | 5% | 10% | 12% |
| feature | 556 | 33 | 146 | 23% | 31% | 7% | 8% | 18% |
| test | 488 | 26 | 89 | 33% | 73% | 18% | 12% | 11% |
| mechanical | 263 | 19 | 85 | 30% | 11% | 3% | 23% | 17% |
| docs | 170 | 5 | 48 | 10% | 7% | 2% | 3% | 10% |

### By subsystem (first non-test file)

| subsystem | commits | median words | p90 | ChangeLog block | testing stated |
|---|---:|---:|---:|---:|---:|
| bfd | 764 | 33 | 140 | 55% | 13% |
| gas (target) | 681 | 34 | 107 | 25% | 16% |
| gas | 437 | 30 | 106 | 40% | 35% |
| ld | 430 | 31 | 112 | 51% | 44% |
| bfd (target) | 407 | 38 | 135 | 49% | 30% |
| binutils | 398 | 19 | 81 | 44% | 19% |
| opcodes (target) | 297 | 29 | 89 | 29% | 21% |
| .pre-commit-config.yaml | 108 | 22 | 174 | 9% | 27% |
| include | 100 | 33 | 157 | 43% | 16% |
| libctf | 92 | 60 | 233 | 90% | 37% |
| gprofng | 69 | 21 | 69 | 80% | 9% |
| libsframe | 65 | 38 | 140 | 92% | 29% |
| gprof | 28 | 14 | 61 | 46% | 36% |
| opcodes | 22 | 31 | 123 | 68% | 9% |

### Correlation of explanation length with patch measures (Spearman rho)

| measure | all | bugfix | feature | refactor |
|---|---:|---:|---:|---:|
| code_changed | 0.23 | 0.25 | 0.21 | 0.23 |
| code_files | 0.14 | 0.17 | 0.11 | 0.17 |
| hunks | 0.25 | 0.30 | 0.16 | 0.25 |
| functions | 0.20 | 0.24 | 0.19 | 0.22 |
| complexity | 0.22 | 0.23 | 0.20 | 0.24 |

### Form

- Subject length: median 48, p90 67, 5% over 72.  Component prefix ("x: ..."): 75%.  Ends with a full stop: 6%.
- Explanation lines over 72 columns: in 22% of commits with an explanation.
- ChangeLog block in the message: 44% overall.
- Mentions testing: 24%.  First person (I/we): 21% of commits with an explanation.
- Paragraphs in the explanation: median 1, p90 4.
- Trailers: signed-off-by 15.4%, approved-by 1.9%, reviewed-by 1.7%, co-authored-by 1.7%, bug 1.1%, change-id 0.8%, fixes 0.5%, suggested-by 0.3%.
- Most common subject prefixes: `aarch64` 337, `gas` 231, `RISC-V` 205, `x86` 196, `ld` 148, `LoongArch` 107, `bfd` 87, `s390` 80, `Re` 76, `libctf` 72, `gprofng` 56, `bfd/ELF` 47, `elf` 43, `libsframe` 42, `arm` 39.

### Frequent authors: explanation length

| author | commits | median words | p90 | ChangeLog block | testing stated |
|---|---:|---:|---:|---:|---:|
| Alan Modra | 778 | 26 | 94 | 74% | 15% |
| Jan Beulich | 637 | 32 | 89 | 2% | 6% |
| H.J. Lu | 281 | 24 | 76 | 96% | 57% |
| Nick Clifton | 168 | 0 | 2 | 0% | 0% |
| Indu Bhagat | 165 | 52 | 176 | 92% | 37% |
| Matthieu Longo | 153 | 29 | 156 | 1% | 10% |
| Jens Remus | 134 | 50 | 170 | 98% | 53% |
| Alice Carlotti | 130 | 19 | 66 | 0% | 21% |
| Maciej W. Rozycki | 123 | 47 | 177 | 1% | 42% |
| Tom de Vries | 101 | 29 | 166 | 10% | 33% |

