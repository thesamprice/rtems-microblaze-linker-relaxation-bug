# binutils patch

`git am`-able, generated against upstream binutils master `b7da195b94`
(2.47.50.20260805). The commit message carries the analysis and a ChangeLog entry, in
the form binutils expects.

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
  passes, 13 pre-existing unexpected failures, and the full result lists are
  byte-identical with and without the patch.
- `git diff --check` reports no whitespace errors; indentation is tabs, matching the
  surrounding GNU style.

## Where to send it

Sourceware Bugzilla against `ld` / MicroBlaze, plus the patch to
binutils@sourceware.org. Add your own `Signed-off-by:` before sending.
