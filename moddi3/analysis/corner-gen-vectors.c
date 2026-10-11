/* Emit the boundary-reaching vectors as a vectors.h for the target harness:
   every pair that drives the partial remainder to 2^63.  */
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
      u64 top = X >> 63; X <<= 1; R = (R << 1) | top;
      if (R >> 63) hit = 1;
      if (!((R - D) >> 63)) R -= D;
  }
  return hit;
}
static void pv (s64 x) {
  if (x == LLONG_MIN) printf ("(-9223372036854775807LL - 1)");
  else printf ("%lldLL", x);
}
int main (void) {
  int n = 0;
  printf ("/* generated - boundary-reaching corner cases */\n");
  printf ("struct tv { long long a, b, r; };\nstatic const struct tv tv[] = {\n");
  for (int xd = 0; xd < 4096; xd++)
    for (int dd = 0; dd < 4096; dd++)
      for (int sx = 0; sx < 2; sx++)
        for (int sd = 0; sd < 2; sd++) {
            s64 a = sx ? LLONG_MIN + xd : LLONG_MAX - xd;
            s64 b = sd ? LLONG_MIN + dd : LLONG_MAX - dd;
            if (b == 0) continue;
            if (a == LLONG_MIN && b == -1) continue;
            if (!reaches (a, b)) continue;
            printf ("  { "); pv (a); printf (", "); pv (b);
            printf (", "); pv (a % b); printf (" },\n");
            n++;
        }
  printf ("};\n#define NTV %d\n", n);
  fprintf (stderr, "%d boundary-reaching vectors\n", n);
  return 0;
}
