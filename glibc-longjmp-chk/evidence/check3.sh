export PATH=/work/tc/bin:$PATH
W="test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh"
echo "CHECK3 START $(date)"
cd /build && make -j8 -k check $W > /work/check-full3.log 2>&1
echo "CHECK3 DONE rc=$? $(date)"
cp /build/tests.sum /work/tests-full.sum 2>/dev/null
echo "== summary"; cat /build/*/*.test-result | cut -d: -f1 | sort | uniq -c | grep -v "exit status"
echo "== FAIL list"; grep -l "^FAIL" /build/*/*.test-result | sed "s|/build/||;s|.test-result||" | tr "\n" " "; echo
