#!/bin/sh
# Rebuild and re-run every measurement behind the moddi3 series.
#
#   TOOLCHAIN=<prefix>/bin QEMU=<qemu-build> ./run.sh
#
# TOOLCHAIN must hold microblaze-rtems7-gcc with its "le" multilib (an RTEMS 7
# tools install provides this).  QEMU must hold qemu-system-microblaze and
# qemu-system-microblazeel built from the fork whose petalogix-s3adsp1800 has
# the exit-and-counter device at 0xFF000000 -- without it the instruction
# counts cannot be taken and the guest cannot exit.
set -e
: "${TOOLCHAIN:?set TOOLCHAIN to the directory holding microblaze-rtems7-gcc}"
: "${QEMU:?set QEMU to the directory holding qemu-system-microblaze[el]}"
PATH=$TOOLCHAIN:$PATH
CC=microblaze-rtems7-gcc
F="-O2 -ffreestanding -nostdlib"

cc -O2 -o gen  gen.c      && ./gen  > vectors.h        # 4701 vectors, host-computed

for e in be le; do
  E=""; [ $e = le ] && E="-mlittle-endian"
  $CC $E $F -c rt.c    -o rt-$e.o
  $CC $E $F -c cmoddi.c -o c-$e.o
  $CC $E -ffreestanding -nostdlib -c start.S  -o s-$e.o
  $CC $E -ffreestanding -nostdlib -c start2.S -o s2-$e.o
  $CC $E $F -c arith-rand-ll.c -o fx-$e.o
  $CC $E $F -DMODFN=__moddi3 -c bench.c -o ba-$e.o
  $CC $E $F -DMODFN=c_moddi3 -c bench.c -o bc-$e.o
  $CC $E $F -c test.c -o t-$e.o
  for v in stock fixed; do
    $CC $E $F -c moddi3-$v.S -o m-$v-$e.o
    $CC $E -ffreestanding -nostdlib -T link.ld s-$e.o  t-$e.o  m-$v-$e.o -o vec-$v-$e.elf -lgcc
    $CC $E -ffreestanding -nostdlib -T link.ld s2-$e.o fx-$e.o rt-$e.o m-$v-$e.o -o arll-$v-$e.elf -lgcc
  done
  $CC $E -ffreestanding -nostdlib -T link.ld s-$e.o ba-$e.o m-fixed-$e.o -o bench-asm-$e.elf -lgcc
  $CC $E -ffreestanding -nostdlib -T link.ld s-$e.o bc-$e.o c-$e.o       -o bench-c-$e.elf   -lgcc
done

q () { e=$1; shift; Q=$QEMU/qemu-system-microblaze; [ "$e" = le ] && Q=${Q}el
       timeout 120 "$Q" -M petalogix-s3adsp1800 -nographic "$@" 2>/dev/null | tr -d '\r'; }

echo "== 4701-vector check (stock must hang, fixed must pass) =="
for e in be le; do for v in stock fixed; do
  printf '  %-3s %-6s ' $e $v
  q $e -kernel vec-$v-$e.elf | grep -m1 RESULT || echo '(no RESULT: hang)'
done; done

echo "== existing upstream test arith-rand-ll.c (stock must abort) =="
for e in be le; do for v in stock fixed; do
  printf '  %-3s %-6s ' $e $v
  q $e -kernel arll-$v-$e.elf | grep -m1 'TEST-' || echo '(no result: hang)'
done; done

echo "== executed instructions, -icount 0 (assembly vs generic C at -O2) =="
for e in be le; do for v in asm c; do
  printf '  %-3s %-4s ' $e $v
  q $e -icount 0 -kernel bench-$v-$e.elf | grep -m1 BENCH
done; done

echo "== static size =="
for e in be le; do
  printf '  %-3s asm __moddi3 ' $e
  microblaze-rtems7-objdump -d bench-asm-$e.elf | sed -n '/<__moddi3>:/,/^$/p' | grep -c '	'
  for s in c_moddi3 __udivmoddi4; do
    printf '  %-3s C %-13s ' $e $s
    microblaze-rtems7-objdump -d bench-c-$e.elf | sed -n "/<$s>:/,/^\$/p" | grep -c '	'
  done
done
