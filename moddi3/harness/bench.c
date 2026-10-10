/* Instruction-count benchmark using the machine's exit-and-counter device.
   With -icount 0 the virtual clock advances 1ns per instruction, so the
   delta is the exact instruction count.  MODFN is the routine under test. */
#include "vectors.h"
#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
/* The counter device is DEVICE_LITTLE_ENDIAN, so a big-endian CPU sees the
   32-bit value byte-swapped.  Undo that or the delta is nonsense.  */
#ifdef __MICROBLAZEEL__
# define CTRLO() (CTR[1])
#else
# define CTRLO() (__builtin_bswap32 (CTR[1]))
#endif
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void putu (unsigned v) { char b[12]; int i=0;
  if (!v) { putc_('0'); return; } while (v) { b[i++]='0'+(int)(v%10); v/=10; }
  while (i--) putc_(b[i]); }
extern long long MODFN (long long, long long);
void main_ (void) {
  unsigned bad = 0, t0, t1;
  volatile long long sink = 0;
  t0 = CTRLO();                                   /* clock lo, ns == insns */
  for (unsigned i = 0; i < NTV; i++) {
    long long g = MODFN (tv[i].a, tv[i].b);
    if (g != tv[i].r) bad++;
    sink += g;
  }
  t1 = CTRLO();
  puts_ ("BENCH bad="); putu (bad);
  puts_ (" insns="); putu (t1 - t0);
  puts_ ("\r\n");
  CTR[0] = 0;                                    /* clean shutdown */
  for (;;) ;
}
