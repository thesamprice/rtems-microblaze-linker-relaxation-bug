#!/bin/bash
# Assemble every gcc.c-torture/compile source twice -- pristine vs patched
# binutils -- and compare the objects.  Same compiler both times, so any
# difference is attributable to the binutils change.
#
#   TORTURE=/path/to/gcc.c-torture BASE=/path/to/base PAT=/path/to/pat \
#   GCC=microblaze-rtems7-gcc CFLAGS_BSP="..." ./compile-diff.sh -O2 outdir
set -u
: "${TORTURE:?set TORTURE to the gcc.c-torture directory}"
: "${BASE:?set BASE to a directory containing pristine as/ld symlinks}"
: "${PAT:?set PAT to a directory containing patched as/ld symlinks}"
: "${GCC:=microblaze-rtems7-gcc}"
: "${CFLAGS_BSP:=}"
OPT="${1:--O2}"; OUT="${2:-out}"
mkdir -p "$OUT"; : > "$OUT/differ.txt"; : > "$OUT/failed.txt"; : > "$OUT/ok.txt"

one () {
  local src=$1 n a b
  n=$(basename "$src" .c); a="$OUT/$n.base.o"; b="$OUT/$n.pat.o"
  $GCC -B"$BASE/" $CFLAGS_BSP $OPT -w -c "$src" -o "$a" 2>/dev/null || {
      echo "$n" >> "$OUT/failed.txt"; rm -f "$a" "$b"; return; }
  $GCC -B"$PAT/"  $CFLAGS_BSP $OPT -w -c "$src" -o "$b" 2>/dev/null || {
      echo "$n" >> "$OUT/failed.txt"; rm -f "$a" "$b"; return; }
  if cmp -s "$a" "$b"; then echo "$n" >> "$OUT/ok.txt"
  else echo "$n" >> "$OUT/differ.txt"; fi
  rm -f "$a" "$b"
}

n=0
for f in $(ls "$TORTURE/compile"/*.c | sort); do
  one "$f" & n=$((n+1)); [ $((n % 8)) -eq 0 ] && wait
done
wait
echo "identical: $(wc -l < "$OUT/ok.txt")  differ: $(wc -l < "$OUT/differ.txt")  did-not-compile: $(wc -l < "$OUT/failed.txt")"
