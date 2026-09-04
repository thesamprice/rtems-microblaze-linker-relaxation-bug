<!-- Per-patch analysis template. Every patch doc follows this shape so a
     reviewer can read any one of them the same way. Keep prose tight, one
     idea per sentence. Cite code as path:line so it is clickable. -->

# <component> <NNNN>: <one-line title>

**Patch:** `<path to the .patch in this repo>`
**Target:** `<upstream repo>` at base commit `<sha>` (`<date>`)
**Files touched:** `<file>`, `<file>`
**Status:** <sent upstream / ready / independent — from patches README>

## What it does
<2-4 sentences: the defect or gap, and the change.>

## Upstream audit: is this already fixed?
<State plainly whether current upstream master already carries an equivalent
 fix. Say what you checked (the file/function in the latest tree, any related
 commit) and the result. If it is genuinely still open, say so and give the
 evidence — e.g. the code is byte-identical to the base commit, or the port
 never had the file at all.>

## Why it survived so long unpatched
<The honest reason. Usually: nobody runs this path on MicroBlaze (the glibc
 testsuite is never run on it; build-many-glibcs only compiles), or the
 default masks it, or the feature was never wired up when the port landed.
 Name the port commit / era if known.>

## What a reviewer should sanity-check (this port)
<Bullet list of path:line in the PATCHED area a reviewer should read to
 confirm correctness. Include the exact constants/offsets that matter and
 why they are right (e.g. RA column 15, RETURN_ADDR_OFFSET 8).>

## How other processors do the same thing
<For each analogous arch, the file:line and a one-line note on what to compare.
 Pick the closest 2-4 arches. This is the reviewer's correctness oracle.>

## Same-processor code that does related logic
<Other MicroBlaze code that must stay consistent with this patch, path:line.
 E.g. if the patch sets an offset, where else that offset is assumed.>

## Other cross-checks
<Anything else: ABI documents, kernel source (signal frame layout), the ELF
 psABI, related open bugs, interactions with other patches in this series.>

## How to verify on real hardware
<Concrete steps that do NOT need the qemu/docker harness: what to compile,
 what to run on the board, what output proves the fix. The user will do this
 on a Linux host with real MicroBlaze hardware.>
