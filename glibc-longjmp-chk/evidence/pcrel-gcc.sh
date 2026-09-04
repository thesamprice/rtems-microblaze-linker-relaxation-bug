export PATH=/opt/gas/bin:/work/tc/bin:$PATH
GCC=/opt/gcc16/bin/microblazeel-linux-gnu-gcc
RE=microblazeel-linux-readelf
SYSROOT=/work/tc/microblazeel-buildroot-linux-gnu/sysroot
mkdir -p /work/pcg && cd /work/pcg
cat > lib.c <<'A'
void (*volatile fp)(void);
__attribute__((noinline)) void lib_leaf (void) { fp (); }
__attribute__((noinline)) void lib_mid (void) { lib_leaf (); __asm__ volatile (""); }
A
cat > main.c <<'A'
#include <unwind.h>
#include <stdio.h>
extern void (*volatile fp)(void);
extern void lib_mid (void);
static _Unwind_Reason_Code cb (struct _Unwind_Context *ctx, void *arg)
{
  int *n = arg;
  printf ("frame %d: ip=%p cfa=%p\n", (*n)++, (void *) _Unwind_GetIP (ctx), (void *) _Unwind_GetCFA (ctx));
  return *n > 20 ? _URC_END_OF_STACK : _URC_NO_REASON;
}
static void leaf (void) { int n = 0; _Unwind_Reason_Code r = _Unwind_Backtrace (cb, &n); printf ("result %d after %d frames\n", r, n); }
int main (void) { fp = leaf; lib_mid (); puts ("back in main"); return 0; }
A
echo "== 1. gcc 17 assembly for a PIC -fexceptions object"
$GCC -O2 -fPIC -fexceptions -S -o lib.s lib.c && grep -n "\.4byte.*-\s*\.\|\.byte\s*0x1b\|\.cfi_startproc\|augment\|\.section\s*\.eh_frame" lib.s | head -8
echo "== 2. relocations and FDE encoding in the object"
$GCC -O2 -fPIC -fexceptions -c -o lib.o lib.c && $RE -rW lib.o | sed -n '/eh_frame/,/^$/p' | head -8; $RE --debug-dump=frames lib.o | grep -E "Augmentation data|FDE"
echo "== 3. shared object"
$GCC -shared -o liblib.so lib.o 2>&1 | head -3
$RE -SW liblib.so | grep -E "\.eh_frame|\.text " | awk '{print "   " $2, "flags=" $8}'
echo "   R_MICROBLAZE_REL dynamic relocs: $($RE -rW liblib.so | grep -c R_MICROBLAZE_REL)"
echo "   PT_GNU_EH_FRAME: $($RE -lW liblib.so | grep -c GNU_EH_FRAME)"
echo "   hdr: $($RE -x .eh_frame_hdr liblib.so | sed -n 3p)"
echo "   FDEs: $($RE --debug-dump=frames liblib.so | grep FDE | sed 's/.*pc=//' | tr '\n' ' ')"
echo "   syms: $(microblazeel-linux-nm liblib.so | grep ' T lib_' | tr '\n' ' ')"
echo "== 4. unwind from the executable through the DSO"
$GCC -O2 -fexceptions -o main main.c -L. -llib -Wl,-rpath,/work/pcg 2>&1 | head -3
$RE -SW main | grep -E "\.eh_frame" | awk '{print "   " $2, "flags=" $8}'
LD_LIBRARY_PATH=/work/pcg:/opt/gcc16/microblazeel-linux-gnu/lib timeout 60 qemu-microblazeel -L $SYSROOT -E LD_LIBRARY_PATH=/work/pcg:/opt/gcc16/microblazeel-linux-gnu/lib ./main ./main; echo "   exit=$?"
echo "== 5. same, old gas (Bootlin binutils 2.43) for comparison of the DSO"
/work/tc/bin/microblazeel-buildroot-linux-gnu-gcc -O2 -fPIC -fexceptions -c -o lib-old.o lib.c && /work/tc/bin/microblazeel-buildroot-linux-gnu-gcc -shared -o liblib-old.so lib-old.o && $RE -SW liblib-old.so | grep -E "\.eh_frame" | awk '{print "   " $2, "flags=" $8}'; echo "   R_MICROBLAZE_REL: $($RE -rW liblib-old.so | grep -c R_MICROBLAZE_REL)"; $RE --debug-dump=frames lib-old.o | grep "Augmentation data"
echo "PCREL GCC DONE"
