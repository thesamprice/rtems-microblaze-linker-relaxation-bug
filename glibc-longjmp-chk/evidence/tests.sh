# Usage: tests.sh <label>  -- build & run debug/tst-longjmp_chk* via qemu-user, print results
set -e
export PATH=/work/tc/bin:$PATH
B=/build; L=$1
cd $B
rm -f debug/tst-longjmp_chk*.out debug/tst-longjmp_chk*.test-result
make -j8 objdir=$B -C /src/glibc/debug tests \
  test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh \
  tests='tst-longjmp_chk tst-longjmp_chk2 tst-longjmp_chk3' > /work/tests-$L.log 2>&1 || true
echo "== [$L] ____longjmp_chk in freshly built libc.so"
microblazeel-linux-objdump -d $B/libc.so | awk '/<____longjmp_chk>:/,/^$/' | head -40
echo "== [$L] test results"
for t in tst-longjmp_chk tst-longjmp_chk2 tst-longjmp_chk3; do
  printf '%s: ' $t; cat debug/$t.test-result 2>/dev/null | tr '\n' ' '; echo; sed 's/^/    /' debug/$t.out 2>/dev/null | head -12
done
