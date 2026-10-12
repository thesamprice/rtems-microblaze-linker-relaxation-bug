#!/bin/sh
# build-support.sh -- build the startup and runtime objects the board links
# into every test, and record what the toolchain needs.  Run once per
# toolchain; re-run after changing either source.
#
#   CC=microblaze-elf-gcc ./build-support.sh
#   CC=./gcc17 MB_LDEXTRA=-L/path/to/libgcc ./build-support.sh
#
# What the runtime has to supply depends on the C library, so this probes
# rather than assumes:
#
#   no libc at all      a tiny freestanding runtime (MB_NO_LIBC).  An
#                       uninstalled trunk cross build looks like this: libgcc
#                       but no libc.  Tests needing real stdio will not link.
#   RTEMS newlib        newlib expects the kernel to supply malloc, the
#                       reentrancy pointer and the mutexes its stdio locks
#                       against, so those are compiled in.
#   vanilla newlib      only the syscall layer is needed.
#
# The result is written to obj/<be|le>/config.sh for the board file to read.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-microblaze-elf-gcc}
case "$CC" in /*|./*|../*) : ;; *) command -v "$CC" >/dev/null || { echo "$0: $CC not found; set CC" >&2; exit 1; } ;; esac

for e in be le; do
  E=""; [ "$e" = le ] && E="-mlittle-endian"
  o="$here/obj/$e"
  mkdir -p "$o"
  d=$(mktemp -d)

  # Is there a C library at all?
  printf 'int main(void){return 0;}\n' > "$d/c.c"
  if $CC $E $MB_LDEXTRA -nostartfiles -nostdlib "$d/c.c" -lc -lgcc \
        -o "$d/c.elf" > /dev/null 2>&1 \
     || $CC $E -print-file-name=libc.a 2>/dev/null | grep -q '/'; then
    haslibc=yes
  else
    haslibc=no
  fi

  $CC $E -O2 -ffreestanding -c "$here/mb-qemu-crt0.S" -o "$o/crt0.o"

  if [ "$haslibc" = no ]; then
    defs="-DMB_NO_LIBC"
    libs="-lgcc"
    # No libc headers either, so the ~5% of tests that include one would not
    # compile.  stub-include/ declares just enough; see its README.
    cflags="-isystem $here/stub-include"
    # GCC's driver appends -lc and its testsuite appends -lm whatever we do,
    # so satisfy them with empty archives.  Every real symbol comes from
    # runtime.o; these exist only so the link succeeds.
    : > "$d/empty.c"
    $CC $E -c "$d/empty.c" -o "$d/empty.o"
    for l in c m; do
      rm -f "$o/lib$l.a"
      "${AR:-$(echo "$CC" | sed 's/gcc$/ar/')}" rc "$o/lib$l.a" "$d/empty.o" \
        2>/dev/null || microblaze-linux-gnu-ar rc "$o/lib$l.a" "$d/empty.o"
    done
  else
    # This toolchain has a real libc, so any empty libc.a/libm.a left by an
    # earlier run against a libc-less one must go: the board puts -L$o ahead
    # of the toolchain's own directories, so a stale empty archive silently
    # wins over newlib and every test fails to link on __libc_init_array,
    # exit, memset and memcpy.
    rm -f "$o/libc.a" "$o/libm.a"
    # Probe what this newlib leaves to the board.
    cat > "$d/p.c" <<'PROBE'
#include <stdio.h>
#include <stdlib.h>
int main (void) { printf ("%d", 1); free (malloc (8)); return 0; }
PROBE
    $CC $E -O2 -c "$here/mb-qemu-newlib.c" -o "$d/rt.o" >/dev/null 2>&1
    $CC $E -O2 -c "$d/p.c" -o "$d/p.o" >/dev/null 2>&1
    u=$($CC $E $MB_LDEXTRA -nostartfiles -T "$here/mb-qemu.ld" "$o/crt0.o" \
          "$d/p.o" "$d/rt.o" -o "$d/p.elf" -lc -lgcc 2>&1 \
        | sed -n "s/.*undefined reference to \`\\([^']*\\)'.*/\\1/p" | sort -u)
    defs=""
    case "$u" in *malloc*)     defs="$defs -DMB_PROVIDE_MALLOC" ;; esac
    case "$u" in *__getreent*) defs="$defs -DMB_PROVIDE_REENT" ;; esac
    case "$u" in *_Mutex_*)    defs="$defs -DMB_PROVIDE_LOCKS" ;; esac
    libs="-lc -lgcc"
    cflags=""
  fi

  # Does this linker adjust a wrapped symbol's value twice when relaxing?
  #
  # DejaGnu's testglue.c defines __wrap_exit and calls exit, which puts the
  # one __wrap_exit hash entry in two elf_sym_hashes slots.  MicroBlaze
  # relaxation walks that array by index and subtracts the fixup once per
  # slot, so __wrap_exit ends up pointing before its own first instruction
  # and the status marker is never printed -- every execution test then
  # reports 2.  See ../../patches/binutils/0013-microblaze-relax-wrap-double-adjust.patch;
  # GCC's LINK_SPEC passes -relax unconditionally, so this is the default.
  #
  # The shape below reproduces it in eight instructions: a deleted IMM, then
  # a global defined after it, then a call to the wrapped name.  w_target is
  # 4 past w_before's last instruction, so if the two addresses come back
  # equal the linker has over-adjusted and relaxation has to be turned off.
  # w_fwd has to live in another section: within one section the assembler
  # resolves the branch itself and emits no IMM, so there is nothing to delete
  # and nothing to adjust.
  cat > "$d/w.s" <<'WRAP'
	.section .text.aaa_w,"ax",@progbits
	.globl	w_before
w_before:
	brlid	r15, w_fwd		/* IMM + BRLID; the IMM is deleted */
	nop
	addik	r1, r1, 28
	.globl	__wrap_w_target
__wrap_w_target:
	addik	r3, r0, 42
	rtsd	r15, 8
	nop
	.globl	w_calls
w_calls:
	brlid	r15, w_target
	nop

	.section .text.zz_w,"ax",@progbits
	.globl	w_fwd
w_fwd:
	rtsd	r15, 8
	nop
WRAP
  ldextra=""
  if $CC $E -c "$d/w.s" -o "$d/w.o" >/dev/null 2>&1 \
     && $CC $E $MB_LDEXTRA -nostartfiles -nostdlib -Wl,-relax \
             -Wl,--wrap,w_target -Wl,-e,w_before "$d/w.o" -o "$d/w.elf" \
             >/dev/null 2>&1; then
    nm=$(echo "$CC" | sed 's/gcc$/nm/')
    a=$($nm "$d/w.elf" 2>/dev/null | sed -n 's/^0*\([0-9a-f]*\) T __wrap_w_target$/\1/p')
    b=$($nm "$d/w.elf" 2>/dev/null | sed -n 's/^0*\([0-9a-f]*\) T w_calls$/\1/p')
    # Correct: __wrap_w_target is 12 bytes (3 instructions) before w_calls.
    if [ -n "$a" ] && [ -n "$b" ] \
       && [ $((0x$b - 0x$a)) -ne 12 ]; then
      ldextra="-Wl,--no-relax"
      echo "  note: $CC's linker mis-adjusts wrapped symbols when relaxing;" \
           "adding --no-relax so DejaGnu's status wrapper works"
    fi
  fi

  $CC $E -O2 $defs -c "$here/mb-qemu-newlib.c" -o "$o/runtime.o"
  { printf 'MB_LIBS="%s"\n' "$libs"
    printf 'MB_CFLAGS="%s"\n' "$cflags"
    printf 'MB_LDEXTRA_BOARD="%s"\n' "$ldextra"; } > "$o/config.sh"
  rm -rf "$d"
  echo "built obj/$e: libc=$haslibc libs=\"$libs\"${defs:+ defs:$defs}${ldextra:+ $ldextra}"
done
