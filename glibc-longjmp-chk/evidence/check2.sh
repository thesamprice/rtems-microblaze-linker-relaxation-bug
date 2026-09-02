export PATH=/work/tc/bin:$PATH
W="test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh"
until grep -q 'FORTIFY DONE\|FORTIFY MAKE FAILED' /work/check.log; do sleep 60; done
echo "RERUN CHECK START $(date)"
cd /build && rm -rf testroot.pristine && make -j8 -k check $W > /work/check-full2.log 2>&1
echo "RERUN CHECK DONE rc=$? $(date)"
cp /build/tests.sum /work/tests-full.sum 2>/dev/null
echo "== summary"; grep -E '^(PASS|FAIL|XFAIL|XPASS|UNSUPPORTED|UNRESOLVED):' /build/tests.sum | cut -d: -f1 | sort | uniq -c
echo "== FAIL list"; grep -E '^FAIL:' /build/tests.sum
