# Corner-case coverage and the correctness argument for `BLTi TRIAL_H`

Written in answer to a review of `moddi3.S` that asked two things:

> You're using the signed sign bit of the 64-bit subtraction to decide an
> unsigned comparison. A negative subtraction result does not universally
> imply `RES < OPD` for unsigned operands. [...] I'd explicitly prove it or
> replace it with a borrow-based test.

> The algorithm uses a 64-bit partial remainder, but general restoring
> division can require an additional high bit for a shifted partial
> remainder.

Both are answerable, and the same bound answers both. The headline finding is
that **the upstream torture test does not reach the state in question**, so
"`arith-rand-ll.c` passes" is not on its own evidence that the comparison is
sound.

## The argument

Write `R` for the partial remainder (`RES`), `D` for `|divisor|` and `X` for
`|dividend|`. Two facts:

1. `D <= 2^63`. `D` is the magnitude of a signed 64-bit value, and the largest
   is `|LLONG_MIN| = 2^63`.
2. **Loop invariant: `0 <= R < D` on entry to every iteration.** True at entry
   (`R = 0`, and `D >= 1` because a zero divisor returns early). Preserved:
   the shift gives `R' = 2R + b <= 2D - 1`, and the conditional subtract
   leaves either `R'` when `R' < D`, or `R' - D <= D - 1`. Either way `< D`.

From those, at the point of the test the true integer `R' - D` lies in
`[-D, D-1]`, hence in `[-2^63, 2^63 - 1]` — which is exactly the 64-bit
two's-complement range. A value in range is stored with its sign bit equal to
the sign of the true difference, so `BLTi TRIAL_H` decides `R' >= D` correctly.
The signed test and a borrow-based test cannot disagree here.

The second question falls out of the same bound: `R' <= 2D - 1 <= 2^64 - 1`,
so the shift never carries out of `RES_H` and no 65th bit is needed. In
practice the bound is not even tight — the largest partial remainder
reachable is exactly `2^63`, never more.

## What the tests actually reach

`corner-model.c` is a bit-exact host model of the loop: 64-bit `RES` with the
carry out of `RES_H` discarded, and the keep/skip decision taken from the sign
bit of the 64-bit difference, exactly as `BLTi TRIAL_H` does. It counts the
states the review names, and separately compares the sign-bit decision against
a true unsigned compare on every iteration.

| | iterations | `R >= 2^63` | `\|D\| == 2^63` | sign test vs unsigned |
|---|---|---|---|---|
| `gcc.c-torture/execute/arith-rand-ll.c` | 331,380 | **0** | **0** | 0 disagreements |
| the harness's 4701 vectors | 266,260 | 6 | 26 | 0 disagreements |
| exhaustive corner (below) | — | 8,192 cases | 32,768 | 0 disagreements |

So `arith-rand-ll.c` never drives the partial remainder over the sign
boundary and never uses an `LLONG_MIN` divisor. It reaches `|D| >= 2^62` 411
times, which gets close, and no further. The 4701-vector set does reach it,
because `LLONG_MIN` and `LLONG_MAX` are in its structured operand list.

## Why it is so hard to reach

`R' >= 2^63` needs `R >= 2^62`, and `R < D`, so it needs `D > 2^62`. Since
`R` after `i` iterations is the top `i` bits of `X` reduced mod `D`, and
`X <= 2^63`, the only way to get there is for **both** magnitudes to sit
within a hair of `2^63`.

`corner-exhaustive.c` sweeps exactly that region: `|X|` and `|D|` each within
4096 of `2^63`, all four sign combinations, 67,108,864 cases.

```
  max partial remainder           0x8000000000000000
  cases reaching R >= 2^63        8192
  sign test != unsigned compare   0
  invariant R_old < D violated    0
  wrong answers                   0
```

Every one of the 8192 has **dividend exactly `LLONG_MIN`**, and the partial
remainder reaches exactly `2^63` and never exceeds it.

## On the target

`corner-gen-vectors.c` emits those 8192 pairs as a `vectors.h` for the target
harness. Run on `qemu-system-microblaze` and `qemu-system-microblazeel`,
machine `petalogix-s3adsp1800`:

| | big-endian | little-endian |
|---|---|---|
| upstream `moddi3.S` | hangs | hangs |
| the patched routine | 8192 / 8192 | 8192 / 8192 |
| the no-quotient variant | 8192 / 8192 | 8192 / 8192 |

## Reproducing

```sh
cc -O2 -o corner-model corner-model.c && ./corner-model
cc -O2 -o corner-exhaustive corner-exhaustive.c && ./corner-exhaustive
cc -O2 -I../harness -o corner-over-vectors corner-over-vectors.c && ./corner-over-vectors
```

`corner-over-vectors.c` needs `../harness/vectors.h`, which `harness/run.sh`
generates.

## The conclusion for the submission

The comparison is sound, and provably so rather than incidentally. But the
reviewer is right that the existing test does not establish it: the state only
arises for an `LLONG_MIN` dividend against a divisor within 4096 of `2^63`,
which `arith-rand-ll.c` never generates. That is worth saying in the patch,
together with the invariant, so the next reader does not have to redo this.
