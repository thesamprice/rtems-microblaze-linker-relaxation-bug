<!-- Raw upstream-audit verification record. The per-patch docs summarise
     this; here are the exact file:line checks against upstream, so the
     audit can be re-run. Verified 2026-09-04 against binutils master
     193340ad3 (git-protocol fetch), gcc master via gcc-mirror/gcc, and
     glibc master via bminor/glibc; base commits binutils 6f24afa,
     glibc 10ed541. -->

# Upstream audit ground truth (verified against master 193340ad3, 2026-09-04; base 6f24afa 2026-08-31)

## binutils
- 0001 relaxation sh_info guard: ALREADY UPSTREAM — in BASE 6f24afa (elf32-microblaze.c:2125), incl v2 tidy-ups (PTR_ADD, sh_info-only read). The original relaxation miscompile. LANDED between Aug 5 (old README base b7da195) and Aug 31.
- 0002 RELOC_AGAINST_DISCARDED_SECTION: ALREADY UPSTREAM — in BASE (elf32-microblaze.c:1120).
- 0003 pr24511 xfail widen: STILL OPEN — base ld-elf/pr24511.d xfails microblaze*-*-elf* only, not microblaze*-linux*. Testsuite only.
- 0004 md_apply_fix BFD_RELOC_8/16: STILL OPEN — base md_apply_fix has case 32/RVA/64 but NOT 8/16.
- 0005 dwarf2 equal-range tiebreak by unit_offset: STILL OPEN (independent, arch-neutral; not sent). Base best_fit tiebreak at dwarf2.c:3365-3369.
- 0006 gas CFI: STILL OPEN — no TARGET_USE_CFIPOP/tc_cfi_* in master.
- 0007 eh_frame -2 static reloc: STILL OPEN — master -2 arm sets skip only, no relocate/bfd_put_32.
- 0008 canonical PLT: STILL OPEN — master still "Zero the value" sym->st_value=0 at 3326 unconditionally.
- 0009 pcrel data relocs: STILL OPEN — no DIFF_EXPR_OK, howto still partial_inplace true (:82).

## gcc
- 0001 libgcc signal frame: EXISTING upstream file, CORRECTION not new. Master libgcc/config/microblaze/linux-unwind.h is uClibc-only-correct (uc = pc - sizeof(ucontext_t); sc = &uc->uc_mcontext; comment "uClibc's ucontext_t matches the kernel's"). Wrong for glibc (glibc ucontext_t larger). Our patch anchors sc at context->cfa + siginfo_t + 2*long + stack_t (matches or1k/sh rt_sigframe layout).
- 0002 pcrel EH encodings: STILL OPEN — master microblaze.h:209 still DW_EH_PE_aligned.

## glibc (all UNFIXED upstream, verified via bminor/glibc mirror by subagents)
- 0001 longjmp_chk stub: UNFIXED (____longjmp_chk.S still the rtsd r15,0 stub; jmpbuf-offsets.h 404).
- 0002 libm nofpu headers: UNFIXED (both math-tests-*.h 404).
- 0003 pass _dl_fini: UNFIXED (start.S still zeroes r10, no r15 logic).
- 0004 ucontext: UNFIXED (getcontext.S/ucontext_i.sym/makecontext.c 404; generic ENOSYS stub).
- 0005 asm CFI: UNFIXED (sysdep.h ENTRY has no cfi_startproc; no HAVE_MICROBLAZE_ASM_CFI).
- 0006 generic backtrace: pending agent E.
- 0007 ld.so eh_frame terminator: pending agent E.

## KEY CONSEQUENCES
1. binutils 0001+0002 are upstream: the relaxation miscompile is FIXED in binutils master. The repo's central bug is resolved upstream. Harness correctly does NOT re-apply them (glob 000[6-9]).
2. gcc 0001 is a CORRECTION of a live upstream file, not a new file — reframe commit msg + doc.
3. Everything else (binutils 0003-0009, gcc 0002, glibc all) is genuinely still open.

