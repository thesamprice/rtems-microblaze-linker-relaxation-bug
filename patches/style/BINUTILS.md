# Writing a binutils commit message

Same labels as [GCC.md](GCC.md): **[REQUIRED]**, **[CONVENTION]** (with
counts, not a rule), **[RECOMMENDED]** (this study's advice).  Sources in
[SOURCES.md](SOURCES.md), numbers in [STATS.md](STATS.md).  Check a
message with `tools/review-commit-msg.py --project binutils`.

## What is required

There is no commit-message checker.  The written rules are in
`binutils/MAINTAINERS` and in list announcements.

- **[REQUIRED]** Patches go to binutils@sourceware.org with `[PATCH]` in
  the subject.  Write-after-approval committers need approval for each
  change; obvious fixes are still posted.
- **[REQUIRED]** The commit message must be complete.  ChangeLog entries
  have **not** been required since the 2.37 branch (Nick Clifton,
  2021-06-17): "the commit messages must include accurate details
  concerning the author(s) and contents ... Changelog entries can still be
  submitted ... but the commit messages must also be complete."  Jan
  Beulich restated it in review in March 2026.
- **[REQUIRED]** FSF copyright assignment, or a DCO `Signed-off-by:`, for
  anything non-obvious.
- **[REQUIRED]** LLM policy (`binutils/MAINTAINERS`, added 2025-10-13):
  the project is "currently *NOT* accepting LLM generated patches",
  covering source, documentation **and testsuites**.  Exceptions: LLM help
  that generates no code, and LLM output that is not legally significant
  (spelling, small formatting cleanups).  A `Generated-By:` line is
  encouraged for those.  Unlike GCC there is no test-case exception.
  Reviewers read an AI `Co-Authored-By:` as AI-generated code; an AI-written
  commit message is considered fine (Beulich, on this repo's dwarf2 patch;
  SOURCES.md section 4).

## What most commits look like

From 4000 commits (2024-03 to 2026-11, gdb-only commits excluded) and a
117-commit deep sample.

- **[CONVENTION]** Subject `component:` or `arch:` then a phrase.  Prefix
  in 75%; stacked prefixes such as `bfd/ELF:`, `x86/Intel:`, `gas: scfi:`
  are common (21 of 117).  Alan Modra usually uses none.  Capitalisation
  after the prefix is split 44/42 and follows the author.  Full stop in
  5.5%, falling (9.8% in 2024, 3.7% in 2026).  Median 48 characters, 5% over
  72.
- **[CONVENTION]** PR references as `PR 12345` or `PR ld/12345` in the
  body (285 and 192 commits); `[PRnnnnn]` at the end of the subject is
  rare.  `PR NNNNN <bugzilla title>` as the subject is an Alan Modra idiom
  (f6b0f53a3682).
- **[CONVENTION]** Explanation: median 22 words for 1-10 line changes, 36
  for 11-50, 45 for 51-300; one paragraph.  Shorter than GCC at every size.
  16% of small changes have no explanation at all.
- **[CONVENTION]** A ChangeLog-style block in 44% of commits, flat since
  2024.  It follows the author, not the area: H.J. Lu 95%, Indu Bhagat
  92%, Alan Modra 73%, Jan Beulich 2%, Maciej Rozycki 0%.  libctf,
  libsframe and gprofng mostly include one; gas and opcodes mostly do not.
- **[CONVENTION]** Testing is rarely stated: 13 of 117 sampled, about 2%
  with a "Tested ..." line.  An added test is taken as the evidence.
- **[CONVENTION]** History cited in 14 of 117, best as
  `commit <hash> ("subject")` (Rozycki), useful for regressions and design
  archaeology (d88b58231ebf, 4bc3f403c566, ab1830f63310).
- **[CONVENTION]** `Signed-off-by` 15%; `Change-Id:` is unwelcome
  (Beulich).

## How to write one

- **[RECOMMENDED]** Name the trigger concretely (input, error text, FAIL
  line, target), give the cause in a sentence or two, say what the fix
  does differently and any deliberate limit (5ad7fd27ba37).  Stop there.
- **[RECOMMENDED]** Size it to the difficulty of the change.  Judged
  complexity explains length (rho 0.64); lines changed barely does
  (rho 0.08).  Median 13 words at complexity 1, 124 at complexity 4.
- **[RECOMMENDED]** Do not replace the why with a PR number, a URL or a
  ChangeLog block (weak: ea1a0737c769, eac88f329849).
- **[RECOMMENDED]** Leave test-result boilerplate out of each commit.  If
  a test was added, say what it shows; if none was added, say why
  (b70b08de3ca1).  Put suite-wide numbers in the cover letter.
- **[RECOMMENDED]** Trim pasted output to the lines that show the bug
  (too long: 31d589588ea4).
- **[RECOMMENDED]** A ChangeLog block is optional.  Include it if the
  area's regulars do; keep it accurate if you do.

## Differences from GCC

| | GCC | binutils |
|---|---|---|
| ChangeLog block | Required, machine-checked | Optional since 2021; 44% by habit |
| `Assisted-by:` | Required for LLM content; must sit above the ChangeLog | Not defined; `Generated-By:` encouraged for permitted LLM output |
| LLM test cases | Accepted | Not accepted |
| Testing statement | Required in the submission; in 58% of commits | No rule; about 2% of commits |
| PR in subject | `[PRnnnnn]`, must match a `PR` line | Rare; `PR 12345` in the body |
| Typical length | Median 36-63 words | Median 22-45 words |

## Skeleton

```
component: what the change does

What goes wrong, with the concrete trigger.  Why.

What the fix does differently, and what it deliberately leaves alone.

	PR 12345
	* file.c (function): Description.     <- optional

Signed-off-by: Name <email>
```
