#source: relax-addend.s
#source: relax-addend-support.s
#as: -mlittle-endian
#ld: -EL -relax --gc-sections -e _start -Ttext=0x90000000
#objdump: -d
#name: MicroBlaze relaxation must preserve R_MICROBLAZE_64 addends

# gvar is placed at 0x90000050 by this link, so the reference to gvar+0x18
# must be 0x90000068.  A linker that corrupts the addend emits 0x90000064.

.*: +file format elf32-microblazeel
#...
9000001c <zzz_victim>:
[ \t]*9000001c:[ \t]+b0009000[ \t]+imm[ \t]+-28672
[ \t]*90000020:[ \t]+e8600068[ \t]+lwi[ \t]+r3, r0, 104.*
#pass
