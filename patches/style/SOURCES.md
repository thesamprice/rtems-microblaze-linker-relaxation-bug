# GCC and binutils: official commit-message and submission requirements

Researched 2026-11-08 against gcc master a74179d08523 and binutils-gdb master 116f031eb755 (both 2026-11-09; history read from 2024-01-01).
Labels used: **[REQ]** official requirement (source), **[DOC]** documented recommendation (source), **[OBS]** observed in review (URL).
Could not fetch: every page on sourceware.org/binutils/wiki/* (Anubis bot wall, including HowToContribute and LLM_Generated_Content) and inbox.sourceware.org thread pages. The sourceware.org/pipermail archives did load, and the review quotes below come from their monthly mbox files. inbox URLs are built from Message-IDs.

## 1. GCC

### 1a. Enforced by the commit checker (`contrib/gcc-changelog/git_commit.py`)
The server-side hook runs this script. Martin Liska announced it in May 2020 (https://gcc.gnu.org/pipermail/gcc/2020-May/232431.html), and `git gcc-verify` runs the same script locally (`contrib/gcc-git-customization.sh:28`). In Sept 2026 Richard Biener reported the checker rejecting a placement (see below), so it is still running. Every item below is an **error** that blocks the push. The script emits **warnings** only for auto-added "New file." entries and for unresolvable revert/cherry-pick hashes (lines 349, 783-785, 826-829).

- **[REQ] Line 2 must be blank.** `Expected empty second line in commit message` (l.337-338).
- **[REQ] A ChangeLog block must be present.** Unless every changed file is under `ignored_prefixes` (libsanitizer/, zlib/, libgo/, gcc/go/gofrontend/, ...; l.149-162), the push fails with `cannot find a ChangeLog location in message` (l.472). The block starts at the first line that is any of these: `dir/ChangeLog[:]`, a known ChangeLog directory, `\t* file`, `\tPR comp/N`, an author line, or `Co-Authored-By:` (l.459-469). Everything above that line is free text and **is not checked**, apart from line 2 and the subject PR rule.
- **[REQ] Entries must name the right files.** Every changed file must be named under the ChangeLog of its directory (`changed file not mentioned in a ChangeLog`, l.774). Unchanged files must not be named (l.723), and an entry under the wrong directory fails with `wrong ChangeLog location` (l.793). Wildcards are allowed only under gcc/testsuite/, libstdc++-v3/testsuite/ and libstdc++-v3/doc/html/ (l.164-168, 624).
- **[REQ] Line format:**
  - entry lines start with a TAB (`line should start with a tab`, l.575) and have no space after the tab (l.648);
  - a star line is `\t* ` with exactly one space (l.584);
  - no `file (fn):` without a description (`missing description of a change`, l.635);
  - parentheses balance and there are no empty `()`/`[]`/`<>` groups;
  - no trailing whitespace (l.484);
  - **100-column limit, tabs counted as 8, applied only to the ChangeLog block** (`LINE_LIMIT = 100`, l.192, 485). A long bare filename line is exempt.
- **[REQ] PR lines.** `\tPR component/NNNN` needs a valid component from `bug_components` (`missing PR component` / `invalid PR component`, l.520-523). If the subject contains `[PRnnnn]`, `(PRnnnn)` or `PR comp/nnnn`, the same number must appear as a PR line in the block (`PR %s in subject but not in changelog`, l.400). An invalid component in the subject is also an error (l.365).
- **[REQ] Author lines.** A date line uses `YYYY-MM-DD␣␣Name␣␣<email>`. An extra author line is TAB plus exactly four spaces (l.510).
- **[REQ] Trailers.**
  - `Co-Authored-By:` is parsed, and the name is added as an author of every ChangeLog entry (l.194, 834-837).
  - `Reviewed-by`, `Reviewed-on`, `Signed-off-by`, `Acked-by`, `Tested-by`, `Reported-by` and `Suggested-by` are skipped silently (l.196-198).
  - **`Assisted-by:` is not in that list** (no "assisted" string anywhere in contrib/). Below the ChangeLog block it is read as a ChangeLog line and fails the tab rule. Confirmed by running `git_check_commit.py` on this repo's gcc series on 2026-11-08: every patch failed with `line should start with a tab: "Assisted-by: ..."`, and passed once the line was moved above the ChangeLog block. Of the 40 most recent gcc commits with the tag, 38 place it above the ChangeLog block. Biener reported the same rejection in review: "the commit checker does not like the Assisted-By tags placed at the Signed-off-by position, instead it seems it should be at the end of the description" (https://inbox.sourceware.org/gcc-patches/CAFiYyc33YU-GTDuKNqLL=qHKryEY6fCrdO8ZcKhX3pv573+oHg@mail.gmail.com/).
- **[REQ] Reverts and backports.** `This reverts commit <hash>.` must name a commit that exists (l.354). At most one `cherry picked from commit` line (l.545).
- **[REQ] Generated files.** ChangeLog, DATESTAMP, BASE-VER and DEV-PHASE edits must be separate commits (l.378), because a daily cron job generates them for master and releases/gcc-14/15/16 (`git_update_version.py`, active_refs l.76-77).
- **[REQ] Author email.** The commit email must be ASCII (l.880).

### 1b. Stated in docs, not enforced by the checker
From https://gcc.gnu.org/contribute.html ("Submitting Patches", "E-mail subject lines"):
- **[REQ] Patch contents.** "Every patch must have several pieces of information":
  - "A description of the problem/bug and how your patch addresses it";
  - for bugs, what was wrong and a reference to the PR;
  - testcases, or "a justification for why adequate testcases cannot be added";
  - "A ChangeLog entry as plaintext";
  - "State the host and target combinations you used ... and the results of your testing".
  - "Don't mix together changes made for different reasons."
- **[REQ] Testing.** "All patches must be thoroughly tested." Non-front-end, C or C++ changes need a full bootstrap of all default languages and all testsuites. "you must test exactly the change that you intend to submit."
- **[DOC] Subject line.** "The entire line (excluding the classifier) should not exceed 75 characters." It is made of a classifier (`[PATCH vN M/N]`, dropped from the commit), component tags ending in `:`, a summary, and an optional `[PRnnnnn]`. The body "should still contain the full form (PR <component>/nnnnn)".
- **[DOC] Message layout.** https://gcc.gnu.org/gitwrite.html: "a summary line ... followed by a blank line, then any discussion of the patch, and then the complete ChangeLog entry".
- **[DOC] What goes in the ChangeLog.** https://gcc.gnu.org/codingconventions.html#ChangeLogs: "descriptions of the purpose of code and changes should go in comments rather than the ChangeLog". Authors may be deduced from git, and "we recommend to use it". Generate the template with `contrib/mklog.py` or `git gcc-commit-mklog`.
- No documented line-length rule exists for the free-text body. 76 columns is only a reviewer preference [OBS, see §5].

## 2. binutils

### 2a. Enforced
- No server-side commit-message checker found. `.pre-commit-config.yaml` is client-side and opt-in, and its only commit-msg hook (codespell-log) is scoped to gdb. No in-tree commit-msg rule applies to binutils directories.

### 2b. Stated
- **[REQ] Where to send patches.** binutils@sourceware.org with "[Patch]" in the subject (`binutils/MAINTAINERS` l.15-19). config.guess/config.sub go to config-patches@gnu.org. libiberty goes to gcc-patches.
- **[REQ] Approval.** Write-after-approval contributors need approval for each change. Obvious fixes may go in without approval but "should still be sent to the binutils list" and must not be legally significant (MAINTAINERS l.190-213).
- **[REQ] ChangeLog entries are no longer required.**
  - Nick Clifton, head maintainer, 2021-06-17: after the 2.37 branch "we are going to relax the requirement that patch submissions include text for changelog entry(s) ... the commit messages must include accurate details concerning the author(s) and contents ... Changelog entries can still be submitted ... but the commit messages must also be complete" (https://sourceware.org/pipermail/binutils/2021-June/117016.html).
  - H.J. Lu, 2021-08-04: "ChangeLog is no longer needed for binutils master branch" (https://sourceware.org/pipermail/binutils/2021-August/117591.html).
  - In-tree: bfd/ChangeLog etc. were rotated to `ChangeLog-2020`. The current files are touched by about 1% of commits: 13 of 1644 in 2024, 16 of 1823 in 2025, 1 of 1368 in 2026, counting bfd, gas, ld, binutils and opcodes.
  - In practice: about 1065 of 3196 commits since 2025-01-01 (one third) still carry a GNU-style `\t* file (fn):` block in the message. That is a convention, not a rule.
  - Jan Beulich in review, 2026-03-06: "ChangeLog data (which isn't required anymore)" (https://inbox.sourceware.org/binutils/0a903228-11dc-4490-8c3e-54500bf669af@suse.com/).
- No official binutils doc found on subject length, body wrapping or testing statements. HowToContribute could not be fetched.

## 3. DCO, Signed-off-by and copyright assignment
- **GCC [REQ].** Contributors use either an FSF assignment or the DCO, shown by a `Signed-off-by:` with "a known identity (sorry, no anonymous contributions.)" (https://gcc.gnu.org/dco.html). Committers can record a standing DCO in MAINTAINERS ("Contributing under the DCO", MAINTAINERS l.982-986). "We can accept small changes without copyright assignment or DCO certification" (contribute.html). The checker ignores `Signed-off-by` (1a).
- **binutils [REQ].** A non-obvious patch needs either an FSF copyright assignment or a DCO 1.1 sign-off, "adding a line ... Signed-off-by: Random J Developer <...>" (`binutils/MAINTAINERS` l.215-238). In practice about 450 Signed-off-by lines appear in roughly 3200 commits since 2025, so it is not universal: contributors with an FSF assignment on file don't need one.

## 4. AI-assisted contribution policy
- **GCC [REQ]** https://gcc.gnu.org/ai-policy.html, last modified 2026-07-29, to be reviewed "at the start of 2027":
  - Policy: "decline any legally significant contributions which include LLM-generated content or are derived from LLM-generated content".
  - Allowed: legally insignificant LLM content "clearly marked", and legally significant LLM **test cases**.
  - Marking: "The commit message for any contribution of LLM-generated content must include an 'Assisted-by:' tag."
  - Human role: the submitter must be "a human who understands the changes". "Only a human may provide the 'Signed-off-by:' tag". "An LLM may not commit code".
  - Out of scope: research, bug discovery, review and debugging, as long as the output is not included in the contribution.
  - The ~15-line threshold quoted in press coverage is **not** in the policy text.
- **binutils [REQ]** `binutils/MAINTAINERS` l.240-298, added in commit c0316a54b on 2025-10-13 after the RFC at https://inbox.sourceware.org/binutils/878qhth0zt.fsf@redhat.com/:
  - "The GNU Binutils project is currently *NOT* accepting LLM generated patches", covering code, documentation and testsuites.
  - Exceptions: LLM help that does not generate code, and LLM code that is not legally significant.
  - "If [LLM output] does [make it into the patch], then the patch is unacceptable."
  - "Fully automated patch submission ... is not acceptable."
  - Marking is **encouraged, not required**: "a line starting with the Generated-By: prefix", e.g. `Generated-By: GNU-LLM version 1.0`.
  - Unlike GCC, there is **no exception for testsuites**.
- **[OBS] How binutils reviewers apply it** (this repo's dwarf2 patch):
  - Jan Beulich, 2026-08-21: "This all looks good to me, if there wasn't the Co-Authored-By:. That, to me, suggests that part of the patch was AI-generated" (https://inbox.sourceware.org/binutils/edc99a80-5d85-466f-b626-c3f66e5eb872@suse.com/).
  - Then: "my understanding is that an AI-based commit message is fine; it's AI-generated code which isn't" (https://inbox.sourceware.org/binutils/45201d8b-19ab-46cc-b71a-eb583e019c78@suse.com/).
  - v3, which carried `Assisted-by: Claude (Anthropic)`, was committed by Alan Modra (https://inbox.sourceware.org/binutils/aqx955xpUac_NYNK@squeak.grove.modra.org/).
- **[OBS] How GCC reviewers apply it:**
  - Robin Dapp: "please also state why you think the particular assisted-by change is legally insignificant. Otherwise we cannot ACK it" (https://inbox.sourceware.org/gcc-patches/DKH3ERLDA06Y.275DBCYMDRBV0@gmail.com/).
  - Richard Sandiford: "When you use Assisted-by, could you also give a quick summary of how you used Claude?" (https://inbox.sourceware.org/gcc-patches/87a4oe5dr5.fsf@googlemail.com/).
  - Robin Dapp: "add an Assisted-By tag whenever an LLM (or similar) was used in any way" (https://inbox.sourceware.org/gcc-patches/DL5HJBDPK74E.2267YUGT3VUTQ@gmail.com/).

## 5. Review comments asking for better messages
All are [OBS]. Roles: Beulich is x86 and global binutils maintainer, Modra and Clifton are binutils blanket-write, Rozycki is the MIPS maintainer, Marchi is a GDB global maintainer, Wakely leads libstdc++, Merrill is the C++ FE maintainer, Biener and Law are GCC global reviewers, and Earnshaw is the ARM maintainer.

**Missing rationale ("why")**
- Beulich (binutils): "Please can you try to get used to having non-empty descriptions ... It's really the 'why' here that imo would deserve a sentence or two." https://inbox.sourceware.org/binutils/27229e6c-6df9-41be-b9d7-d78eadefc0b2@suse.com/
- Rozycki (binutils): "Please explain in the commit description why this change is needed. Also do you have a test case" https://inbox.sourceware.org/binutils/alpine.DEB.2.21.2510301324140.1185@angie.orcam.me.uk/
- Jens Remus (s390 reviewer): "Please add a short commit message why this is the right thing to do." https://inbox.sourceware.org/binutils/0efb6864-1268-4e75-a3a3-8becd007963e@linux.ibm.com/
- Beulich: "the commit message should mention [uncertainty]. If later someone notices the same issue on Cygwin, they'd know right away" https://inbox.sourceware.org/binutils/db94391e-f7dd-4a3a-8797-2bad2cc81a9d@suse.com/
- Earnshaw (GCC): "Please make sure the commit message contains a brief summary of why this is considered to be the right change" (posted through the Sourceware Forge bot, approval of "testsuite: require cortex-a53 in reg_equal_test.c test"; the source mbox is gcc-patches 2026-July)
- Patrick Palka (GCC): "the commit message could use an explanation of why we can't optimize empty functors in general" https://inbox.sourceware.org/gcc-patches/d614f6bf-43fa-c69a-612a-fd38c5916fb1@idea/

**Empty or too terse**
- Beulich: "Please can all of the patches come with non-empty descriptions? 'Non-empty' as in 'describing what they're for'" (same 0a903228 URL as §2)
- Simon Marchi: "could you please make the commit message actually describe the change?" https://inbox.sourceware.org/binutils/78e8d2e7-7ed5-4b56-af05-28177f85d63d@simark.ca/
- Rozycki: "Please add the missing commit description; naming the MXU specs used" https://inbox.sourceware.org/binutils/alpine.DEB.2.21.2609181659260.57799@angie.orcam.me.uk/
- Wakely (GCC): "The information above should be included in the commit message. Currently the commit message is quite brief" https://inbox.sourceware.org/gcc-patches/CACb0b4nEu2m+TdLOa03ZrFvGQw6K+YUC5pnhYpLdikLDyEzFmQ@mail.gmail.com/

**Unexplained terms, history and caveats**
- Indu Bhagat (SFrame maintainer): "Can you add a one liner in the commit log explaining that term?" https://inbox.sourceware.org/binutils/bfd91b47-0546-4a5e-add6-34dfe6f83c40@oracle.com/
- Beulich: "Please can such anomalies be mentioned in the description, such that ... somebody later finding this commit also knows" https://inbox.sourceware.org/binutils/84560696-70ba-4ad8-8271-4ee02b283d1c@suse.com/
- Harald Anlauf (Fortran): "adjust the commit message to indicate that this is a partial EX implementation" https://inbox.sourceware.org/gcc-patches/591a1f8a-03aa-43b2-9693-9fe5d91fe114@gmx.de/

**Missing testing statement or testcase**
- Law (GCC): "For future patches please note how the patch was tested." https://inbox.sourceware.org/gcc-patches/23f20d84-0a21-46eb-8932-13b78de858ef@oss.qualcomm.com/
- H.J. Lu (x86 binutils): "Please add a testcase to show it makes a difference." https://inbox.sourceware.org/binutils/CAMe9rOrdL_wv2wfKMUT=AXZBv4KYvCfj8aAfcvpeaP0vYFZG=Q@mail.gmail.com/
- Beulich: "As said before, some test is wanted." https://inbox.sourceware.org/binutils/6981bbd7-e078-4f97-888d-1d2db9177f81@suse.com/

**PR references**
- H.J. Lu: "Please mention PR ld/33146 in the commit log for backport tracking" https://inbox.sourceware.org/binutils/CAMe9rOrDL_wv2wfKMUT=AXZBv4KYvCfj8aAfcvpeaP0vYFZG=Q@mail.gmail.com/ (the Message-ID in this URL may be inexact; the message is in the binutils July 2025 mbox, "gas: Move gas_sframe_check")
- Gerald Pfeifer (GCC): "Please mention PR 69374 in the ChangeLog/commit message" https://inbox.sourceware.org/gcc-patches/92736b0e-1acb-5e4c-35ad-bf20201e9fd5@pfeifer.com/

**ChangeLog format (GCC)**
- Kyrylo Tkachov (AArch64): "Missing full stops in ChangeLog entires" https://inbox.sourceware.org/gcc-patches/B0C86724-AFC3-468F-96F6-B2F626C8F852@nvidia.com/
- Biener: "please update the description and the ChangeLog to mention you remove ..." https://inbox.sourceware.org/gcc-patches/CAFiYyc0hz4Gg-JsLa7geB4KXmZVACeQ-4GWP-D8_ZpyfewAjEQ@mail.gmail.com/

**Layout and noise**
- Merrill (GCC): "please wrap the commit message at 76 columns, and keep subject line (after [PATCH]) as close to 50 as is reasonable" https://inbox.sourceware.org/gcc-patches/fdca3b48-76dd-4ec3-8e1b-d34c40a112bc@redhat.com/
- Beulich, on `Change-Id:` trailers: "Can these please be dropped from the commit messages?" https://inbox.sourceware.org/binutils/1439d638-972a-4524-b837-4f6add67d279@suse.com/
- Alan Modra, on this repo's dwarf2 v2: "The above comment and two more copies of it should be removed as it is no longer relevant." (This is about stale code comments, not the message itself.) https://inbox.sourceware.org/binutils/aqKQxBX1yYfndJdB@squeak.grove.modra.org/

None of the archived comments asked for a message to be made shorter. This repo's own reply on the dwarf2 thread called its v1 message "overly wordy"; no reviewer said so.

## 6. GCC vs binutils

| | GCC | binutils |
|---|---|---|
| ChangeLog block in message | **Required**; the hook rejects pushes without one | **Not required** since 2.37 (2021); about a third of commits still include one by habit |
| Machine-checked format | Yes: git_commit.py | None found |
| Free-text body | Not checked; contribute.html requires a description and test results in the submission | Required in substance: "commit messages must also be complete" (Clifton 2021); reviewers enforce it |
| Subject | ≤75 chars after the classifier, component tags, `[PRnnnnn]` [DOC] | "[Patch]" in the e-mail subject [REQ]; nothing else written |
| PR references | Subject PR must match a `\tPR comp/N` line [REQ, hook] | Requested in review only |
| Testing | Bootstrap and regtest required; results must be stated [REQ] | No written rule; testcases demanded in review |
| Legal | FSF assignment or DCO; small changes exempt | FSF assignment or DCO for non-obvious patches |
| LLM | Declines legally significant LLM content **except tests**; `Assisted-by:` **mandatory**; the checker requires it above the ChangeLog block | Declines LLM-generated content **including tests**; `Generated-By:` encouraged only; reviewers read `Co-Authored-By: <AI>` as LLM-generated code, and an AI-written commit message is considered fine (Beulich) |
| Trailers recognised | Co-Authored-By (becomes a ChangeLog author), Signed-off-by, Reviewed-by, etc. | No tooling; `Change-Id:` unwelcome |
