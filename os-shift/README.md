# MicroBlaze `-Os`: 64-bit shift emits unreachable code, silently wrong results

Found by the DejaGnu board in [`../dejagnu/`](../dejagnu/) on its first full
`gcc.c-torture/execute` run — the kind of bug only execution testing finds.
Five tests, seven FAILs, one root cause.

## What happens

At `-Os`, on a CPU **without a barrel shifter**, GCC implements a 64-bit shift
with a software loop. That loop is a multi-instruction sequence, and it can be
emitted *after* an unconditional `brid`, where only the single delay-slot
instruction executes and the rest is unreachable. The result register keeps a
stale intermediate, and the wrong answer is returned with no diagnostic.

From `repro-Os.s`, the `x >> 8` case:

```
	or	r4,r5,r6        ; low word -- correct
	brid	$L22            ; branch, one delay slot
	ori	r18,r0,8        ; <- the only instruction that runs
	addk	r5,r3,r0        ; \
	addik	r18,r18,-1      ;  |  unreachable: computes high >> 8
	bneid	r18,.-4         ;  |
	sra	r5,r5           ; /
$L22:
	rtsd	r15, 8
	addk	r3,r5,r0        ; r3 = r5, which is still high << 24
```

`r5` holds the carry term `high << (32 - n)` from the earlier left-shift loop,
so the returned high word is that instead of `high >> n`. The low word is
correct, which is why the corruption is easy to miss.

Measured on `0x7654321fedcba980 >> 8`:

```
  want = 0x00765432_1fedcba9
  got  = 0x1f000000_1fedcba9      (0x1f000000 == 0x7654321f << 24)
```

## Trigger

All four needed together:

- `-Os`. `-O0`, `-O1`, `-O2` and `-O3` are all unaffected.
- No barrel shifter, so the shift becomes a loop. `-mxl-barrel-shift` avoids
  it entirely — that is the single switch that makes all five tests pass.
- A 64-bit shift by **6 or more**. Smaller counts are emitted inline without a
  loop and are correct.
- The shift inside a `switch`, so there is a shared epilogue to branch to.

Both byte orders are affected.

## Affected tests

`gcc.c-torture/execute`, at `-Os`:

| test | what it does |
|---|---|
| `ashrdi-1.c` | 64-bit arithmetic shift right, constant and variable |
| `bf64-1.c` | 64-bit bitfields |
| `pr42833.c` | |
| `pr79121.c` | |
| `pr82524.c` | |

All five pass at every other optimisation level, and all five pass at `-Os`
with `-mxl-barrel-shift`.

## Reproducing

`repro.c` is self-contained for the bare-metal board: a `switch` of constant
64-bit arithmetic right shifts, checked against the same shifts done inline.

```sh
export TOOLCHAIN=<tools>/bin MB_QEMU=<qemu>/qemu-system-microblaze
microblaze-rtems7-gcc -Os -w repro.c -nostartfiles \
  -T../dejagnu/mb-qemu-board/mb-qemu.ld \
  -Wl,../dejagnu/mb-qemu-board/obj/be/crt0.o \
  -Wl,../dejagnu/mb-qemu-board/obj/be/runtime.o -lc -lgcc -o repro.elf
../dejagnu/mb-qemu-board/mb-qemu-run repro.elf
```

Prints the wrong values and exits non-zero at `-Os`; prints `OK` at `-O2` or
with `-mxl-barrel-shift`.

`repro-Os.s` and `repro-O2.s` are the generated assembly for comparison; the
dead code is in `$L11` onward in the `-Os` one.

## Status: already fixed on trunk — do not report upstream

Reproduced on `microblaze-rtems7-gcc` 12.4.1 (RTEMS 7 toolchain), both byte
orders. **It does not reproduce on current trunk (17.0.0).**

Checked by compiling `repro.c` at `-Os` with a trunk `microblaze-linux-gnu`
`xgcc` and reading the output: trunk emits the high-word shift **unrolled
inline, straight-line**, with no `brid` to a shared epilogue. There is no
branch for the loop to be stranded behind, so the fault cannot occur:

```
	addk	r4,r5,r6        ; low word
	addk	r5,r3,r0
	addk	r3,r0,r5
	sra	r3,r5           ; high word, unrolled -- no loop, no branch
	sra	r3,r3
	...
```

So this is a GCC 12 bug, fixed or incidentally avoided somewhere in 13–17.
Kept here as a record of what the DejaGnu board found on its first run, and
because it is a useful worked example of the diagnosis, but there is nothing to
send upstream.

The general worry it raised is still worth checking on trunk, and is the open
item in #38: if the fault was a multi-instruction pattern being treated as
single-insn and put in a delay slot, shifts need not be the only victim.

Tracked as issue #38.
