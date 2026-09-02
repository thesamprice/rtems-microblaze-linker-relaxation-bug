export PATH=/work/tc/bin:$PATH
W="test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh"
echo "NPTLRT START $(date)"
for d in nptl rt; do
  make -j8 -k objdir=/build -C /src/glibc/$d tests $W > /work/tests-$d.log 2>&1
  echo "$d done rc=$? $(date)"
done
echo "NPTLRT DONE $(date)"
for d in nptl rt; do echo "== $d"; cat /build/$d/*.test-result | cut -d: -f1 | sort | uniq -c | grep -v "exit status"; done
