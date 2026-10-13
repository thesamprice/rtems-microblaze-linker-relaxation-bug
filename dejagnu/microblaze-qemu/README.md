# Running the GCC testsuite on MicroBlaze under QEMU

A DejaGnu board giving MicroBlaze **execution** testing — `gcc.c-torture/execute`
and friends actually running — rather than compile-only coverage.

It is shaped like DejaGnu's own `*-sim` boards. Everything a bare-metal target
needs comes from libgloss and newlib: the `crt0`, the linker script, the C
library and the syscall layer are the toolchain's. This directory adds two
things a simulator would not need:

- `qemu-run`, a wrapper that stops QEMU once the test has reported its status,
  because QEMU cannot hand a guest exit status back to the shell;
- `libxil.c`, forty lines driving the UART.

`libxil.c` is not a stub standing in for a real library. GCC's MicroBlaze
`LIB_SPEC` links `-lgloss -lxil -lc -lm`; libgloss supplies `-lgloss`, newlib
`-lc` and `-lm`, and `-lxil` is the **board's** library, which upstream builds
nothing for — in Xilinx's world it comes from the tools' board support
package. libgloss's `write()` and `read()` are loops over an `outbyte()` and
`inbyte()` that are declared and never defined. Supplying them is using the
interface as designed.

## What it needs

- `qemu-system-microblaze` or `-microblazeel`, **stock upstream**. No fork, no
  patches. Nothing is asked of the machine model but a UART, and
  `petalogix-s3adsp1800` is an upstream machine.
- A `microblaze-elf` toolchain built as a **combined tree**, so that libgloss
  and newlib are built alongside GCC. This is what DejaGnu's
  `libgloss_link_flags` and `newlib_link_flags` assume, and it is how every
  other `*-sim` board is used.
- DejaGnu (tested with 1.6.3).

## Building the toolchain

```sh
# binutils for the target, on PATH as microblaze-elf-as, -ld, -ar, -ranlib, -nm
git clone git://sourceware.org/git/binutils-gdb.git
mkdir bu-build && cd bu-build
../binutils-gdb/configure --target=microblaze-elf --enable-sim --disable-gdb
make && make install          # or put the build tree's tools on PATH
cd ..

# newlib and libgloss, symlinked into the gcc source tree: the combined tree
git clone --depth 1 --filter=blob:none --sparse \
    https://sourceware.org/git/newlib-cygwin.git
git -C newlib-cygwin sparse-checkout set newlib libgloss   # 73 MB
ln -sfn "$PWD/newlib-cygwin/newlib"   gcc/newlib
ln -sfn "$PWD/newlib-cygwin/libgloss" gcc/libgloss

mkdir mb-elf-build && cd mb-elf-build
../gcc/configure --target=microblaze-elf --prefix=<prefix> \
    --with-newlib --disable-multilib --disable-threads --disable-shared \
    --enable-languages=c \
    --disable-libssp --disable-libquadmath --disable-libgomp --disable-libatomic \
    --disable-nls --disable-werror --with-system-zlib
make -j8
```

`--disable-multilib` matters: `t-microblaze` otherwise builds ten copies of
newlib and the board uses one. The whole build is about 1.2 GB and produced no
errors here. On macOS add
`--with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew --with-mpc=/opt/homebrew
--with-isl=no`, and `--with-system-zlib` is not optional.

## Running it

```sh
# once per toolchain
CC=microblaze-elf-gcc ./setup.sh

# then, from the gcc build directory
export DEJAGNU=<a file containing: lappend boards_dir "<path to this dir>">
export MB_QEMU=<path to qemu-system-microblaze>
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu"
```

`setup.sh` builds `libxil.a` and probes the linker (see below). For
little-endian, point `MB_QEMU` at `qemu-system-microblazeel` and add
`/-mlittle-endian` to the board name. `MB_TIMEOUT` sets the per-test limit in
seconds, default 90.

One narrower run, useful first:

```sh
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp=pr50865.c"
```

## The memory map

`xilinx.ld`'s defaults are text at `0x50`, a 1 KiB stack and **no heap at
all**, which puts everything inside the 128 KiB of BRAM that
`petalogix-s3adsp1800` maps at 0 and leaves `malloc` failing immediately. All
three addresses are `DEFINED()`-guarded, so the board overrides them:

| symbol | default | board |
|---|---|---|
| `_TEXT_START_ADDR` | `0x50` | `0x90000000` (the RAM) |
| `_STACK_SIZE` | `0x400` | `0x400000` |
| `_HEAP_SIZE` | `0x0` | `0x400000` |

The vectors stay at 0 in BRAM, which is where the core resets to. Megabytes of
stack are not generosity: `pr28982b` and `memcpy-1` hang on less.

## The relaxation workaround

The board sets `needs_status_wrapper`, so GCC links DejaGnu's `testglue.c`,
which wraps `exit`/`_exit`/`abort`/`main` and writes `*** EXIT code N` through
`write(1, ...)`; `check_for_board_status` in DejaGnu's `remote.exp` parses it.

`testglue.c` defines `__wrap_exit` and calls `exit`, which puts one hash entry
in two `elf_sym_hashes` slots. MicroBlaze relaxation walks that array by index
and subtracts the fixup once per slot, so `__wrap_exit` resolves before its own
first instruction, no status line is written, and **every execution test is
reported as status 2**. GCC's `LINK_SPEC` passes `-relax` unconditionally, so
this is the default. The fix is
[`../../patches/binutils-relax/`](../../patches/binutils-relax/).

Until it lands, `setup.sh` probes for the defect and records `--no-relax` in
`config.sh`. Two consequences:

- **It expires on its own.** The probe links an eight-instruction case and
  checks one symbol's address. Against a linker carrying the fix it matches
  nothing and records nothing, so a toolchain built afterwards gets relaxation
  back with no edit here.
- **While it is on, the suite does not exercise relaxation at all.** That costs
  little for testing the compiler — relaxation is a linker transformation and
  the object files are identical either way — but a run cannot catch a
  relaxation bug while the flag is in force.

## What this does not cover

The GDB simulator (`sim/microblaze/run`, built by `--enable-sim` above) is the
cheaper runner and is what most targets use, but it implements 107
instructions: no hard float, `mulh*`, `pcmp*`, `clz`, `swapb/swaph` or
`lwx/swx`. `lwx/swx` are emitted at the **default** `-mcpu`, because
`gcc/config/microblaze/sync.md` gives all three of its atomic patterns the
condition `""`, so atomics fault there. QEMU system emulation is what covers
the full ISA. See [`../sim-evidence/`](../sim-evidence/) for the simulator's
measurements and [`../LIBGLOSS-BSP.md`](../LIBGLOSS-BSP.md) for how libgloss's
BSP was read.
