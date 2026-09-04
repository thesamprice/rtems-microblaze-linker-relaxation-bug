set -e
export PATH=/opt/gas/bin:/work/tc/bin:$PATH
ulimit -c 0
SR=/work/tc/microblazeel-buildroot-linux-gnu/sysroot
echo "PCREL BUILD3 START $(date)"
cd /build-pcrel
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
