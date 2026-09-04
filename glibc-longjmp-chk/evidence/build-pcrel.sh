set -e
export PATH=/opt/gas/bin:/work/tc/bin:$PATH
ulimit -c 0
SR=/work/tc/microblazeel-buildroot-linux-gnu/sysroot
echo "PCREL BUILD START $(date)"
rm -rf /build-gcc2 && mkdir -p /build-gcc2 && cd /build-gcc2
/src/gcc/configure --target=microblazeel-linux-gnu --prefix=/opt/gcc17 --with-sysroot=$SR \
  --with-as=/opt/gas/bin/microblazeel-linux-gnu-as --with-ld=/opt/gas/bin/microblazeel-linux-gnu-ld \
  --enable-languages=c,c++ --disable-bootstrap --disable-multilib --disable-nls --disable-libsanitizer \
  --disable-libssp --disable-libquadmath --disable-libgomp --disable-libitm --disable-libvtv --disable-lto \
  --disable-werror > configure.log 2>&1
echo "GCC2 CONFIGURE DONE $(date)"
make -j8 > make.log 2>&1 || { echo "GCC2 BUILD FAILED $(date)"; grep -n -E " error: |Error [0-9]+$" make.log | head; exit 1; }
make install > install.log 2>&1
echo "GCC2 BUILD OK $(date)"
grep -h "HAVE_LD_RO_RW_SECTION_MIXING\|HAVE_GAS_CFI_DIRECTIVE\|HAVE_LD_EH_FRAME_HDR" gcc/auto-host.h
echo "== crtendS.o .eh_frame flags: $(microblazeel-linux-gnu-readelf -SW $(/opt/gcc17/bin/microblazeel-linux-gnu-gcc -print-file-name=crtendS.o) | grep eh_frame | awk '{print $2, $8}')"
echo "== libgcc_s: $(microblazeel-linux-gnu-readelf -SW /opt/gcc17/microblazeel-linux-gnu/lib/libgcc_s.so.1 | grep -E 'eh_frame' | awk '{print $2 "=" $8}' | tr '\n' ' ') dynrel=$(microblazeel-linux-gnu-readelf -rW /opt/gcc17/microblazeel-linux-gnu/lib/libgcc_s.so.1 | grep -c R_MICROBLAZE_REL)"
rm -rf /build-pcrel && mkdir -p /build-pcrel && cd /build-pcrel
/src/glibc-cfi/configure --host=microblazeel-linux-gnu --build=x86_64-linux-gnu --prefix=/usr \
  --with-headers=$SR/usr/include --disable-werror --disable-nscd --disable-crypt \
  CC=/opt/gcc17/bin/microblazeel-linux-gnu-gcc CXX=/opt/gcc17/bin/microblazeel-linux-gnu-g++ > configure.log 2>&1
grep -i "cfi" configure.log || true
echo "GLIBC CONFIGURE DONE $(date)"
make -j8 > make.log 2>&1 || { echo "PCREL MAKE FAILED $(date)"; grep -n -E " error: |Error [0-9]+$" make.log | head; exit 1; }
echo "PCREL MAKE OK $(date)"
RE=microblazeel-linux-gnu-readelf
for f in /build-cfi/libc.so /build-pcrel/libc.so /build-cfi/elf/ld.so /build-pcrel/elf/ld.so /build-pcrel/nptl/libpthread.so.0 /build-pcrel/math/libm.so; do
  [ -f $f ] || continue
  eh=$($RE -SW $f | grep -E " \.eh_frame " | awk '{print $8}'); hdr=$($RE -x .eh_frame_hdr $f 2>/dev/null | sed -n 3p | awk '{print $2}')
  lo=$($RE -SW $f | grep -E " \.eh_frame " | awk '{print "0x"$4}'); sz=$($RE -SW $f | grep -E " \.eh_frame " | awk '{print "0x"$6}')
  n=$($RE -rW $f | awk -v lo=$((lo)) -v hi=$((lo+sz)) '$3=="R_MICROBLAZE_REL"{a=strtonum("0x"$1); if (a>=lo && a<hi) c++} END{print c+0}')
  echo "   $f: .eh_frame flags=$eh hdr=$hdr REL-relocs-in-.eh_frame=$n fdes=$($RE --debug-dump=frames $f 2>/dev/null | grep -c FDE)"
done
echo "PCREL BUILD DONE $(date)"
