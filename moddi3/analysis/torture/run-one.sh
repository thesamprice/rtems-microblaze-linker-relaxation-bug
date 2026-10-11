#!/bin/sh
# run-one.sh <endian> <libgcc|noquo|stock> <test.c>
#
# Compile, link and run one gcc.c-torture/execute test bare-metal, with the
# named __moddi3 linked ahead of libgcc so it wins.  Prints "<STATUS> <name>".
#
# Three things here were learned the hard way and must not be undone:
#
#   - The test is compiled HOSTED, not -ffreestanding.  Under -ffreestanding
#     main is an ordinary function, so GCC stops emitting the C99 implicit
#     "return 0" on fallthrough -- and most of these tests fall off the end of
#     main.  The return register then holds the last computed value and every
#     such test looks like a failure.  That alone accounted for 13 of them.
#   - The stack is 4MB (link3.ld).  At 256KB, pr28982b and memcpy-1 hang.
#   - The test's own dg-options are honoured.  Without them, nine tests
#     wanting -fwrapv and one wanting -finstrument-functions fail by design.
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

if ! $CC $E -O2 -w $OPTS -nostdlib -c "$src" -o "$o.o" 2>"$o.cerr"; then
  if grep -q 'internal compiler error' "$o.cerr"; then echo "ICE $b [$OPTS]"
  else echo "CFAIL $b [$OPTS]"; fi
  rm -f "$o.o" "$o.cerr"; exit 0
fi
if ! $CC $E -ffreestanding -nostdlib -T "$T/link3.ld" \
      "$T/$e-start3.o" "$o.o" $MD "$T/$e-rt2.o" -o "$o.elf" -lgcc 2>/dev/null; then
  echo "LFAIL $b [$OPTS]"; rm -f "$o.o" "$o.elf" "$o.cerr"; exit 0
fi
out=$(timeout 120 "$Q" -M petalogix-s3adsp1800 -nographic -kernel "$o.elf" 2>/dev/null | tr -d '\r')
rm -f "$o.o" "$o.elf" "$o.cerr"
case "$out" in
  *TEST-PASS*)         echo "PASS $b [$OPTS]" ;;
  *TEST-ABORT*)        echo "ABORT $b [$OPTS]" ;;
  *TEST-EXIT-NONZERO*) echo "EXITNZ $b [$OPTS]" ;;
  *)                   echo "TIMEOUT $b [$OPTS]" ;;
esac
