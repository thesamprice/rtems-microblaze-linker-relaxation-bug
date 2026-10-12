# The MicroBlaze GDB simulator exists and works

The premise we were given on gcc-patches was that "the microblaze port doesn't
have a gdb simulator which is what is generally easiest to use with GCC". That
is not correct, and this directory is the evidence.

## It is in-tree and maintained

- `binutils-gdb/sim/microblaze/` — `interp.c`, `microblaze.isa` (107
  instructions), `microblaze-sim.h`, `local.mk`
- wired in `sim/configure.ac:114` — `[[microblaze*-*-*], [microblaze]]`
- and `gdb/configure.tgt:794` — `microblaze*-*-*) gdb_sim=microblaze`
- `sim/MAINTAINERS:29` names **Michael J. Eager** — the MicroBlaze maintainer
  we have already sent the moddi3 series to

## Building it took one configure and one make

```sh
mkdir bu-mbsim-build && cd bu-mbsim-build
../binutils-gdb/configure --target=microblaze-elf --enable-sim \
                          --disable-gdb --disable-werror --with-system-zlib
make all-sim -j4
# -> sim/microblaze/run
```

Note `run` is declared `noinst_PROGRAMS` in `sim/microblaze/local.mk`, so it is
never installed — it only exists in the build tree. That is exactly why
DejaGnu's `find_sim` searches a build tree for `sim/<cpu>/run` rather than
looking on `$PATH`.

The previous local build (`binutils-build`) had it off: it was configured
`--target=microblaze-linux-gnu --disable-gdb --disable-sim`.

## It satisfies DejaGnu's contract

`config/sim.exp`'s `sim_load` needs only: run `<sim> <elf>`, pass the program's
stdout through, and **exit with the guest's status**. All three hold.

**Exit status propagates exactly.** The sim's protocol is the code in `r3`
then `bri 0` (`MICROBLAZE_HALT_INST 0xb8000000`), per `interp.c` and the
`exit` macro in `sim/testsuite/microblaze/testutils.inc`. Using `mbx.s`:

| guest exits | `run` exits |
|---|---|
| 0 | 0 |
| 3 | 3 |
| 42 | 42 |

**Its own upstream testsuite passes:**

| test | result |
|---|---|
| `sim/testsuite/microblaze/pass.s` | prints `pass`, exits 0 |
| `sim/testsuite/microblaze/fail.s` | prints `fail`, exits 1 |

**Syscalls work.** `sc.s` issues `brki r14, 8` with the number in `r12` and
args in `r5`-`r8` (generic `CB_SYS_*` numbering — `CB_SYS_write` is 5) and the
output appears on stdout. So `write(1, ...)` works, which is all DejaGnu's
`testglue.c` status wrapper requires.

## Reproducing

```sh
# assembled with any microblaze binutils; this used microblaze-linux-gnu-as
microblaze-linux-gnu-as -o mbx.o mbx.s
microblaze-linux-gnu-ld -Ttext=0x100 -e _start -o mbx.elf mbx.o
<build>/sim/microblaze/run mbx.elf ; echo $?
```

`make all-sim` alone does not build gas/ld, so use an existing target
assembler or add `all-gas all-ld`.

## What this does not cover

The sim implements 107 instructions. Compared with the ~400 opcodes in
`opcodes/microblaze-opc.h` it is missing hard float (`fadd` etc.),
`mulh/mulhu/mulhsu`, `pcmp*`, `clz`, `swapb/swaph`, `bsefi/bsifi`, `mbar`,
`lwx/swx` and more.

That is survivable because GCC's MicroBlaze defaults are all soft —
`microblaze.opt` marks `msoft-float`, `mxl-soft-mul` and `mxl-soft-div` as the
defaults, and barrel-shift / pattern-compare / multiply-high are opt-in. So a
default-flags run only uses instructions the sim has. Tests built with
`-mhard-float`, `-mxl-multiply-high`, `-mxl-pattern-compare`, or RTEMS-style
multilibs will fail *at the simulator*, not in the compiler — which is where
the QEMU board remains necessary.

## The blocker: libgloss hands the sim the wrong register

The sim halts on `bri 0` and reports `RETREG`, which `microblaze.h:52` defines
as `CPU.regs[3]`. libgloss's `_exit` (`crt0.S`) is bare `bri 0`, while newlib
calls `_exit (code)` with the status in r5. The status never reaches r3.

`exit-status-asis.s` and `exit-status-patched.s` mimic the whole
`crtinit` → `exit()` → `_exit` sequence and differ only in the one `addik`:

```
run exit-status-asis.elf    ; echo $?   ->  0     (guest meant 42)
run exit-status-patched.elf ; echo $?   -> 42
```

Left alone, a sim board would call every execution test a pass. See
`../LIBGLOSS-BSP.md` for the reading behind this and the caveat that the
reproducer mimics newlib rather than linking it.
