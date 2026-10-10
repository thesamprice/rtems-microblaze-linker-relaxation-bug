#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void px (unsigned long long v) { puts_ ("0x");
  for (int s = 60; s >= 0; s -= 4) putc_ ("0123456789abcdef"[(v >> s) & 0xf]); }
extern long long MODFN (long long, long long);
static volatile long long zero = 0;
void main_ (void) {
  static const long long a[] = { 0, 1, -1, 5, -5, 0x123456789abcLL };
  for (unsigned i = 0; i < sizeof a / sizeof a[0]; i++) {
    puts_ ("  a="); px ((unsigned long long) a[i]);
    puts_ (" a%0 = "); px ((unsigned long long) MODFN (a[i], zero));
    puts_ ("\r\n");
  }
  puts_ ("DBZ-DONE\r\n"); CTR[0] = 0; for (;;) ;
}
