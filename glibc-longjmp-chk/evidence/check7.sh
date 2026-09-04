export PATH=/opt/gas/bin:/work/tc/bin:$PATH
W="test-wrapper=/work/qemu-wrap.sh test-wrapper-env=/work/qemu-wrap.sh test-wrapper-env-only=/work/qemu-wrap.sh"
ulimit -c 0
echo "CHECK7 START $(date)"
cd /build-pcrel && rm -rf testroot.pristine testroot.root
make -j8 -k check $W > /work/check-full7.log 2>&1
echo "CHECK7 MAIN DONE rc=$? $(date)"
for d in nptl rt; do make -j8 -k objdir=/build-pcrel -C /src/glibc-cfi/$d tests $W > /work/tests7-$d.log 2>&1; done
echo "CHECK7 DONE $(date)"
cat /build-pcrel/*/*.test-result | cut -d: -f1 | sort | uniq -c | grep -v "exit status"
