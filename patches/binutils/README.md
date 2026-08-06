# binutils patch

**Complete and submittable**: the bfd fix *and* two dejagnu tests in one
`git am`-able patch against upstream master `b7da195b94` (2.47.50.20260805).
The commit message carries the analysis and the ChangeLog entries.

No `ChangeLog` file edits are included, and none are needed. Since 2021-07-03
binutils generates those from the git log — see
`binutils/README-how-to-make-a-release`, which regenerates with
`gitlog-to-changelog --since=2021-07-03` and describes that date as "when
changelog entries were no longer required". The entry belongs in the commit
message, which is where it is.

```sh
cd binutils-gdb
git am .../0001-microblaze-don-t-index-the-local-symbol-cache-with-a-.patch
```

It also applies to the Xilinx binutils 2.36 snapshot used by the RTEMS MicroBlaze
toolchain — the surrounding code is unchanged there — though the line numbers differ,
so use `git apply -3` or `patch -l` if it does not go on cleanly.

## Verified

- Upstream master, ASan build: the reproducer reports a heap-buffer-overflow on every
  run without the patch, clean on every run with it. See
  [`../../testcase-upstream/`](../../testcase-upstream/).
- Xilinx 2.36, ASan build: same, via the `--gc-sections` route. See
  [`../../testcase/`](../../testcase/).

Note on evidence: the RTEMS material elsewhere in this repository is *motivation* --
why the bug matters to a real project -- and is not validation for the patch. The
validation is the ASan reproducer and the binutils testsuite below.
- **Whole binutils `make check`**, target `microblaze-xilinx-rtems7`, upstream master:

  | component | baseline | patched |
  |---|---|---|
  | gas | 323 pass, 2 fail | identical |
  | binutils | 92 pass, 17 fail | identical |
  | ld | 476 pass, 13 fail | 478 pass, 13 fail |

  The only difference in the entire testsuite is the two tests the patch adds. The
  32 pre-existing failures are host artifacts and are present either way. Raw `.sum`
  files for both runs: [`../../binutils-testsuite/`](../../binutils-testsuite/).
- The new tests fail if the addend is corrupted, verified by injecting an
  unconditional four-byte subtraction at the same place. They do not fail on an
  unfixed linker, because the effect of the out-of-bounds read is heap-dependent;
  see [`../../ld-microblaze/`](../../ld-microblaze/).
- `git diff --check` reports no whitespace errors; indentation is tabs, matching the
  surrounding GNU style.

## Contents

```
 bfd/elf32-microblaze.c                          |  3 +
 ld/testsuite/ld-microblaze/microblaze.exp       | new
 ld/testsuite/ld-microblaze/relax-addend.s       | new
 ld/testsuite/ld-microblaze/relax-addend-support.s | new
 ld/testsuite/ld-microblaze/relax-addend.ld      | new
 ld/testsuite/ld-microblaze/relax-addend.d       | new
 ld/testsuite/ld-microblaze/relax-addend-data.d  | new
```

## Where to send it

Sourceware Bugzilla against `ld` / MicroBlaze, plus the patch to
binutils@sourceware.org. Add your own `Signed-off-by:` before sending.
