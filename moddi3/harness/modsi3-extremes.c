/* Does the hand-written 32-bit modsi3.S/divsi3.S have the same class of bug
   at the extremes?  Host-computed expectations, compared on target.  */
#define INT_MIN (-2147483647 - 1)
#define INT_MAX 2147483647
#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static void putd (int v) {
  char b[12]; int i = 0; unsigned u = v < 0 ? (putc_ ('-'), -(unsigned) v) : v;
  if (!u) { putc_ ('0'); return; }
  while (u) { b[i++] = '0' + u % 10; u /= 10; }
  while (i--) putc_ (b[i]);
}
static int __attribute__ ((noinline, noclone)) m (int a, int b) { return a % b; }
static int __attribute__ ((noinline, noclone)) d (int a, int b) { return a / b; }
struct { int a, b, m, d; } t[] = {
  { INT_MIN, INT_MAX,  -1,  -1 },
  { INT_MIN, -INT_MAX, -1,   1 },
  { INT_MIN, INT_MIN,   0,   1 },
  { INT_MAX, INT_MIN,  INT_MAX, 0 },
  { INT_MIN, INT_MAX - 1, -2, -1 },
  { INT_MIN, INT_MIN + 1, -1,  1 },
  { INT_MIN, 1,         0, INT_MIN },
  { INT_MIN, 3,        -2, -715827882 },
};
void main_ (void) {
  int bad = 0;
  for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
      volatile int a = t[i].a, b = t[i].b;
      int gm = m (a, b), gd = d (a, b);
      if (gm != t[i].m) { puts_ ("MOD-BAD i="); putd (i); puts_ (" got="); putd (gm); puts_ ("\r\n"); bad++; }
      if (gd != t[i].d) { puts_ ("DIV-BAD i="); putd (i); puts_ (" got="); putd (gd); puts_ ("\r\n"); bad++; }
  }
  puts_ (bad ? "RESULT 32-bit BROKEN\r\n" : "RESULT 32-bit ALL PASS\r\n");
  CTR[0] = 0; for (;;) ;
}
