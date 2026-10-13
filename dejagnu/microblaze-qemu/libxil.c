/* Board support for qemu-system-microblaze[el], machine petalogix-s3adsp1800.
   This is the whole of what libgloss needs from a board.

   GCC's MicroBlaze LIB_SPEC (gcc/config/microblaze/microblaze.h:879) links
   "-start-group -lgloss -lxil -lc -lm -end-group".  libgloss supplies
   -lgloss and newlib -lc and -lm, but -lxil is the board's own library and
   upstream builds nothing for it: in Xilinx's world libxil.a comes from the
   tools' board support package.  libgloss's generic write() and read()
   (libgloss/write.c, read.c) are loops over outbyte() and inbyte(), which
   are declared and never defined for bare metal.

   So this file is libxil.a.  It is not a stub standing in for a real
   library; it is the interface libgloss is written against, and a QEMU UART
   is all it takes to satisfy it.  Build it with:

       <target>-gcc -O2 -ffreestanding -c mb-qemu-libxil.c -o outbyte.o
       <target>-ar  rc libxil.a outbyte.o

   The only device touched is the UART-lite: TX at +4, status at +8, TX-full
   is bit 3.  Stock upstream QEMU's petalogix-s3adsp1800 provides it, which
   is why this board needs no QEMU patch.  */

#define UART ((volatile unsigned int *) 0x84000000)

void
outbyte (char c)
{
  while (UART[2] & 0x8)
    ;
  UART[1] = (unsigned) (unsigned char) c;
}

/* Nothing is wired to the receiver.  Returning 0 makes read() report end of
   input rather than block, which is what the execute tests want: none of
   them reads, and a test that did would otherwise hang until the timeout.  */
char
inbyte (void)
{
  return 0;
}
