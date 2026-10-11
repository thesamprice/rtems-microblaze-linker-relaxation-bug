#!/bin/sh
# scan.sh <endian> <test.c> -- link the instrumented __moddi3 and report whether
# the test calls it at all, and whether it reaches the 2^63 partial remainder.
e=$1; src=$2
T=$(cd "$(dirname "$0")" && pwd)
b=$(basename "$src" .c)
: "${TOOLCHAIN:?set TOOLCHAIN to the directory holding microblaze-rtems7-gcc}"
: "${QEMU:?set QEMU to the directory holding qemu-system-microblaze[el]}"
PATH=$TOOLCHAIN:$PATH
CC=microblaze-rtems7-gcc
E=""; [ "$e" = le ] && E="-mlittle-endian"
Q=$QEMU/qemu-system-microblaze
[ "$e" = le ] && Q=${Q}el
o=$T/o/s-$e-$b
OPTS=$(sed -E -n 's/.*dg-(additional-)?options//p' "$src" | tr -d '"{}' | tr ' ' '\n' \
       | grep '^-' | grep -v -F -- '-std=c++' | sort -u | tr '\n' ' ')
$CC $E -O2 -w $OPTS -ffreestanding -nostdlib -c "$src" -o "$o.o" 2>/dev/null || { echo "SKIP-CFAIL $b"; exit 0; }
# Does it reference __moddi3 at all?
if ! microblaze-rtems7-nm -u "$o.o" 2>/dev/null | grep -q '__moddi3'; then
  echo "NO-MODDI3 $b"; rm -f "$o.o"; exit 0
fi
$CC $E -ffreestanding -nostdlib -T "$T/link3.ld" "$T/$e-start3.o" "$o.o" \
    "$T/$e-md-instr.o" "$T/$e-rt2.o" -o "$o.elf" -lgcc 2>/dev/null || { echo "SKIP-LFAIL $b"; rm -f "$o.o"; exit 0; }
out=$(timeout 20 "$Q" -M petalogix-s3adsp1800 -nographic -kernel "$o.elf" 2>/dev/null | tr -d '\r')
rm -f "$o.o" "$o.elf"
case "$out" in
  *BOUNDARY-REACHED*) echo "REACHES-2^63 $b" ;;
  *)                  echo "CALLS-MODDI3 $b" ;;
esac
