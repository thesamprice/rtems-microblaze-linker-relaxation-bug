#!/bin/sh
# one2.sh <endian> <moddi3-variant|libgcc> <test.c>
# Links the named __moddi3 ahead of libgcc so it wins, then runs the test.
e=$1; v=$2; src=$3
T=$(cd "$(dirname "$0")" && pwd)
b=$(basename "$src" .c)
: "${TOOLCHAIN:?set TOOLCHAIN to the directory holding microblaze-rtems7-gcc}"
: "${QEMU:?set QEMU to the directory holding qemu-system-microblaze[el]}"
PATH=$TOOLCHAIN:$PATH
CC=microblaze-rtems7-gcc
E=""; [ "$e" = le ] && E="-mlittle-endian"
Q=$QEMU/qemu-system-microblaze
[ "$e" = le ] && Q=${Q}el
o=$T/o/$e-$v-$b
MD=""; [ "$v" != libgcc ] && MD="$T/$e-md-$v.o"

if ! $CC $E -O2 -w -ffreestanding -nostdlib -c "$src" -o "$o.o" 2>"$o.cerr"; then
  if grep -q 'internal compiler error' "$o.cerr"; then echo "ICE $b"; else echo "CFAIL $b"; fi
  rm -f "$o.o" "$o.cerr"; exit 0
fi
if ! $CC $E -ffreestanding -nostdlib -T "$T/link3.ld" \
      "$T/$e-start3.o" "$o.o" $MD "$T/$e-rt2.o" -o "$o.elf" -lgcc 2>/dev/null; then
  echo "LFAIL $b"; rm -f "$o.o" "$o.elf" "$o.cerr"; exit 0
fi
out=$(timeout 15 "$Q" -M petalogix-s3adsp1800 -nographic -kernel "$o.elf" 2>/dev/null | tr -d '\r')
rm -f "$o.o" "$o.elf" "$o.cerr"
case "$out" in
  *TEST-PASS*)         echo "PASS $b" ;;
  *TEST-ABORT*)        echo "ABORT $b" ;;
  *TEST-EXIT-NONZERO*) echo "EXITNZ $b" ;;
  *)                   echo "TIMEOUT $b" ;;
esac
