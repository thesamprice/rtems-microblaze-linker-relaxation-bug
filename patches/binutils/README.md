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
- `make check-ld`, target `microblaze-xilinx-rtems7`, upstream master: 476 expected
  passes without the new tests, 478 with them, 13 pre-existing unexpected failures
  either way. The delta is exactly the two new passes and the failure set is
  byte-identical.
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
