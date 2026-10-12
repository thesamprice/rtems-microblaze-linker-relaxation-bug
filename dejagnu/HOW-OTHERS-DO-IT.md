# How other targets do bare-metal GCC testing, and what that means here

Written after building a board from scratch and then looking at how the
established targets actually do it. Short version: **this board reinvented
most of what libgloss already provides, and libgloss supports MicroBlaze.**

## The standard recipe

Every `*-sim` board DejaGnu ships is the same four lines. `arm-sim.exp`,
`riscv-sim.exp`, `aarch64-sim.exp`, `cris-sim.exp`, `frv-sim.exp`,
`iq2000-sim.exp` — all of them:

```tcl
set_board_info cflags   "[libgloss_include_flags] [newlib_include_flags]"
set_board_info ldflags  "[libgloss_link_flags] [newlib_link_flags]"
set_board_info ldscript ""
```

Note `ldscript ""` — they do not supply a linker script. libgloss does.

Those four procs live in DejaGnu's `libgloss.exp` and work by **looking inside
the build tree**:

- `newlib_link_flags` wants `<multilib build dir>/newlib`
- `libgloss_link_flags` wants `<multilib build dir>/libgloss/$target_cpu`
  and the matching `libgloss/$cpu` source directory

So the assumed setup is a **combined tree**: gcc, newlib and libgloss
configured and built together, `--target=<cpu>-elf --with-newlib`. Then the
testsuite finds the freshly built libc and BSP by itself. No stub headers, no
hand-written crt0, no hand-written linker script, no empty archives.

## libgloss supports MicroBlaze

From `libgloss/configure.ac` upstream:

```
  microblaze*-*-*)
	config_microblaze=true
	;;
```

and `microblaze` is in the subdirectory list beside `arm`, `riscv`, `nios2`.
`libgloss/microblaze/` contains `crt0.S` through `crt4.S`, `crtinit.S`,
`sim-crtinit.S`, a `xilinx.ld` linker script, `sbrk.c` and `timer.c`.
Contributed by Xilinx. The syscall stubs it is built from — `fstat.c`,
`getpid.c`, `isatty.c`, `lseek.c`, `print.c` and the rest — are libgloss's
**top-level**, target-independent files, not MicroBlaze ones.

That matters: there is a `sim-crtinit.S`, and `crt0.S`'s `_exit` is the
simulator's halt instruction, so the BSP anticipates a simulator.

`LIBGLOSS-BSP.md` reads the BSP in full: what its I/O model is, which
addresses are parameterisable, and the one bug that stops it reporting exit
status on the simulator.

## So why does MicroBlaze get compile-only testing?

Not for want of libgloss. The missing half is the **runner**. Every one of
those boards gets its execution from a GDB simulator — `setup_sim` in
`basic-sim.exp` goes looking for `sim/<cpu>/run`.

**The premise that MicroBlaze has no GDB simulator is wrong.** It has one,
`binutils-gdb/sim/microblaze/`, maintained by the MicroBlaze maintainer, and
it builds and propagates exit status. `sim-evidence/README.md` records the
build and the measurements. So this section's original conclusion — that the
runner is the whole gap — was itself based on the claim it was repeating.

What is actually missing is narrower:

| piece | status |
|---|---|
| crt0, syscalls, linker script, libc | **libgloss + newlib already do this** |
| a simulator to run the binary | **exists**, unbuilt by default and widely assumed absent |
| libgloss reporting the exit status to it | **broken** — `_exit` leaves the status in r5, the sim reads r3 |
| full-ISA execution (hard FP, `mulh*`, `clz`, ...) | the sim lacks these; this is where QEMU earns its place |

## What this board should be

`mb-qemu-run` and the `sim_load` override are the parts worth keeping: they
turn `qemu-system-microblaze` into something DejaGnu can drive, which is the
piece nobody has. Everything else here — `mb-qemu-crt0.S`, `mb-qemu.ld`,
`mb-qemu-newlib.c`, `stub-include/`, the empty `libc.a`/`libm.a` — exists only
because this was built against a toolchain that had no libc, and should be
replaced by the standard four lines once a combined tree exists.

Target shape:

```tcl
load_generic_config "sim"
process_multilib_options ""
load_base_board_description "basic-sim"

set_board_info compiler  "[find_gcc]"
set_board_info cflags    "[libgloss_include_flags] [newlib_include_flags]"
set_board_info ldflags   "[libgloss_link_flags] [newlib_link_flags]"
set_board_info ldscript  ""
set_board_info sim       "$mb_dir/mb-qemu-run"
set_board_info sim_time_limit 120
# plus the sim_load override, because generic sim_load loses the exit status
```

That is a board file a GCC maintainer would recognise, and it is far more
likely to be accepted than one carrying its own BSP.

## What it costs

The libgloss half of this no longer needs a build to investigate: a blobless
sparse clone of newlib is 7.6 MB over the git protocol, and
`LIBGLOSS-BSP.md` is the result. What still costs real time is building it.

A combined-tree build of `microblaze-elf`: fetch newlib (~200MB), symlink
`newlib` and `libgloss` into the gcc source tree, configure
`--target=microblaze-elf --with-newlib --disable-threads`, build. Hours, not
minutes, and it wants several GB.

Until then the current board works and has produced real results — 1633/1685
on the RTEMS 12.4.1 toolchain — but it is scaffolding, not the thing to send.

## The honest status of the trunk attempt

Trying to point this board at a trunk `microblaze-linux-gnu` build that was
configured `--without-headers` produced a chain of workarounds: patch
`gthr-default.h` to single-thread so libgcc builds, patch `collect-ld` so gcc
can find the linker, stub headers so tests that include `<string.h>` compile,
empty `libc.a`/`libm.a` so `-lc`/`-lm` resolve. Each worked; together they are
a sign of pushing against the grain rather than a setup anyone should copy.

The useful trunk results were obtained without the board at all, by linking
directly: trunk's `libgcc.a` ships the broken 60-instruction `moddi3.o`, the
4701-vector check fails with it and passes with the fix. See `../moddi3/`.
