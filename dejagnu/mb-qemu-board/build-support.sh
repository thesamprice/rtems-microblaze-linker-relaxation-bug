#!/bin/sh
# build-support.sh -- build the startup and runtime objects the board file
# links into every test.  Run once per toolchain; re-run if you change either
# source.  Produces obj/<be|le>/{crt0.o,runtime.o}.
#
#   CC=microblaze-rtems7-gcc ./build-support.sh
#
# Separate objects per byte order because the board links them into
# microblaze-elf and microblazeel-elf tests alike.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-microblaze-rtems7-gcc}
command -v "$CC" >/dev/null || { echo "$0: $CC not found; set CC" >&2; exit 1; }

for e in be le; do
  E=""; [ "$e" = le ] && E="-mlittle-endian"
  mkdir -p "$here/obj/$e"
  # The runtime is built -ffreestanding on purpose; the TESTS must not be.
  $CC $E -O2 -ffreestanding -c "$here/mb-qemu-crt0.S"    -o "$here/obj/$e/crt0.o"
  $CC $E -O2 -c "$here/mb-qemu-newlib.c" -o "$here/obj/$e/runtime.o"
  echo "built obj/$e/crt0.o obj/$e/runtime.o"
done
