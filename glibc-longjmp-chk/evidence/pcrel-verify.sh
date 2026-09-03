export PATH=/opt/gas/bin:/work/tc/bin:$PATH
ulimit -c 0
python3 /work/pcrel-fix4.py /src/binutils; python3 /work/pcrel-fix5.py /src/binutils
cd /build-gas && make -j8 all-gas all-ld all-binutils > /work/pcrel-make.log 2>&1 && make install-gas install-ld install-binutils > /dev/null 2>&1 && echo "BINUTILS REBUILT" || { echo "BINUTILS BUILD FAILED"; grep -n " error" /work/pcrel-make.log | head -5; exit 1; }
cd /work; AS=/opt/gas/bin/microblazeel-linux-gnu-as; LD=/opt/gas/bin/microblazeel-linux-gnu-ld
echo "== (a) cross-section sym - ."
printf ".text\n.globl f\nf: nop\n nop\n.Lloc: nop\n.section .rodata\n.globl p\np: .4byte f - .\nq: .4byte .Lloc - .\n" > pc1.s; $AS -o pc1.o pc1.s && microblazeel-linux-readelf -r pc1.o | grep -A3 rodata | tail -2
$LD -shared -o pc1.so pc1.o && echo "-- linked DSO: dynamic relocs: $(microblazeel-linux-readelf -rW pc1.so | grep -c R_MICROBLAZE)"; f=$(microblazeel-linux-nm pc1.so | awk '$3=="f"{print $1}'); p=$(microblazeel-linux-nm pc1.so | awk '$3=="p"{print $1}'); v=$(microblazeel-linux-objcopy -O binary --only-section=.rodata pc1.so /tmp/r.bin && od -An -tx4 -N4 /tmp/r.bin | tr -d ' '); echo "-- f=$f p=$p stored=$v expected=$(printf %08x $(( (0x$f - 0x$p) & 0xffffffff )))"
echo "== (a2) addend matrix"; $AS -o dt.o dt.s && microblazeel-linux-readelf -rW dt.o | grep -A8 rodata | tail -5
echo "== (b) gas CFI now pcrel?"; $AS -o cfi.o cfi.s && microblazeel-linux-readelf --debug-dump=frames cfi.o | grep "Augmentation data"; $LD -shared --eh-frame-hdr -o cfi.so cfi.o 2>&1 | head -2; microblazeel-linux-readelf -SW cfi.so | grep -E "eh_frame" | awk '{print $2, $8}'; microblazeel-linux-readelf -x .eh_frame_hdr cfi.so | sed -n 3p
f=$(microblazeel-linux-nm cfi.so | awk '$3=="f"{print $1}'); echo "-- CFI FDE in DSO: $(microblazeel-linux-readelf --debug-dump=frames cfi.so | grep FDE | sed s/.*pc=//)  f is at $f"
echo "== (c) relaxation: imm deleted before the target"
cat > rx.s <<'A'
	.text
	.globl _start
_start:
	addik	r3, r0, small	/* gas emits imm+addik with R_MICROBLAZE_64; ld deletes the imm */
	nop
	.globl f
f:	nop
	nop
	.section .rodata
	.globl small
	.globl p
small:	.4byte 1
p:	.4byte f - .
A
$AS -o rx.o rx.s && $LD -relax -Ttext=0x100 -Tdata=0x1000 -o rx rx.o && echo "-- linked with -relax"; microblazeel-linux-objdump -d rx | grep -c "imm" | sed 's/^/   imm instructions left: /'; f=$(microblazeel-linux-nm rx | awk '$3=="f"{print $1}'); p=$(microblazeel-linux-nm rx | awk '$3=="p"{print $1}'); v=$(microblazeel-linux-objcopy -O binary --only-section=.rodata rx /tmp/r.bin && od -An -tx4 -j4 -N4 /tmp/r.bin | tr -d ' '); echo "-- f=$f p=$p stored=$v expected=$(printf %08x $(( (0x$f - 0x$p) & 0xffffffff )))"
echo "PCREL VERIFY DONE"
