/* How small can a test be and still reach the partial remainder >= 2^63 state?
   Candidates: LLONG_MIN against divisors at and just below +-2^63.  */
#include <stdio.h>
#include <limits.h>
typedef unsigned long long u64; typedef long long s64;
static int reaches (s64 a, s64 b) {
  u64 X, D, R = 0; int count = 64, hit = 0;
  if (a == 0 || b == 0) return 0;
  X = a < 0 ? -(u64) a : (u64) a;
  D = b < 0 ? -(u64) b : (u64) b;
  if (!(X >> 63)) while (!(X >> 63)) { X <<= 1; count--; }
  for (int i = 0; i < count; i++) {
      u64 t = X >> 63; X <<= 1; R = (R << 1) | t;
      if (R >> 63) hit = 1;
      if (!((R - D) >> 63)) R -= D;
  }
  return hit;
}
int main (void) {
  struct { s64 a, b; const char *d; } c[] = {
    { LLONG_MIN, LLONG_MIN,     "LLONG_MIN % LLONG_MIN" },
    { LLONG_MIN, LLONG_MAX,     "LLONG_MIN % LLONG_MAX" },
    { LLONG_MIN, -LLONG_MAX,    "LLONG_MIN % -LLONG_MAX" },
    { LLONG_MIN, LLONG_MAX - 1, "LLONG_MIN % (LLONG_MAX-1)" },
    { LLONG_MIN, LLONG_MIN + 1, "LLONG_MIN % (LLONG_MIN+1)" },
    { LLONG_MAX, LLONG_MAX,     "LLONG_MAX % LLONG_MAX" },
    { LLONG_MIN, 1,             "LLONG_MIN % 1  (what pr50865 does)" },
    { LLONG_MIN, 3,             "LLONG_MIN % 3" },
  };
  for (unsigned i = 0; i < sizeof c / sizeof c[0]; i++)
    printf ("  %-36s reaches 2^63: %s   (%lld %% %lld == %lld)\n",
            c[i].d, reaches (c[i].a, c[i].b) ? "YES" : "no ",
            c[i].a, c[i].b, c[i].a % c[i].b);
  return 0;
}
