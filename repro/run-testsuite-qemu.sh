#!/bin/bash
B=$1; OUT=$2; J=${3:-4}; TMO=${4:-20}
# Xilinx QEMU fork; upstream qemu-system-microblazeel works too.
Q=${QEMU_MICROBLAZE:?set QEMU_MICROBLAZE to a qemu-system-microblazeel binary}
mkdir -p "$OUT/logs"; : > "$OUT/results.txt"
one() {
  local exe=$1 n log v
  n=$(basename "$exe" .exe); log="$OUT/logs/$n.log"; rm -f "$log"
  timeout "$TMO" "$Q" -M petalogix-s3adsp1800 -m 256M -nographic -no-reboot \
     -serial file:"$log" -kernel "$exe" >/dev/null 2>&1
  if   grep -q "TEST STATE: EXPECTED_FAIL" "$log" 2>/dev/null; then v=XFAIL
  elif grep -q "TEST STATE: USER_INPUT" "$log" 2>/dev/null; then v=SKIP
  elif grep -q "TEST STATE: BENCHMARK" "$log" 2>/dev/null; then v=SKIP
  elif grep -q "END OF TEST" "$log" 2>/dev/null; then v=PASS
  elif [ ! -s "$log" ]; then v=NO-OUTPUT
  else v=FAIL; fi
  echo "$v $n" >> "$OUT/results.txt"
}
n=0
for e in $(find "$B/testsuites" -name '*.exe' ! -name '*.norun.exe' | sort); do
  one "$e" &
  n=$((n+1)); [ $((n % J)) -eq 0 ] && wait
done
wait
awk '{c[$1]++} END {for (k in c) printf "%6d %s\n", c[k], k}' "$OUT/results.txt" | sort -rn
