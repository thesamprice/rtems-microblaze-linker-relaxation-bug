# Writing a GCC commit message

Labels: **[REQUIRED]** is an official rule, with its source.  **[CONVENTION]**
is what most commits do, with counts; it is not a rule.  **[RECOMMENDED]** is
this study's advice, derived from the data and the review comments.  Sources
and URLs are in [SOURCES.md](SOURCES.md), numbers in [STATS.md](STATS.md),
annotated examples in [EXAMPLES.md](EXAMPLES.md), templates in
[TEMPLATES.md](TEMPLATES.md).  Check a message with
`tools/review-commit-msg.py --project gcc`.

## What is required

### Enforced by the push hook

The server runs `contrib/gcc-changelog/git_commit.py` on every pushed
commit.  Run it yourself before sending; it needs GitPython:

```sh
python3 contrib/gcc-changelog/git_check_commit.py -v BASE..HEAD
```

- **[REQUIRED]** Line 2 is blank.
- **[REQUIRED]** The message contains a ChangeLog block.  It starts at the
  first line that is `dir/ChangeLog:` (or a known directory), `\t* file`, or
  `\tPR comp/N`; everything above it is free text and is not checked.
- **[REQUIRED]** Every changed file is named under its own directory's
  ChangeLog, and no unchanged file is named.  Wildcards only under
  gcc/testsuite, libstdc++-v3/testsuite and libstdc++-v3/doc/html.
- **[REQUIRED]** Entry lines start with a tab, then `* ` with one space;
  every `file (function):` has a description; ChangeLog lines fit in 100
  columns (tab = 8).
- **[REQUIRED]** A PR in the subject (`[PR12345]`) also appears as a
  `\tPR component/12345` line, with a valid component.
- **[REQUIRED]** ChangeLog, DATESTAMP, BASE-VER and DEV-PHASE are never
  edited by hand in the same commit; a daily job writes them.
- **[REQUIRED]** Trailers the hook knows (`Signed-off-by`, `Reviewed-by`,
  `Co-Authored-By` and a few others) may follow the ChangeLog block.
  **`Assisted-by:` is not one of them: after the ChangeLog block it fails
  with "line should start with a tab".**  Put it in the free text, on its
  own line just above the ChangeLog block.  This repo's gcc patches all
  failed this check until the line was moved (2026-11-08).

### Stated in the documentation

From gcc.gnu.org/contribute.html, gitwrite.html, codingconventions.html,
dco.html and ai-policy.html:

- **[REQUIRED]** The submission describes the problem and how the patch
  addresses it, references the PR for a bug, adds testcases or justifies
  their absence, includes the ChangeLog, and states the host/target tested
  and the results.  Not everything needs to survive into the commit:
  contribute.html asks for testing in the *submission*.
- **[REQUIRED]** Bootstrap and full regression test for anything outside a
  front end; test exactly what you submit.
- **[REQUIRED]** Copyright assignment or DCO `Signed-off-by:` with a real
  identity.  Only a human adds `Signed-off-by:`.
- **[REQUIRED]** LLM policy (2026-07-29, to be reviewed early 2027):
  legally significant contributions containing LLM-generated content are
  declined, *except test cases*.  Any contribution with LLM-generated
  content carries `Assisted-by:`.  Reviewers have also asked for a sentence
  on how the tool was used and why the change is legally insignificant
  (Sandiford, Dapp; SOURCES.md section 4).
- **[DOC]** Subject at most 75 characters after the `[PATCH]` classifier:
  `component: summary [PRnnnnn]`.  Layout: subject, blank line, discussion,
  ChangeLog.

## What most commits look like

From 4000 commits (2026-06 to 2026-11) and a 140-commit deep sample.

- **[CONVENTION]** Subject `component: Summary [PRnnnnn]`.  Prefix in 83%;
  the word after it is capitalised in 86 of 116 sampled; no full stop in
  87%; median 57 characters, 14% over 72.  Prefixes: language or pass in
  lower case (`fortran:`, `libstdc++:`, `match.pd:`, `c++:`, `testsuite:`),
  targets as the port spells them (`RISC-V:`, `aarch64:`, `i386:`, `AVR:`).
  Richard Biener alone uses `tree-optimization/NNNNN - summary`.
- **[CONVENTION]** Explanation: median 36 words for 1-10 line changes, 49
  for 11-50, 63 for 51-300; 2 paragraphs.  Order: symptom, cause, fix and
  why it is right, side effects, testing.
- **[CONVENTION]** Testing is mentioned in 58% of commits, but as a
  formal line in only 17 of 140 sampled.  Recurring forms:
  "Bootstrapped and regtested on x86_64-pc-linux-gnu." and "Tested on
  riscv32-elf and riscv64-elf."  Frequent committers often omit it
  (Biener 4%), newer contributors almost always include it.
- **[CONVENTION]** History is cited as `rNN-NNNN` (11 of 140 sampled), for
  regressions and dependencies.
- **[CONVENTION]** ChangeLog: `gcc/ChangeLog:` headers (94 of 140), "New
  test." for tests, "Likewise." for repeats, `PR comp/NNNN` line first.
- **[CONVENTION]** `Signed-off-by` 38%, `Assisted-by` 4.4% (175 commits,
  e.g. 2a4f362222, bcf14085d82), `Reviewed-by` 7%.

## How to write one

- **[RECOMMENDED]** Size the explanation to how hard the change is to
  understand, not to the diff.  Judged complexity explains length far
  better than lines changed (rho 0.58 against 0.18; STATS.md).  A
  one-line fix to a subtle invariant deserves a paragraph (d794365c8f0d);
  a 300-line mechanical rename deserves a sentence.
- **[RECOMMENDED]** Answer, in order, and stop when the reader has enough:
  1. What goes wrong, observably: wrong output, ICE text, missed
     optimisation, with a minimal snippet if it helps (e8621d3bdaf0).
  2. Why: the invariant or rule that was violated.
  3. Why this fix and not the obvious alternative, and what you left alone
     (5be7b70e769e).
  4. Testing, one line: triplets and scope.
- **[RECOMMENDED]** Cite `rNN-NNNN` when you claim a regression or build on
  earlier work.  Leave other history out.  Never write "a recent change"
  or "my previous patch".
- **[RECOMMENDED]** Leave out mailing-list residue: `[PATCH v3]`, version
  logs, "Waiting on CI", greetings, full build logs (weak examples
  ea1a75bfd580, 9d59dcff40a4, 51c8f3368607).
- **[RECOMMENDED]** In a series, put shared background and the test
  results in the cover letter; each commit repeats only what it needs to
  stand alone in `git log`.
- **[RECOMMENDED]** "No functional change." plus one sentence of why is a
  complete message for a refactor (35874595799c).

## Skeleton

```
component: Imperative summary [PR12345]

What goes wrong, observably, in one or two sentences.  Why it goes
wrong.

What the fix does and why it is the right fix.  What it deliberately
does not change.

Bootstrapped and regtested on x86_64-pc-linux-gnu.

Assisted-by: Tool name

	PR component/12345

gcc/ChangeLog:

	* file.cc (function): Description.

gcc/testsuite/ChangeLog:

	* gcc.dg/pr12345.c: New test.

Signed-off-by: Name <email>
```
