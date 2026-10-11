#!/bin/sh
# run-corner.sh -- the corner-case evidence behind README.md, end to end.
#
#   TOOLCHAIN=<prefix>/bin QEMU=<qemu-build> ./run-corner.sh
#
# Host side: model the loop bit-exactly and report which of the states the
# review asks about each test stream reaches.  Target side: run the
# boundary-reaching pairs on both byte orders.
#
# The host part needs ../harness/vectors.h, which ../harness/run.sh generates.
set -e
: "${TOOLCHAIN:?set TOOLCHAIN to the directory holding microblaze-rtems7-gcc}"
: "${QEMU:?set QEMU to the directory holding qemu-system-microblaze[el]}"
here=$(cd "$(dirname "$0")" && pwd)
H=$here/../harness
PATH=$TOOLCHAIN:$PATH
CC=microblaze-rtems7-gcc

echo "== host model: what each test stream reaches =="
cc -O2 -o "$here/corner-model" "$here/corner-model.c" && "$here/corner-model"

if [ -f "$H/vectors.h" ]; then
  cc -O2 -I"$H" -o "$here/corner-over-vectors" "$here/corner-over-vectors.c"
  "$here/corner-over-vectors"
else
  echo "(skipping the 4701-vector pass: run ../harness/run.sh first)"
fi

echo "== exhaustive sweep of the only region that can reach R >= 2^63 =="
cc -O2 -o "$here/corner-exhaustive" "$here/corner-exhaustive.c"
( cd "$here" && ./corner-exhaustive )

echo "== the boundary-reaching pairs, on the target =="
cc -O2 -o "$here/corner-gen-vectors" "$here/corner-gen-vectors.c"
"$here/corner-gen-vectors" > "$here/vectors-corner.h"
sed 's|#include "vectors.h"|#include "vectors-corner.h"|' "$H/test.c" \
  > "$here/test-corner.c"
for e in be le; do
  E=""; [ $e = le ] && E="-mlittle-endian"
  $CC $E -O2 -ffreestanding -nostdlib -I"$here" -c "$here/test-corner.c" \
      -o "$here/tc-$e.o"
  $CC $E -ffreestanding -nostdlib -c "$H/start.S" -o "$here/s-$e.o"
  for v in stock fixed noquo; do
    src=$H/moddi3-$v.S
    $CC $E -O2 -ffreestanding -nostdlib -c "$src" -o "$here/m-$v-$e.o"
    $CC $E -ffreestanding -nostdlib -T "$H/link.ld" \
        "$here/s-$e.o" "$here/tc-$e.o" "$here/m-$v-$e.o" \
        -o "$here/corner-$v-$e.elf" -lgcc
  done
done
for e in be le; do
  Q=$QEMU/qemu-system-microblaze; [ "$e" = le ] && Q=${Q}el
  for v in stock fixed noquo; do
    printf '  %-3s %-6s ' $e $v
    timeout 200 "$Q" -M petalogix-s3adsp1800 -nographic \
        -kernel "$here/corner-$v-$e.elf" 2>/dev/null | tr -d '\r' \
      | grep -m1 RESULT || echo '(no RESULT: hang)'
  done
done
