/* An instrumented __moddi3: computes the same answer by the same radix-2
   restoring-division recurrence the assembly uses, but shouts on the UART the
   first time the partial remainder reaches 2^63 -- the state the signed
   trial-subtraction test is only safe at because of the D <= 2^63 bound.
   Linked into a test, it answers "does this test reach that state?".  */
#define UART ((volatile unsigned int *) 0x84000000)
typedef unsigned long long u64;
typedef long long s64;
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
static int said;

long long __moddi3 (long long a, long long b) {
  u64 X, D, R = 0;
  int neg = a < 0, count = 64;
  if (a == 0 || b == 0) return 0;
  X = neg ? -(u64) a : (u64) a;
  D = b < 0 ? -(u64) b : (u64) b;
  if (!(X >> 63)) while (!(X >> 63)) { X <<= 1; count--; }
  for (int i = 0; i < count; i++) {
      u64 t = X >> 63;
      X <<= 1;
      R = (R << 1) | t;
      if ((R >> 63) && !said) { said = 1; puts_ ("BOUNDARY-REACHED\r\n"); }
      if (!((R - D) >> 63)) R -= D;
  }
  return neg ? -(s64) R : (s64) R;
}
