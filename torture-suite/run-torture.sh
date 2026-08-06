#!/bin/bash
# Build every gcc.c-torture/execute test as an RTEMS application, link it with
# both the pristine and the patched linker, note whether the executables differ,
# and run it under QEMU.
#
#   TORTURE=... BASE=... PAT=... CFLAGS_BSP="$(pkg-config --cflags ...)" \
#   LDFLAGS_BSP="$(pkg-config --libs ...)" QEMU=qemu-system-microblazeel \
#   ./run-torture.sh -O2 outdir
#
# The tests end in exit(0), so a pass is "[ RTEMS shutdown ]" without
# "*** EXIT STATUS NOT ZERO ***"; abort() produces the latter.
set -u
: "${TORTURE:?}" ; : "${BASE:?}" ; : "${PAT:?}"
: "${CFLAGS_BSP:?}" ; : "${LDFLAGS_BSP:?}"
: "${GCC:=microblaze-rtems7-gcc}"
: "${QEMU:=qemu-system-microblazeel}"
: "${QEMU_MACHINE:=petalogix-s3adsp1800}"
OPT="${1:--O2}"; OUT="${2:-out}"
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUT/work"
for f in pass fail noexe differ untested; do : > "$OUT/$f.txt"; done
$GCC $CFLAGS_BSP $OPT -w -c "$HERE/wrap.c" -o "$OUT/work/wrap.o" || exit 1

one () {
  local src=$1 n w log
  n=$(basename "$src" .c); w="$OUT/work/$n"
  $GCC $CFLAGS_BSP $OPT -w -Dmain=torture_main -c "$src" -o "$w.o" 2>/dev/null || {
      echo "$n" >> "$OUT/untested.txt"; return; }
  $GCC -B"$BASE/" $LDFLAGS_BSP "$OUT/work/wrap.o" "$w.o" -o "$w.base.exe" 2>/dev/null
  $GCC -B"$PAT/"  $LDFLAGS_BSP "$OUT/work/wrap.o" "$w.o" -o "$w.pat.exe"  2>/dev/null
  if [ ! -s "$w.base.exe" ] || [ ! -s "$w.pat.exe" ]; then
      echo "$n" >> "$OUT/noexe.txt"; rm -f "$w".*; return; fi
  cmp -s "$w.base.exe" "$w.pat.exe" || echo "$n" >> "$OUT/differ.txt"
  log="$OUT/work/$n.log"
  timeout 25 "$QEMU" -M "$QEMU_MACHINE" -m 256M -nographic -no-reboot \
      -kernel "$w.pat.exe" > "$log" 2>/dev/null
  if grep -q "EXIT STATUS NOT ZERO" "$log"; then echo "$n" >> "$OUT/fail.txt"
  elif grep -q "RTEMS shutdown" "$log"; then echo "$n" >> "$OUT/pass.txt"
  else echo "$n" >> "$OUT/fail.txt"; fi
  rm -f "$w".*.exe "$w.o" "$log"
}

n=0
for f in $(ls "$TORTURE/execute"/*.c | sort); do
  one "$f" & n=$((n+1)); [ $((n % 8)) -eq 0 ] && wait
done
wait
echo "pass=$(wc -l < "$OUT/pass.txt") fail=$(wc -l < "$OUT/fail.txt")" \
     "link-differ=$(wc -l < "$OUT/differ.txt") noexe=$(wc -l < "$OUT/noexe.txt")" \
     "untested=$(wc -l < "$OUT/untested.txt")"
