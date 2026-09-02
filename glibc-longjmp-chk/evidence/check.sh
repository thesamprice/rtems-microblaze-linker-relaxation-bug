export PATH=/work/tc/bin:$PATH
SR=/work/tc/microblazeel-buildroot-linux-gnu/sysroot
W="test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh"
echo "CHECK START $(date)"
cd /build && make -j8 -k check $W > /work/check-full.log 2>&1
echo "CHECK DONE rc=$? $(date)"
cp /build/tests.sum /work/tests-full.sum 2>/dev/null
echo "== summary"; grep -E '^(PASS|FAIL|XFAIL|XPASS|UNSUPPORTED|UNRESOLVED):' /build/tests.sum | cut -d: -f1 | sort | uniq -c
echo "FORTIFY BUILD START $(date)"
mkdir -p /build-fortify && cd /build-fortify
/src/glibc/configure --host=microblazeel-linux-gnu --build=x86_64-linux-gnu --prefix=/usr \
  --with-headers=$SR/usr/include --disable-werror --disable-nscd --disable-crypt --enable-fortify-source=2 \
  CC=microblazeel-linux-gcc CXX=microblazeel-linux-g++ > configure.log 2>&1
make -j8 > make.log 2>&1 && echo "FORTIFY MAKE OK $(date)" || { echo "FORTIFY MAKE FAILED $(date)"; exit 1; }
for d in setjmp debug; do
  make -j8 -k objdir=/build-fortify -C /src/glibc/$d tests $W > /work/fortify-$d.log 2>&1
done
echo "== fortify results (setjmp, debug)"
cat /build-fortify/setjmp/*.test-result /build-fortify/debug/*.test-result 2>/dev/null | sort | uniq -c | sort -rn | head -80
echo "FORTIFY DONE $(date)"
