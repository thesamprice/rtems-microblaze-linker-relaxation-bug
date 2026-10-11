# `__moddi3` on MicroBlaze — series, harness and measurements

Everything behind the two-patch gcc series for the broken 64-bit signed
modulo. Tracked as [issue #35](https://github.com/thesamprice/rtems-microblaze-linker-relaxation-bug/issues/35).

| | |
|---|---|
| [`patches/`](patches/) | the series, ready for `git send-email`. **Generated — do not hand-edit.** |
| [`messages/`](messages/) | the commit messages and cover letter the series is built from |
| [`make-series.sh`](make-series.sh) | regenerates `patches/` from `messages/` and `harness/moddi3-noquo.S` |
| [`tests/`](tests/) | `divmod-2.c`, the testsuite patch's payload |
| [`harness/`](harness/) | everything needed to reproduce the numbers |
| [`results/`](results/) | what the runs actually printed, 2026-09-27 |

## The series

Based on gcc master `8361264a1`. **`0001` and `0002` are alternatives — apply
one, not both.** Neither is a follow-on to the other; each applies to an
unpatched master.

| patch | what |
|---|---|
| `0001` | fix the assembly. Ramin Moussavi's fix plus my additions. **Recommended.** |
| `0002` | delete the assembly, use the generic C. The alternative. |

`0001` installs [`harness/moddi3-noquo.S`](harness/moddi3-noquo.S) — the
44-instruction version, with the quotient the function never returns taken
out. There is no separate top-level copy of it: that duplication cost an
afternoon's edits once, so `harness/` is the only place it lives.

Send to `gcc-patches@gcc.gnu.org`, CC Michael Eager `eager@eagercon.com`
(MicroBlaze maintainer) and Ramin Moussavi `lordrasmus@gmail.com`.

### Authorship

The assembly fix in `0001` is **Ramin Moussavi's**, carried in OpenADK as
`toolchain/gcc/patches/16.2.0/0010`. He agreed to its being submitted here, so
there is no longer a sign-off blocker. Both patches go out under Sam's
authorship and sign-off — the additions to `0001` are Sam's and Ramin is not
sending it himself — and `0001` credits him in its first paragraph. Revert to
`From: Ramin Moussavi` by editing the `commit` call for `$TMP/a` in
`make-series.sh` and the `Signed-off-by:` in `messages/0001.msg`.

### The testsuite patch

[`patches-test/`](patches-test/) holds one, generated from
[`tests/divmod-2.c`](tests/divmod-2.c) and deliberately **outside** the series
numbering: it tests the C semantics rather than either fix, applies to an
unpatched tree or on top of either patch, and is not MicroBlaze specific.

It exists because the boundary scan showed nothing in the tree reaches the
`2^63` partial remainder — the one state where the routine's signed
trial-subtraction test could have been wrong. Three operand pairs reach it;
see [`analysis/`](analysis/) and issue #37.

An earlier draft added a different test and dropped it, on finding
`arith-rand-ll.c` already catches the bug. That reasoning still holds for the
bug itself — `pr50865.c` and `arith-rand-ll.c` both catch it — and is why
`divmod-2.c` is pitched at the uncovered state instead.

## Regenerating the series

```sh
GCC_TREE=~/src/gcc GCC_BASE=8361264a1 ./make-series.sh
```

`0001` and `0002` are alternatives, so this is **not** a linear series and
`git format-patch --cover-letter` cannot be used: it would emit a diffstat for
applying both. The script commits each patch on the same base in its own
worktree, formats it with an explicit `--subject-prefix`, and writes the cover
letter from `messages/cover.txt`.

## Reproducing the numbers

```sh
cd harness
TOOLCHAIN=<rtems7-tools>/bin QEMU=<qemu-build> ./run.sh
```

`TOOLCHAIN` needs `microblaze-rtems7-gcc` **with its `le` multilib** — an RTEMS
7 tools install has it, and it is what makes little-endian testing possible
without building a second toolchain.

`QEMU` needs both `qemu-system-microblaze` and `qemu-system-microblazeel` from
the fork whose `petalogix-s3adsp1800` carries the exit-and-counter device at
`0xFF000000`. Without it the guest cannot exit and the instruction counts
cannot be taken. With `-icount 0` each instruction advances the virtual clock
by 1 ns, so the delta is an exact instruction count.

One trap worth keeping: that device is `DEVICE_LITTLE_ENDIAN`, so a big-endian
guest sees the 32-bit counter byte-swapped. Subtracting two swapped values is
meaningless — it first read as 973,879,040 instructions against little-endian's
3,607,610 for identical work. `bench.c` byte-swaps on big-endian.

### What the runs give

4701 vectors, machine `petalogix-s3adsp1800`, `-icount 0`:

| | instructions | be insns | le insns |
|---|---|---|---|
| stock `__moddi3` | 60 | hangs | hangs |
| Ramin's patch as sent | 56 | 3,607,673 | 3,607,610 |
| keeping the dead quotient | 55 | 3,605,340 | 3,605,277 |
| `0001` as sent here | 44 | 2,777,735 | 2,777,672 |
| generic C at `-O2` | 62 + 1030/1028 for `__udivmoddi4` | 3,995,016 | 3,988,505 |

Dropping the quotient is 23% of the executed instructions and 11 of the 55
instructions of code. It is only possible once the return value is fixed:
the original returned `r29:r30`, the quotient, by mistake.

Coverage, traced with the QEMU `libexeclog` plugin over the same 4701
vectors: 55 of 55 instructions and 17 of 18 conditional branch outcomes on
both byte orders, measured on the 55-instruction variant. The missing outcome
is the branch to the divide-by-zero label, which the vectors deliberately
exclude. Not re-measured on the 44-instruction version.

See [`analysis/`](analysis/) for the corner-case coverage of the signed
trial-subtraction test, which is the part `arith-rand-ll.c` does not reach.

## Files in `harness/`

| | |
|---|---|
| `gen.c` | host-side generator, 4701 vectors with expected values |
| `arith-rand-ll.c` | the existing upstream test, copied here so the A/B can be re-run |
| `moddi3-stock.S` | upstream `moddi3.S`, for the A side |
| `moddi3-noquo.S` | **what `0001` installs. The source of truth for the patch.** |
| `moddi3-fixed.S` | the same fix keeping the dead quotient, 55 instructions; kept only to measure what the quotient costs |
| `divdi3.S` | hand-written `__divdi3`; correct but loses on cycles, so not submitted |
| `cmoddi.c` | the generic `libgcc2.c` `__moddi3`, for the C comparison |
| `test.c` | 4701-vector checker, prints each failure |
| `bench.c` | instruction-count benchmark via the counter device |
| `hwdiv.c`, `dbz.c` | hardware-divide and divide-by-zero behaviour probes |
| `modsi3-extremes.c` | checks the 32-bit `divsi3.S`/`modsi3.S` at the same extremes; they are correct |
| `rt.c` | freestanding `abort`/`exit` so a gcc execute test can run bare-metal |
| `start.S`, `start2.S`, `link.ld` | bare-metal startup and memory map |

There are deliberately no copies of the assembly outside `harness/`. An
earlier layout kept reading copies at the top level and edits went into them
instead of the file the series installs.
