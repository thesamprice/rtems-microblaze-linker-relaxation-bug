#!/bin/sh
# setup.sh -- build the one library this board adds to the toolchain, and
# record whether the toolchain's linker needs a workaround.  Run once per
# toolchain.
#
#   CC=microblaze-elf-gcc ./setup.sh
#   CC="<obj>/gcc/xgcc -B<obj>/gcc/" AR=... NM=... ./setup.sh
#
# For an uninstalled build tree CC may carry -B options and so cannot be
# rewritten into a tool name; set AR and NM explicitly in that case.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-microblaze-elf-gcc}
AR=${AR:-$(echo "$CC" | sed 's/gcc$/ar/')}
NM=${NM:-$(echo "$CC" | sed 's/gcc$/nm/')}

# --- libxil.a ---------------------------------------------------------------
# GCC's MicroBlaze LIB_SPEC (gcc/config/microblaze/microblaze.h:879) links
# "-lgloss -lxil -lc -lm".  libgloss and newlib supply three of those; -lxil
# is the board's own library and upstream builds nothing for it.  See
# libxil.c.
$CC -O2 -ffreestanding -c "$here/libxil.c" -o "$here/libxil.o"
rm -f "$here/libxil.a"
$AR rc "$here/libxil.a" "$here/libxil.o"
echo "libxil.a: $($NM "$here/libxil.a" | grep -c ' T ') symbols"

# --- does this linker need --no-relax? --------------------------------------
# DejaGnu's testglue.c defines __wrap_exit and calls exit, which puts one
# hash entry in two elf_sym_hashes slots.  MicroBlaze relaxation walks that
# array by index and subtracts the fixup once per slot, so __wrap_exit ends
# up pointing before its own first instruction, the status line is never
# written, and every execution test reports 2.  GCC's LINK_SPEC passes -relax
# unconditionally, so this is the default.
#
# TODO: delete this probe once ../../patches/binutils-relax/0001-*.patch is in
# the toolchains being tested.  Nothing needs editing when that happens -- the
# probe stops matching and stops adding the flag by itself -- but the dead
# code should go, and with it the note in ../README.md.
#
# w_fwd has to live in another section: within one section the assembler
# resolves the branch itself and emits no IMM, so there is nothing to delete
# and nothing to adjust.  __wrap_w_target must come out 12 bytes before
# w_calls; a linker that over-adjusts puts it 16 before.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
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
# An explicit -T, which also suppresses LINK_SPEC's "%{!T*: -dT xilinx.ld%s}".
# Without it the probe needs libgloss's script on a -L path, and -nostdlib
# means there is none.
cat > "$d/w.ld" <<'WLD'
ENTRY(w_before)
SECTIONS
{
  . = 0x90000000;
  .text : { *(.text.aaa_w) *(.text.zz_w) }
  /DISCARD/ : { *(.comment) *(.note*) }
}
WLD
no_relax=""
if $CC -c "$d/w.s" -o "$d/w.o" >/dev/null 2>&1 \
   && $CC -nostartfiles -nostdlib -T "$d/w.ld" -Wl,-relax \
          -Wl,--wrap,w_target "$d/w.o" -o "$d/w.elf" >/dev/null 2>&1; then
  a=$($NM "$d/w.elf" 2>/dev/null | sed -n 's/^0*\([0-9a-f]*\) T __wrap_w_target$/\1/p')
  b=$($NM "$d/w.elf" 2>/dev/null | sed -n 's/^0*\([0-9a-f]*\) T w_calls$/\1/p')
  if [ -n "$a" ] && [ -n "$b" ] && [ $((0x$b - 0x$a)) -ne 12 ]; then
    no_relax="-Wl,--no-relax"
    echo "note: this linker mis-adjusts wrapped symbols when relaxing;"
    echo "      adding --no-relax so DejaGnu's status wrapper works."
    echo "      While that is on, the suite does not exercise relaxation"
    echo "      at all -- see ../README.md."
  else
    echo "linker adjusts wrapped symbols correctly; relaxation left enabled"
  fi
else
  echo "warning: could not run the relaxation probe; leaving relaxation enabled" >&2
fi

printf 'MB_NO_RELAX="%s"\n' "$no_relax" > "$here/config.sh"
echo "wrote config.sh"
