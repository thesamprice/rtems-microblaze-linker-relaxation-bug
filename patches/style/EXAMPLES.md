# Good and weak commit messages, with reasons

Chosen by reading 257 sampled commits with their diffs (data/deep-*.tsv).
Every SHA below resolves in the upstream repository.  "Good" and "weak"
are this study's judgments **[RECOMMENDED]**: the test is whether a reader
learns what changed and why, not length.  Weak examples are spread across
authors on purpose; several prolific authors appear in both lists.

## GCC

### Good

| SHA | Subject | Why it works |
|---|---|---|
| e8621d3bdaf0 | match-sat-alu.pd: Check operand types of signed SAT_ADD [PR127916] | Shows the C and GIMPLE, the wrong value (-57), the regressing revision (r15-6406), the fix, the side effect and the testing. |
| d794365c8f0d | ipa-icf: compare the field, not just the offset, under OEP_ADDRESS_OF [PR119006] | One-line fix with a precise root cause: quotes the flag's documented meaning and the PR's scenario. |
| e78da8455a1e | c++: Fix up assert in build_vec_init [PR126752] | The r-number chain explains why changing one token is correct. |
| 4d22d3ead95e | ranger: use the index range for loads from constant aggregates | Before-and-after ranges, a motivating example, testing. |
| 5be7b70e769e | i386: Enable 512-bit byte dot-product only under AVX512BW [PR126098] | ISA reasoning, the ICE, and why the word variant is left alone. |
| 1beab80079e2 | RISC-V: Remove obsolete CACHE_ALIGNED_STD fusion | Three sentences on why the code is dead. Short and complete. |
| 73ae58ac01fc | testsuite: powerpc64: Fix gcc.dg/asm-hard-reg-5.c | The error text plus the endianness reason. |
| 177b84bd12e0 | gcov: Split atomic bitwise-or for some targets | Affected targets, an asm example, an honestly scoped test list. |
| a43cd560e438 | libstdc++: Make make_decimalN inline instead of static [PR122071] | The linkage consequence and why `inline` fixes it. |
| 35874595799c | ifcvt: decode the multiple-sets condition once | A model no-functional-change message. |

### Weak

| SHA | Subject | What is missing |
|---|---|---|
| 69d8bd0b3f5c | Revert "rs6000: Add new builtin __builtin_ppc_atomic_cas_local" | Reverts 700 lines with no reason. |
| 8858cb3a6af5 | libbacktrace: handle MOREDATA correctly without debug info | 437 lines; the only prose is an attribution. |
| 470f86dd50a8 | fix: Check if loop_vinfo is null before dereferencing. | When is it null, and which caller hits it?  Non-GCC prefix, no PR, no test. |
| 4ff8e6ba9f4e | aarch64: Port NEON lane get/set intrinsics to pragma-based framework | No why, deleted tests unmentioned, no testing for a large change. |
| 96a93d365915 | cobol: Add official COBOL word lists to parser. | 559 lines of generated headers, source and purpose not given. |
| ea1a75bfd580 | [RISC-V] Improve ADD synthesis | A mailing-list cover letter committed verbatim; future-work notes bury the change. |
| 9d59dcff40a4 | match.pd: Simplify (~A & 1) == (~B & 1) at -O1 [PR112533] | Good core padded with a v2-v5 revision log. |
| 51c8f3368607 | libstdc++: Remove unused variable | A full build log for a one-line removal; the useful line is "introduced in r16-8142". |

## binutils

### Good

| SHA | Subject | Why it works |
|---|---|---|
| 0cdae10e5786 | memory mayhem in _bfd_elf_link_read_relocs | Names the regressing commit, admits the testsuite gap, gives a reproducer, one-line cause, extended test. |
| 4bc3f403c566 | Solaris .strtab and .shstrtab flags | Why the previous design fails when Solaris is not the default, then where the logic now lives. |
| 1a5ff476f78f | bfd/rl78: remove unused bfd_elf32_rl78_set_target_flags | Quoted compiler error plus history, in four lines. |
| aa4fbe885956 | s390: Do not generate incomplete opcode table | Failure mode, consequence, fix, and exactly how it was tested. |
| 6197c6f3a6f9 | xfail undefweak-1 test for alpha | Two sentences recording why the obvious alternatives break other targets. |
| 3f89802f207a | bfd: correct dir separator conversion for Win32 | Two bugs, each with mechanism and fix, compactly. |
| 7b12694de97f | LD/testsuite: Fix archive verification for Alpha/VMS | History, root cause, and the exact FAIL lines removed. |
| 5ad7fd27ba37 | aarch64: Don't relax relocations to static function symbols | ABI rule, fix, the deliberately deferred check, test fallout explained. |
| b49b0bfe1215 | bfd/ELF: fold BFD_RELOC_<arch>_PCREL* | A cross-target refactor justified, exceptions named per target. |
| f6b0f53a3682 | PR 33455 SEGV in vfinfo at ldmisc.c:527 | The subject is the symptom; one sentence of cause; minimal ChangeLog. |

### Weak

| SHA | Subject | What is missing |
|---|---|---|
| ea1a0737c769 | elf: Don't read beyond .eh_frame section size | PR plus ChangeLog only; no trigger, no mention that strlen over-reads unterminated input. |
| 674628ae3a1d | PR 33360, Correct strings -Ue output | No body; what output was wrong? |
| eac88f329849 | Add support for Windows network paths to the UNC support in _bfd_real_open(). | A 108-line change with "PR 31527" as the whole body. |
| 40a04cee22b2 | Synchronize the dwarf2.h and dwarf2.def files ... | The whole message in a 208-character subject. |
| 1785837a2570 | ld: fix PR/32297 | Good body, but the subject says nothing in `git log --oneline`. |
| 63f5af1fe20b | gas/testsuite: Fix multibyte3 test cases on Windows | Says which tests were not changed, never what failed. |
| 44fab92685fd | ld: Don't treated the fatal error as warning | Restates the diff; the user-visible effect is not given. |
| 45f3ea0bbb5e | Revert "binutils: Require GNU tail for 'objdump -Wi' test" | No reason for the revert. |

## Too long

Rare in both samples (GCC 4 of 140, binutils 3 of 117).  The pattern is
material the diff or a cited document already carries: a 40-line readelf
dump with the flags legend (31d589588ea4), a section-layout tutorial
(0924a1ca2e1e), command output that repeats a one-line diff
(0326df1b9b1f), a build log (51c8f3368607).  Per-patch test-result
paragraphs repeated across a series, as this repo's MicroBlaze opcodes
series had, fall in the same class.
