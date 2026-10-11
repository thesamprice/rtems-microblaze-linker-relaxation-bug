# Running gcc.c-torture/execute for MicroBlaze

All 1685 tests, compiled at `-O2` with `microblaze-rtems7-gcc` 12.4.1 and run
bare-metal on `qemu-system-microblaze[el]`, machine `petalogix-s3adsp1800`, on
both byte orders, with the unpatched assembly `__moddi3`, with the patched one,
and with libgcc's generic C.

## The result for the series

| `__moddi3` | tests passing (of 1685) |
|---|---|
| unpatched assembly | 1631 |
| patched (`harness/moddi3-noquo.S`) | **1633** |

The patched routine recovers exactly two tests over the unpatched one, on both
byte orders, and changes nothing else:

| test | unpatched, big-endian | unpatched, little-endian |
|---|---|---|
| `pr50865.c` | **hangs** | aborts |
| `arith-rand-ll.c` | aborts | aborts |

`pr50865.c` is the one to quote: four lines of `INT64_MIN % 1LL`, precisely the
`LLONG_MIN` non-termination, in the tree since PR middle-end/50865 in 2011.
An in-tree execute test has been able to catch this for fifteen years.

## Everything else that fails is explained

An earlier version of this file reported 19 unexplained run-time failures and
suggested somebody should look at them. That was wrong: **they were all this
harness.** The count is now zero, and the three fixture bugs are worth writing
down because each produced convincing-looking failures.

**`-ffreestanding` removes the implicit `return 0` from `main`.** This was 13 of
the 19. A freestanding implementation gives `main` no special status, so GCC
stops emitting the C99 fallthrough return — and most of these tests fall off the
end of `main` rather than calling `exit`:

```
  hosted                -ffreestanding
    bgeid r18,$L11        bgei  r18,$L11
    addk  r3,r0,r0        rtsd  r15, 8
    rtsd  r15, 8
```

That `addk r3,r0,r0` is the `return 0`. Without it the return register holds
whatever was last computed, which is why the exit codes looked meaningful —
`-2`, `10`, `115`, `-128` were results, not error codes. Compile hosted.

**A 256KB stack.** `pr28982b` and `memcpy-1` hang on it and pass with 4MB.

**A stubbed `printf`.** `printf-1` wants the real thing.

Separately, and not a fixture bug: this runs **gcc-master's testsuite against a
gcc 12.4.1 compiler**, so tests added for post-12 fixes fail by construction.
`pr111613` and `pr115033` do not exist in gcc 13.3.0's testsuite at all.
`pr111151` folds `max(0x80000000u, 2) * 2` to `4` instead of `0` on gcc 12 —
real, but fixed upstream after 12 and not backported. Use a testsuite matching
the compiler, or expect these four.

## Final tally

With the harness fixed, the patched `__moddi3`, both byte orders identical:

| | count | what it is |
|---|---|---|
| pass | 1633 | |
| link failure | 35 | want libc this deliberately minimal runtime lacks |
| compile failure | 13 | want `__int128`, decimal float, or x86 `st(1)` asm — DejaGnu marks these UNSUPPORTED via `dg-require-effective-target`; this harness has no such notion |
| run-time failure | 4 | `printf-1` (stubbed `printf`) and the three post-gcc-12 tests above |
| **unexplained** | **0** | |

## Does any test reach the sign boundary?

No — measured. `moddi3-instr.c` is a `__moddi3` that computes the same answer by
the same recurrence but reports on the UART the first time the partial remainder
reaches `2^63`. `scan.sh` links it into a test and runs it. Across all 1685:
1667 never reference `__moddi3`, 5 call it (`920604-1`, `arith-rand-ll`,
`pr33669`, `pr50865`, `pr85582-1`), and **none reaches the state**.

Outside this directory, 327 runnable tests do 64-bit modulo, 289 for other
architectures; of the 38 arch-neutral ones only 3 emit the call, with divisors
2, 5, -2 and `n - 10000`. Reaching the boundary needs `|D| > 2^62`, so none can.

That is structural: `R' >= 2^63` needs `R >= 2^62`, and `R < D`, so it needs
`|D| > 2^62` *and* `|X|` within a hair of `2^63`. Nothing in the tree pairs
those. `gcc.c-torture/execute/divmod-2.c`, sent as a separate patch from
[`../../tests/`](../../tests/), does. See #37.

## Was the suite being run?

Running it cannot prove nobody else does, and `gcc-testresults`' archive search
is behind Anubis. What is checkable: across the whole of `gcc/testsuite` only 13
files mention `microblaze`, almost all ChangeLogs; the only real references are
`gcc.dg/combine_ashiftrt_2.c` and `g++.dg/cpp0x/constexpr-rom.C`, both
`dg-do compile`, plus `microblaze.exp`, `lib/scanasm.exp` and
`lib/target-supports.exp`. There is **no `xfail` keyed on microblaze anywhere**,
and not one execute test carries a microblaze marker. `visium` appears in 40
files, `nds32` in 21.

Set against the harness findings above, the useful statement is narrower than
the one this file used to make: the suite passes for MicroBlaze once it is run
correctly, and a test that catches this bug has existed since 2011.

## Reproducing

Both scripts take `TOOLCHAIN` and `QEMU`, as `harness/run.sh` does.

```sh
export TOOLCHAIN=<rtems7-tools>/bin QEMU=<qemu-build>

# build the runtime objects once, per byte order
for e in be le; do
  E=""; [ $e = le ] && E=-mlittle-endian
  microblaze-rtems7-gcc $E -O2 -ffreestanding -nostdlib -c rt2.c    -o $e-rt2.o
  microblaze-rtems7-gcc $E    -ffreestanding -nostdlib -c start3.S  -o $e-start3.o
  microblaze-rtems7-gcc $E -O2 -ffreestanding -nostdlib -c ../../harness/moddi3-noquo.S  -o $e-md-noquo.o
  microblaze-rtems7-gcc $E -O2 -ffreestanding -nostdlib -c ../../harness/moddi3-stock.S  -o $e-md-stock.o
done

# one test, or the whole suite
./run-one.sh be noquo <path>/gcc.c-torture/execute/pr50865.c
ls <path>/gcc.c-torture/execute/*.c | xargs -P 8 -I{} ./run-one.sh be noquo {} > out.txt
```

`run-one.sh` carries the three fixture lessons as comments; do not undo them.
The runtime is `rt2.c` plus `start3.S`: `.bss` cleared, `main` returning *n*
becomes `exit(n)`, `abort()` and a non-zero exit print a marker, and the
exit-and-counter device at `0xFF000000` shuts QEMU down so runs are bounded.

## Raw results

`final-<endian>-noquo.txt` and `final-<endian>-stock.txt` are the runs above;
`scan-be.txt` is the boundary scan.

Tracked as #36 — a real DejaGnu board file instead of a shell loop, the full
torture option set rather than `-O2` alone, and the procedure upstreamed.
