/*
 * mb-abi-demo.c -- show the MicroBlaze arg-passing ABI that the kernel
 * entry.S "reserve the argument save area" patch (and the glibc
 * syscall_cancel offsets) are built on.
 *
 * Build (any microblaze[el] gcc), then read the .s:
 *
 *     microblazeel-buildroot-linux-gnu-gcc -O2 -S mb-abi-demo.c -o mb-abi-demo.s
 *
 * Two things to look for in the assembly:
 *
 *   caller_8args():  the 7th/8th args are stored at r1+28 and r1+32
 *                    -> stack args start at sp+28
 *                       = FIRST_PARM_OFFSET(4) + REG_PARM_STACK_SPACE(6*4=24)
 *                    (same offsets the glibc __syscall_cancel_arch reads)
 *
 *   callee_spills(): the 6 incoming register args (r5..r10) are spilled to
 *                    [caller_sp+4 .. caller_sp+28) -- i.e. it writes ABOVE its
 *                    own frame, into the arg-home area the CALLER reserved.
 *                    If the caller left r1 pointing at pt_regs (stock kernel
 *                    entry.S), those stores land on pt_regs+4..+24 -> the
 *                    AT_FDCWD-on-saved-r1 boot panic. C_ARG_SIZE just moves
 *                    this spill area into scratch below pt_regs.
 */

extern int  inner(int a,int b,int c,int d,int e,int f,int g,int h);
extern void sink(int);

/* CALLER: pass 8 args. a..f go in r5..r10; g,h go on the stack. */
int caller_8args(int a,int b,int c,int d,int e,int f)
{
	return inner(a, b, c, d, e, f, /*g=*/7, /*h=*/8);
}

/* CALLEE: use all 6 register args across a call, forcing the compiler
   to spill them into the caller-provided arg-home area. */
int callee_spills(int a,int b,int c,int d,int e,int f)
{
	sink(0);                       /* clobbers r5..r10 -> a..f must be saved */
	return a + b + c + d + e + f;
}
