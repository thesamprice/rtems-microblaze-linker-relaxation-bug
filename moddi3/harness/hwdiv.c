/* Exercise the HARDWARE idiv/idivu path and read MSR afterwards. */
#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void px (unsigned v) { puts_ ("0x");
  for (int s = 28; s >= 0; s -= 4) putc_ ("0123456789abcdef"[(v >> s) & 0xf]); }
static inline unsigned rd_msr (void) { unsigned m; __asm__ volatile ("mfs %0, rmsr" : "=r"(m)); return m; }
static inline void clr_dz (void) { __asm__ volatile ("msrclr r0, 0x40" ::: "memory"); }
__attribute__((noinline)) static int  ds (int a, int b)           { return a / b; }
__attribute__((noinline)) static int  ms (int a, int b)           { return a % b; }
__attribute__((noinline)) static unsigned du (unsigned a, unsigned b) { return a / b; }
static volatile int z = 0; static volatile unsigned uz = 0;
static volatile int mone = -1, imin = (-2147483647 - 1);
void main_ (void) {
  clr_dz (); puts_ ("  MSR before      = "); px (rd_msr ()); puts_ ("\r\n");
  puts_ ("  5 / 0  (idiv)   = "); px ((unsigned) ds (5, z));
  puts_ ("   MSR = "); px (rd_msr ()); puts_ ("\r\n");
  clr_dz ();
  puts_ ("  5 %% 0  (idiv)   = "); px ((unsigned) ms (5, z));
  puts_ ("   MSR = "); px (rd_msr ()); puts_ ("\r\n");
  clr_dz ();
  puts_ ("  5u / 0u (idivu) = "); px (du (5u, uz));
  puts_ ("   MSR = "); px (rd_msr ()); puts_ ("\r\n");
  clr_dz ();
  puts_ ("  INT_MIN / -1    = "); px ((unsigned) ds (imin, mone));
  puts_ ("   MSR = "); px (rd_msr ()); puts_ ("\r\n");
  puts_ ("HW-DONE\r\n"); CTR[0] = 0; for (;;) ;
}
