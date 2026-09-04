set -e
export PATH=/work/tc/bin:$PATH
SR=/work/tc/microblazeel-buildroot-linux-gnu/sysroot
[ -d /src/glibc ] || { mkdir -p /src && cp -r /work/glibc-src /src/glibc; }
B=/build; mkdir -p $B; cd $B
if [ ! -f config.status ]; then
  /src/glibc/configure --host=microblazeel-linux-gnu --build=x86_64-linux-gnu --prefix=/usr \
    --with-headers=$SR/usr/include --disable-werror --disable-nscd --disable-crypt \
    CC=microblazeel-linux-gcc CXX=microblazeel-linux-g++ > configure.log 2>&1
fi
echo "configure done $(date)"
make -j8 > make.log 2>&1 && echo "MAKE OK $(date)" || { echo "MAKE FAILED $(date)"; grep -n -E " error: |Error [0-9]+$|No such file" make.log | head; exit 1; }
