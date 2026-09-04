# Test plan: validating the patch series on a Linux host with real hardware

This turns the "what to run" discussion into a checklist. It assumes you have
built the patched binutils, gcc and glibc (the ordering and configure lines are
in [`../harness/run.sh`](../harness/run.sh); on a native Linux host you do not
need the qemu wrapper or `--init`). Three suites execute on the board (glibc,
the gcc exception subset, gdb); the binutils suite runs entirely on the host.

Run them in this order: binutils (fast, host) -> glibc (the real validation) ->
gcc exception subset -> gdb smoke test.

## What each run proves

| Run | Where | Patches it exercises |
|---|---|---|
| binutils `make check` | host | binutils 0004, 0006, 0007, 0008, 0009 (and 0001/0002, already upstream) |
| glibc `make check` + nptl/rt | board | all seven glibc patches |
| gcc exception subset | board | gcc 0001, gcc 0002 |
| gdb error-handling smoke test | board | glibc 0001 in its original context |
| record kernel version/config | board | substrate for gcc 0001 (signal-frame layout) |

## 0. Record the board

```sh
ssh $BOARD 'uname -a; zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_MICROBLAZE|FUTEX|COMPAT" ; cat /proc/cpuinfo | head'
```

Keep this with the results. gcc 0001 assumes the kernel's `rt_sigframe` layout;
if a future kernel changes it, this is where a regression would surface.

## 1. binutils (host only, minutes)

The gas/ld/bfd tests cross-assemble and cross-link and check the output with
`readelf`/`objdump`; no board is involved. From the binutils build directory:

```sh
make -C gas check RUNTESTFLAGS="gas/microblaze/*.exp gas/elf/*.exp gas/all/*.exp"
make -C ld  check RUNTESTFLAGS="ld-microblaze/microblaze.exp ld-elf/eh*.exp"
grep -E "^# of|^(FAIL|ERROR|UNRESOLVED)" gas/testsuite/gas.sum ld/ld.sum
```

Note the runtest pattern is relative to the testsuite root:
`gas/microblaze/*.exp`, not `microblaze/*.exp`, which silently runs nothing.

Expected: the MicroBlaze gas and ld tests pass, including the new `cfi`,
`reloc_pcrel` (patch 0009) and the CFI FDE encoding. Four `gas/all` tests
(`difference of two undefined symbols`, `simple forward references`, `forward
references`, `all end`) fail on the **unpatched** assembler as well, so build a
baseline `as`/`ld` without the series and confirm those four are the only
difference. See [`binutils-0006`](binutils-0006-gas-cfi-directives.md),
[`binutils-0009`](binutils-0009-pcrel-data-relocs.md).

## 2. glibc (executes on the board, hours)

glibc ships a ready-made remote runner, `scripts/cross-test-ssh.sh`, which
copies each test and the freshly built libraries to the board and runs them
there. Passwordless ssh and `rsync` on the target are required.

```sh
# from the glibc build directory
make test-wrapper="$SRC/glibc/scripts/cross-test-ssh.sh root@$BOARD" check
# nptl and rt are ordered last and get skipped if an earlier step fails, so
# run them explicitly the same way:
for d in nptl rt; do
  make test-wrapper="$SRC/glibc/scripts/cross-test-ssh.sh root@$BOARD" \
       -C "$SRC/glibc/$d" objdir="$(pwd)" tests
done
cat */*.test-result | cut -d: -f1 | sort | uniq -c
```

The result files match the format of
[`../glibc-longjmp-chk/evidence/full-check-results-*.txt`](../glibc-longjmp-chk/evidence),
so a board run diffs cleanly against the recorded qemu runs. On hardware expect
the qemu-only buckets to clear: the emulation-speed timeouts, the PI/robust
futex tests, and the LD_AUDIT hangs should now pass. What is left should be a
small set of genuine environment limits, not code failures.

Highest-signal individual tests (all in the main run): `debug/tst-longjmp_chk*`
(0001), `math/` as a whole (0002), `elf/tst-array1-cmp` and `tst-initorder-cmp`
(0003), `stdlib/tst-*context*` (0004), `nptl/tst-cancel*`/`tst-cleanup*` (0005),
`debug/tst-backtrace*` (0006), `elf/tst-unwind-main` (0007).

## 3. gcc, the exception subset (executes on the board)

The full gcc testsuite is days long; only the execute tests that throw and
unwind matter for gcc 0001/0002. Drive them onto the board with a DejaGnu board
file (sample below), then:

```sh
make check-g++     RUNTESTFLAGS="--target_board=microblaze-ssh eh.exp"
make check-gcc     RUNTESTFLAGS="--target_board=microblaze-ssh dg-torture.exp=*"
make check-target-libstdc++-v3 RUNTESTFLAGS="--target_board=microblaze-ssh"
```

The libstdc++ run is the strongest single check: it throws and catches across
shared-library boundaries, exercising the new `.eh_frame_hdr` search table
(0002) end to end. For 0001, add a test that unwinds out of a signal handler
(`_Unwind_Backtrace` from a `SIGALRM` handler) so the signal-frame path runs
against the real kernel sigframe rather than qemu's trampoline page. See
[`gcc-0001`](gcc-0001-signal-frame-glibc-layout.md),
[`gcc-0002`](gcc-0002-pcrel-eh-encodings.md).

## 4. gdb, smoke test (executes on the board)

You have no gdb patches; gdb is the original reporter of glibc 0001 (native gdb
looped forever handling its own errors because the fortified `longjmp` hung).
The direct check is not the gdb testsuite but the reproducer: on the board, run
native gdb, trigger an error at the prompt (an unknown command, or Ctrl-C during
a command), and confirm it returns to the prompt instead of spinning. If you
want breadth, the gdb testsuite runs over the same ssh board file, but it is
large and mostly orthogonal to this series.

## Sample DejaGnu board file (`microblaze-ssh.exp`)

Put this on `DEJAGNU`'s board search path (or point `--target_board` at its
directory) and set `BOARD_HOST` to the target.

```tcl
# microblaze-ssh.exp -- run execute tests on a real MicroBlaze board over ssh.
load_generic_config "unix"
process_multilib_options ""

set_board_info connect  ssh
set_board_info hostname  $env(BOARD_HOST)
set_board_info username  root

# transfer with scp/rsync; no simulator, no gdb stub
set_board_info protocol      standard
set_board_info rsh_prog      ssh
set_board_info rcp_prog      scp
set_board_info shell_prompt  "# "

# the board runs the freshly built dynamic loader; make the test libraries
# reachable there (rsync the glibc testroot to /opt/glibc-test first).
set_board_info ldflags "-Wl,-dynamic-linker=/opt/glibc-test/lib/ld.so.1 -Wl,-rpath,/opt/glibc-test/lib"
```

## Sample glibc test-wrapper (if not using cross-test-ssh.sh)

`scripts/cross-test-ssh.sh` is the supported path and handles the library copy
for you. A minimal hand-rolled wrapper, for reference, is just:

```sh
#!/bin/sh
# board-wrapper.sh -- glibc test-wrapper that runs one test on the board.
# glibc calls it as:  board-wrapper.sh [VAR=val ...] prog [args...]
set -e
host=root@$BOARD
# copy the test binary next to the freshly built libraries already on the board
scp -q "$(echo "$@" | awk '{for(i=1;i<=NF;i++) if($i !~ /=/){print $i; exit}}')" \
    "$host:/opt/glibc-test/t"
exec ssh "$host" "cd /opt/glibc-test && env $* ./t"
```

Prefer `cross-test-ssh.sh`: it tracks each test's own library-path and argv the
way the in-tree tests expect, which the one-liner above does not.

## Faster than a full run: per-patch reproducers

Three patches are better shown by a small program than by a suite:

- **glibc 0002** is a testsuite-config fix with no runtime behavior; the only
  "test" is that `math/` stops aborting. Nothing to run on hardware beyond the
  suite.
- **glibc 0003 (destructors)** and **binutils 0008 (canonical PLT)** each have a
  five-line reproducer in their analysis doc that proves the fix in seconds on
  the board.

Each patch's own analysis file has its "How to verify on real hardware" section
with the exact program and expected output.
