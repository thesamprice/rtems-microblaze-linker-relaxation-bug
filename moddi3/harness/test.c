/* Freestanding __moddi3 check for qemu petalogix-s3adsp1800.
   UART-lite TX at 0x84000000 + 4; status at +8, TX-full is bit 3.  */
#include "vectors.h"

#define UART ((volatile unsigned int *) 0x84000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void putu (unsigned long long v) {
  char b[24]; int i = 0;
  if (!v) { putc_ ('0'); return; }
  while (v) { b[i++] = '0' + (int) (v % 10); v /= 10; }
  while (i--) putc_ (b[i]);
}
static void puthex (unsigned long long v) {
  puts_ ("0x");
  for (int s = 60; s >= 0; s -= 4) putc_ ("0123456789abcdef"[(v >> s) & 0xf]);
}

extern long long __moddi3 (long long, long long);

void main_ (void) {
  unsigned bad = 0;
  for (unsigned i = 0; i < NTV; i++) {
    long long got = __moddi3 (tv[i].a, tv[i].b);
    if (got != tv[i].r) {
      if (bad < 5) {
        puts_ ("FAIL a="); puthex ((unsigned long long) tv[i].a);
        puts_ (" b="); puthex ((unsigned long long) tv[i].b);
        puts_ (" want="); puthex ((unsigned long long) tv[i].r);
        puts_ (" got="); puthex ((unsigned long long) got);
        puts_ ("\r\n");
      }
      bad++;
    }
  }
  puts_ ("RESULT total="); putu (NTV);
  puts_ (" bad="); putu (bad);
  puts_ (bad ? " -- BROKEN\r\n" : " -- ALL PASS\r\n");
  /* park */
  for (;;) ;
}
