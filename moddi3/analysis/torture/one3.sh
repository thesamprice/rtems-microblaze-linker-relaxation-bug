#!/bin/sh
# one3.sh <endian> <variant> <test.c> -- as one2.sh, but honours the test's
# own dg-options / dg-additional-options, which the plain runner ignored.
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
o=$T/o/x-$e-$v-$b
MD=""; [ "$v" != libgcc ] && MD="$T/$e-md-$v.o"
# Pull every -flag out of the dg-options lines.
OPTS=$(sed -E -n 's/.*dg-(additional-)?options//p' "$src" | tr -d '"{}' | tr ' ' '\n' \
       | grep '^-' | grep -v -F -- '-std=c++' | sort -u | tr '\n' ' ')

if ! $CC $E -O2 -w $OPTS -ffreestanding -nostdlib -c "$src" -o "$o.o" 2>"$o.cerr"; then
  if grep -q 'internal compiler error' "$o.cerr"; then echo "ICE $b [$OPTS]"
  else echo "CFAIL $b [$OPTS]"; fi
  rm -f "$o.o" "$o.cerr"; exit 0
fi
if ! $CC $E -ffreestanding -nostdlib -T "$T/link3.ld" \
      "$T/$e-start3.o" "$o.o" $MD "$T/$e-rt2.o" -o "$o.elf" -lgcc 2>/dev/null; then
  echo "LFAIL $b [$OPTS]"; rm -f "$o.o" "$o.elf" "$o.cerr"; exit 0
fi
out=$(timeout 25 "$Q" -M petalogix-s3adsp1800 -nographic -kernel "$o.elf" 2>/dev/null | tr -d '\r')
rm -f "$o.o" "$o.elf" "$o.cerr"
case "$out" in
  *TEST-PASS*)         echo "PASS $b [$OPTS]" ;;
  *TEST-ABORT*)        echo "ABORT $b [$OPTS]" ;;
  *TEST-EXIT-NONZERO*) echo "EXITNZ $b [$OPTS]" ;;
  *)                   echo "TIMEOUT $b [$OPTS]" ;;
esac
