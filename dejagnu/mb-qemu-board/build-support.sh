#!/bin/sh
# build-support.sh -- build the startup and runtime objects the board links
# into every test.  Run once per toolchain.
#
#   CC=microblaze-elf-gcc ./build-support.sh
#   CC=microblaze-rtems7-gcc ./build-support.sh
#
# Which pieces of the runtime are needed depends on the C library, so this
# probes rather than assumes.  A vanilla newlib brings its own malloc and
# __getreent and needs only the syscalls; an RTEMS newlib expects the kernel to
# supply malloc, the reentrancy pointer and the mutex primitives its stdio
# locks against, so those get compiled in.  Defining them unconditionally
# would collide with a vanilla newlib.
set -e
here=$(cd "$(dirname "$0")" && pwd)
CC=${CC:-microblaze-elf-gcc}
command -v "$CC" >/dev/null || { echo "$0: $CC not found; set CC" >&2; exit 1; }

probe () {           # probe <endian-flag> -> echoes the -D flags needed
  d=$(mktemp -d); trap 'rm -rf "$d"' RETURN 2>/dev/null || :
  cat > "$d/probe.c" <<'PROBE'
#include <stdio.h>
#include <stdlib.h>
int main (void) { printf ("%d", 1); free (malloc (8)); return 0; }
PROBE
  defs=""
  # Link the probe with only the unconditional part of the runtime and see
  # what the C library still wants.
  "$CC" $1 -O2 -c "$here/mb-qemu-newlib.c" -o "$d/rt.o" >/dev/null 2>&1
  "$CC" $1 -O2 -c "$d/probe.c" -o "$d/probe.o" >/dev/null 2>&1
  u=$("$CC" $1 -nostartfiles -T "$here/mb-qemu.ld" "$here/obj/$2/crt0.o" \
        "$d/probe.o" "$d/rt.o" -o "$d/probe.elf" -lc -lgcc 2>&1 \
      | sed -n "s/.*undefined reference to \`\\([^']*\\)'.*/\\1/p" | sort -u)
  case "$u" in *malloc*)     defs="$defs -DMB_PROVIDE_MALLOC" ;; esac
  case "$u" in *__getreent*) defs="$defs -DMB_PROVIDE_REENT" ;; esac
  case "$u" in *_Mutex_*)    defs="$defs -DMB_PROVIDE_LOCKS" ;; esac
  echo "$defs"
}

for e in be le; do
  E=""; [ "$e" = le ] && E="-mlittle-endian"
  mkdir -p "$here/obj/$e"
  # Startup first: the probe link needs it.  -ffreestanding is right for the
  # runtime and startup; it must NOT be used for the tests themselves.
  $CC $E -O2 -ffreestanding -c "$here/mb-qemu-crt0.S" -o "$here/obj/$e/crt0.o"
  defs=$(probe "$E" "$e")
  $CC $E -O2 $defs -c "$here/mb-qemu-newlib.c" -o "$here/obj/$e/runtime.o"
  echo "built obj/$e: crt0.o runtime.o${defs:+ (libc needs:$defs)}"
done
