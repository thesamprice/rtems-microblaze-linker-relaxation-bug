# What libgloss's MicroBlaze BSP actually is

The question this answers: our own `mb-qemu-board/` carries a hand-written
BSP (crt0, linker script, syscall stubs). `HOW-OTHERS-DO-IT.md` concluded that
every other `*-sim` board instead uses libgloss via DejaGnu's
`libgloss_include_flags` / `libgloss_link_flags`, and that ours had reinvented
it. Before paying for a combined-tree build, the condition set was: only do it
if `libgloss/microblaze` actually works under QEMU.

**It does, and it is the right basis for both the simulator and the QEMU
path — with one upstream bug in the way.**

## How this was read

sourceware's gitweb is Anubis-blocked for `a=tree` and `a=snapshot` (HTTP
403), but `a=blob_plain` is not, and the **git smart protocol is not blocked
at all**. A blobless sparse clone is 7.6 MB and gives a real tree:

```sh
git clone --depth 1 --filter=blob:none --sparse \
    https://sourceware.org/git/newlib-cygwin.git
git -C newlib-cygwin sparse-checkout set libgloss/microblaze
```

Note that `libgloss/microblaze/Makefile.inc` lists sources both with and
without a `%D%/` prefix. The unprefixed ones (`read.c`, `write.c`, `open.c`,
`print.c`, `putnum.c`, ...) are libgloss's **top-level** files, shared across
targets. Guessing `libgloss/microblaze/write.c` gets a 404; that is why.

## The I/O model is a UART, not the simulator's syscalls

`libgloss/write.c` is the whole of `write` for this target:

```c
  for (i = 0; i < nbytes; i++) {
    if (*(buf + i) == '\n')
      outbyte ('\r');
    outbyte (*(buf + i));
  }
```

and `read.c` is the matching `inbyte()` loop. There is **no** `brki r14, 8`
syscall anywhere in the bare-metal BSP — the only `brki` in the directory is
`crt1.S:100`, `brki r16, 0x4`, a hook into XMDSTUB (Xilinx's JTAG debug
monitor), unrelated to the GDB simulator.

So the BSP does not target the simulator's ABI, and it does not target a
specific UART either:

- `outbyte` and `inbyte` are **never defined** for bare metal. They appear
  only as `extern void outbyte (char);` in `xil_printf.c`.
- `linux-outbyte.c` and `linux-inbyte.c` exist but are in
  `libgloss_linux_a_SOURCES`, i.e. `libgloss-linux.a`, not `libgloss.a`.

The BSP is therefore **board-agnostic and deliberately incomplete**: whoever
uses it supplies one function. For our QEMU machine that is

```c
void outbyte (unsigned char c) { *(volatile unsigned char *)0x84000000 = c; }
```

which is what `mb-qemu-newlib.c` already does. That answers the condition:
libgloss is parameterisable to the QEMU map, so prefer it for both paths.

## The memory map is parameterisable

`xilinx.ld` guards every address with `DEFINED()`, so all three are
`--defsym`-overridable:

| symbol | default | note |
|---|---|---|
| `_TEXT_START_ADDR` | `0x50` | text start; vectors sit below it |
| `_HEAP_SIZE` | `0x0` | **zero** — `malloc` fails until this is set |
| `_STACK_SIZE` | `0x400` | 1 KiB; the torture suite needs ~4 MiB |

The vectors are fixed at `0x0`, `0x8`, `0x10`, `0x18`, `0x20`, which suits
both targets: the GDB sim has 8 MB from address 0, and QEMU's
`petalogix-s3adsp1800` has BRAM at `0x0` and resets there. For QEMU, text can
move to the `0x90000000` RAM with `--defsym _TEXT_START_ADDR=0x90000000`
while the vectors stay in BRAM.

`sbrk.c` bounds the heap on `_heap_end`, so `_HEAP_SIZE` defaulting to 0 is a
hard stop rather than a slow failure. Two of the four traps in
`../moddi3/analysis/torture/run-one.sh` (stack size, heap) are therefore
`--defsym` arguments here, not code.

`sim-crtinit.S` differs from `crtinit.S` in exactly one respect — it omits the
`.bss`/`.sbss` zeroing loops, on the assumption that a simulator hands over
zeroed memory. Nothing about it is sim-ABI-specific. Use plain `crtinit.o`
unless that assumption has been checked for the target.

## The bug: libgloss's `_exit` discards the exit status

`crt0.S` ends with

```asm
_exit:
        bri     0
```

`bri 0` branches to itself. The GDB simulator special-cases the whole
instruction word (`interp.c:164`, `inst == MICROBLAZE_HALT_INST`) and halts
with `sim_exited, RETREG`, where `microblaze.h:52` defines
`#define RETREG CPU.regs[3]` — register **r3**.

But newlib's `exit` (`newlib/libc/stdlib/exit.c`) ends `_exit (code)`, so the
status arrives in **r5**, the first argument register, and `_exit` never moves
it to r3. r3 holds whatever `__call_exitprocs` or `__stdio_exit_handler` left
behind.

Measured against the built simulator, mimicking the exact
`crtinit` → `exit()` → `_exit` sequence in assembly
(`sim-evidence/exit-status-{asis,patched}.s`):

| `_exit` body | guest intended | `sim/microblaze/run` exits |
|---|---|---|
| `bri 0` (as shipped) | 42 | **0** |
| `addik r3, r5, 0` ; `bri 0` | 42 | **42** |

**A DejaGnu sim board built on stock libgloss would report every execution
test as a pass**, including the ones that fail. That is worse than the
compile-only testing it would replace, and it may well be why MicroBlaze
execution testing was written off. The fix is the one `addik` above.

Caveat, stated plainly: the reproducer mimics newlib's `exit()` in assembly
rather than linking real newlib, because no combined tree has been built yet.
The particular value observed (0) is incidental — it is whatever the last
callee left in r3. The fact being demonstrated is the missing `r5` → `r3`
move, which is visible in the source and independent of the test. Confirm it
against real newlib once a combined tree exists.

On QEMU the same instruction is just an infinite self-branch, which is
consistent with what `mb-qemu-run` already handles by killing QEMU externally
after the status marker appears.

## Consequences for the two board files

- **Simulator path.** libgloss is the right basis, and `xilinx.ld`'s defaults
  already fit the sim's 8 MB. It needs an `outbyte` that issues the sim's
  `write` syscall (`brki r14, 8`, number in r12), plus the `_exit` fix or a
  board-supplied `_exit` that overrides it.
- **QEMU path.** libgloss can replace most of our BSP: keep `outbyte` and the
  three `--defsym` values, drop our crt0 and linker script in favour of
  `crt0.o` + `crtinit.o` + `xilinx.ld`. That is a real reduction, and it makes
  the board look like every other `*-sim` board.
