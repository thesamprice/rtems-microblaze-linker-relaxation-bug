#define UART ((volatile unsigned int *) 0x84000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void puth (unsigned long long v) { puts_("0x"); for (int s=60;s>=0;s-=4) putc_("0123456789abcdef"[(v>>s)&0xf]); }
extern void exit (int);
extern void abort (void);

static long long __attribute__((noinline,noclone))
cshift (long long x, int n)
{
  switch (n)
    {
    case 0: x = x >> 0; break;
    case 1: x = x >> 1; break;
    case 2: x = x >> 2; break;
    case 3: x = x >> 3; break;
    case 4: x = x >> 4; break;
    case 5: x = x >> 5; break;
    case 6: x = x >> 6; break;
    case 7: x = x >> 7; break;
    case 8: x = x >> 8; break;
    case 9: x = x >> 9; break;
    default: abort ();
    }
  return x;
}

int main (void) {
  volatile long long v = 0x7654321fedcba980LL;
  int bad = 0;
  for (int i = 0; i < 10; i++) {
      long long got = cshift (v, i);
      long long want = v >> i;
      if (got != want) {
          puts_ ("n="); puth ((unsigned) i); puts_ (" got="); puth (got);
          puts_ (" want="); puth (want); puts_ ("\r\n"); bad++;
      }
  }
  puts_ (bad ? "BAD\r\n" : "OK\r\n");
  exit (bad != 0);
}
