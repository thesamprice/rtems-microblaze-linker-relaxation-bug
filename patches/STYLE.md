# Writing commit messages and comments for these patches

Derived from what has actually been accepted, not from taste. The sample is
`a639e0adaf2` (this repo's `landed/0001`, reviewed by Alan Modra and merged),
the upstream commits around it, and `bfd/` history generally.

Read this before writing a patch, and audit against it before sending. The
rules in [`../CLAUDE.md`](../CLAUDE.md) about keeping comments true still
apply; this is the house style on top of them.

## Subject line

```
ld: microblaze: don't index the local symbol cache
riscv: Set undefined symbol value to 0 if pointer equality isn't needed
bfd/dwarf2: break equal-range function ties by DIE offset
arm: Fix encoding of SG stubs in BE8 mode
```

- `component: imperative phrase`. The component is the tool, the target, or
  the file (`ld:`, `gas:`, `riscv:`, `microblaze:`, `bfd/dwarf2:`); a target
  prefix may follow a tool prefix.
- **55 characters or fewer.** `git format-patch` prepends
  `Subject: [PATCH n/N] `, which is 21 characters, and wraps the header past
  78 — so a 60-character subject that looks fine in `git log` arrives in the
  mail folded across two lines. Check the generated mail, not the commit.
  The reviewed patch's subject is 49 characters.
- No full stop at the end.
- Say what the change does, not what was wrong. "don't index the local symbol
  cache", not "fix out-of-bounds read".

## Body

Wrap at 72 columns. **Two spaces after a sentence-ending full stop** — this is
consistent across `bfd/` history and the reviewed patch.

Order the paragraphs so a reviewer can stop early:

1. **What the code does now.** Name the function. Quote the offending lines,
   indented with a tab.
2. **What goes wrong**, in terms of the data structure, not the symptom.
3. **How it was observed** — one concrete measurement with real numbers or
   addresses.
4. **Why this fix and not another.** Cite precedent as `file:line` and
   `commit`, and say where a cited idiom came from.
5. **What the test does**, and what it shows with and without the change.
6. **Test results**, from a run.

### Say it plainly

The reviewed patch says things like "The bug:", "The fix copies the guard
from bfd/elf32-sh.c:1227-1228", "Test behavior depends on how ld was built".
Flat, declarative, specific. Match that.

Do not editorialise, narrate how you got there, or address the reviewer about
the patch:

| don't write | write |
|---|---|
| MicroBlaze missed it by provenance rather than by argument | MicroBlaze's relaxation was copied from elf32-sh.c, which has no such guard |
| One aggravation worth noting for review | (just state the fact) |
| The symptom that led here: | (state the symptom, or drop it) |
| it bites harder here than on RISC-V | the error is larger here, because ... |
| This is a known defect, not a new one | RISC-V fixed the same defect as PR ld/22756 |
| it presents as the board's fault | the failure is reported against the board |

Other habits to avoid, all of which appeared in a draft of this series:

- `--` as punctuation. Use a comma, a semicolon, or a second sentence.
  Upstream prose does not use it.
- Sentence fragments. "Hence saving the old value rather than restructuring."
- Vague subjects: "It shows when ...", "This is the substantive one".
- Missing "only": "MicroBlaze is the one that does both" should be "the only
  one".

### First person is fine

Upstream uses it for what the author did or chose: "I've done that by
allowing the stub bfd in `_bfd_elf_link_dynobj`", "I thought it good
defensive programming practice", "I chose to provide the missing sections".
Use it for exactly that, and for the limits of what you checked.

### Say what you did not verify

The repo rule is to verify claims; the corollary is to mark the ones you
could not. "I have only tested microblaze" and "I am not claiming sh is
affected" belong in the message. A reviewer who finds an unmarked guess stops
trusting the rest.

## ChangeLog block

Binutils generates `ChangeLog` from the git log, so the entry goes at the end
of the message. Directory header, then tab-indented entries whose paths are
**relative to that directory**:

```
bfd/
	* elf32-microblaze.c (microblaze_elf_relax_section): Skip a global
	symbol already reached through another elf_sym_hashes slot.

ld/
	* testsuite/ld-microblaze/relax-wrap.s: New file.
	* testsuite/ld-microblaze/relax-wrap.d: New test.
```

- One blank line between directory blocks.
- `New file.` for sources a test needs, `New test.` for the `.d`, `Likewise.`
  to repeat the previous verb.
- Each entry is a sentence, capitalised, with a full stop.
- A single-directory patch may omit the header, but these touch `bfd/` and
  `ld/`, so both are required.

## Trailers

One blank line after the ChangeLog block, then:

```
Signed-off-by: Sam Price <thesamprice@gmail.com>
Assisted-by: Claude <noreply@anthropic.com>
```

- `Assisted-by:`, **never** `Co-Authored-By:` — see `../CLAUDE.md`. The form
  used throughout this repo is `Assisted-by: Claude <noreply@anthropic.com>`;
  17 of the patches here use exactly that, and variants that name a model
  version are drift, not convention.
- `Signed-off-by:` is a legal assertion about provenance. The human sending
  the patch adds it; it is not generated. Check it is present before sending.

## Code comments in the patch

- Explain why, not what. The line above already says what.
- When copying an idiom from another backend, say so and give `file:line`.
  The reviewed patch does this and it is what made the two-line guard
  obviously correct.
- Sentence case, full stop, two spaces between sentences, same as the prose.
- A comment that outlives the code it describes is worse than none. When a
  line changes, read the whole hunk with `git diff -U15` and fix every comment
  the change falsified, in the same patch. `../CLAUDE.md` has the cautionary
  example.

## Cover letter

`patches/<series>/0000-cover-letter.txt`: first line is the subject, then a
blank line, then the body. `tools/make-outbox.sh` splices it into the
generated `[PATCH 0/N]`.

- Say what the series is and in what order to apply it.
- One short paragraph per patch, numbered `n/N`, matching the generated
  subjects. **Cross-check those numbers** — a cover that enumerates `1/7`
  when the series is `1/5` has happened here.
- Include a review walkthrough for anything non-obvious: what to read first,
  what to check, and how to reproduce the result. See
  `binutils-relax/0000-cover-letter.txt`.
- Testing paragraph last, with numbers from a run.

## Before sending

- `contrib/check_GNU_style.py` on each patch.
- `git diff --check` for whitespace.
- `git am` the series onto pristine upstream master; confirm the tree matches
  what you tested.
- Re-read every message against this file.
