# Running gcc.c-torture/execute for MicroBlaze

The cover letter used to assert that "the execute testsuite does not appear to
be run for MicroBlaze at all" and that this was "likely not the only thing
hiding". Both were inferences. This is the measurement.

All 1685 tests in `gcc.c-torture/execute`, compiled at `-O2` with
`microblaze-rtems7-gcc` 12.4.1 and run bare-metal on
`qemu-system-microblaze[el]`, machine `petalogix-s3adsp1800`, on both byte
orders, three times over: with the unpatched assembly `__moddi3`, with the
patched one, and with libgcc's generic C.

## The result that matters for the series

| `__moddi3` | tests passing (of 1685) |
|---|---|
| unpatched assembly | 1590 |
| patched (`harness/moddi3-noquo.S`) | **1592** |
| generic C from `libgcc2.c` | **1592** |

The patched routine gives **identical results on every one of the 1685 tests,
on both byte orders, to the generic C** — not just the same totals, the same
verdict test by test. So the fix recovers exactly what the bug costs and
changes nothing else in the suite.

The two tests the unpatched routine loses:

| test | unpatched, big-endian | unpatched, little-endian |
|---|---|---|
| `pr50865.c` | **hangs** | aborts |
| `arith-rand-ll.c` | aborts | aborts |

`pr50865.c` is the one to quote. It is four lines of `INT64_MIN % 1LL` and
`INT64_MIN % l1` — precisely defect 4, the `LLONG_MIN` non-termination — and
it has been in the tree since PR middle-end/50865 in 2011. An in-tree
execute test has therefore been able to catch this for fifteen years.

This corrects two earlier claims of mine: that only `arith-rand-ll.c` detects
the bug, and that no torture test reaches the `LLONG_MIN` hang. Both wrong.

## Was the suite being run?

Running it myself cannot prove nobody else does. Two things are checkable:

- Across the whole of `gcc/testsuite`, only 13 files mention `microblaze`,
  and most are ChangeLogs. The only real references are
  `gcc.dg/combine_ashiftrt_2.c` and `g++.dg/cpp0x/constexpr-rom.C`, both
  `dg-do compile`, plus `microblaze.exp`, `lib/scanasm.exp` and
  `lib/target-supports.exp`. There is **no `xfail` keyed on microblaze
  anywhere**, and not one execute test carries a microblaze marker. For
  comparison, `visium` appears in 40 files and `nds32` in 21.
- `gcc-testresults` could settle it directly, but its archive search is behind
  Anubis and would not answer from here.

So the strong form of the claim is not established. What is established is
that a test which catches this has been in the tree since 2011 and the bug
survived to 2026.

## Is anything else hiding?

Yes, though less than the raw numbers suggest, and I have not triaged it.

Of the 1685, with the patched routine: 1592 pass, 54 fail to link against my
deliberately minimal runtime (they want libc this harness does not provide,
which is not a target failure), 6 fail to compile, and 23 fail at run time.

Of those 23, four — `printf-1`, `memchr-1`, `pr90949`, `return-addr` — want
real stdio, which `rt2.c` stubs out, so they are my harness's fault. That
leaves **19 unexplained execution failures**, the same 19 on both byte orders.
Three I spot-checked (`bitfld-signed1-1`, `signed1bitfield-1`,
`minmaxcmp-1`) pass when built and run natively, so the tests themselves are
sound; the rest I have not looked at. They are not claimed here as MicroBlaze
bugs, only as unexplained.

A methodological note, since it cost ten of them: the first pass ignored each
test's own `dg-options`. Ten tests failed purely for that — nine wanted
`-fwrapv` or `-fno-strict-overflow` and one `-finstrument-functions`. `one3.sh`
honours them. Anyone repeating this should not trust a torture run that
ignores `dg-options`.

## Tracked as

Issue #36 -- get this running properly under DejaGnu, triage the 19, and
upstream the procedure.

## Reproducing

Both scripts take `TOOLCHAIN` and `QEMU` from the environment, as
`harness/run.sh` does.

```sh
export TOOLCHAIN=<rtems7-tools>/bin QEMU=<qemu-build>

# one test
./one2.sh be noquo <path>/gcc.c-torture/execute/pr50865.c

# the whole suite, one byte order and one __moddi3 variant
ls <path>/gcc.c-torture/execute/*.c | xargs -P 8 -I{} ./one2.sh be noquo {} > res.txt

# re-run failures with their own dg-options honoured
./one3.sh be noquo <test.c>
```

`one2.sh` takes `be`/`le` and `libgcc`/`noquo`/`stock`; the named `__moddi3`
object is linked ahead of `-lgcc` so it wins. Needs `$e-rt2.o`,
`$e-start3.o` and `$e-md-<variant>.o` built first, and the toolchain and QEMU
from the top-level README.

`rt2.c` and `start3.S` are the runtime: `.bss` is cleared, `main` returning
*n* becomes `exit(n)`, `abort()` and a non-zero `exit` print a failure marker,
and the exit-and-counter device at `0xFF000000` shuts QEMU down so a run is
bounded.

## Raw results

`res-<endian>.txt` is the generic C, `res-<endian>-noquo.txt` the patched
assembly, `res-<endian>-stock.txt` the unpatched one, and
`retry-<endian>.txt` the failures re-run with `dg-options` honoured.
