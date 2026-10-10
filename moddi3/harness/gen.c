/* Host side: emit the test vectors with expected results computed by the host's
   (correct) 64-bit modulo.  The target compares against these.  */
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
static void pv (long long x) {
  /* LLONG_MIN has no literal form; write it as (-MAX - 1).  */
  if (x == LLONG_MIN) printf ("(-9223372036854775807LL - 1)");
  else printf ("%lldLL", x);
}
static void emit (long long a, long long b, long long r) {
  printf ("  { "); pv (a); printf (", "); pv (b); printf (", "); pv (r);
  printf (" },\n");
}
int main (void) {
  long long v[] = { 0, 1, -1, 2, -2, 3, -3, 7, -7, 10, -10, 100, -100,
                    0x7fffffff, -0x7fffffff, 0x80000000LL, -0x80000000LL,
                    0x100000000LL, -0x100000000LL, 0x123456789abcLL,
                    -0x123456789abcLL, LLONG_MAX, LLONG_MIN, LLONG_MAX-1,
                    LLONG_MIN+1, 0x5555555555555555LL, -0x5555555555555555LL };
  int n = sizeof v / sizeof v[0];
  printf ("/* generated - do not edit */\n");
  printf ("struct tv { long long a, b, r; };\n");
  printf ("static const struct tv tv[] = {\n");
  int count = 0;
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) {
      if (v[j] == 0) continue;                 /* div by zero is undefined */
      if (v[i] == LLONG_MIN && v[j] == -1) continue;  /* overflow, undefined */
      emit (v[i], v[j], v[i] % v[j]);
      count++;
    }
  srand (20260927);
  for (int k = 0; k < 4000; k++) {
    long long a = ((long long) rand () << 40) ^ ((long long) rand () << 20) ^ rand ();
    long long b = ((long long) rand () << 33) ^ ((long long) rand () << 11) ^ rand ();
    if (k & 1) a = -a;
    if (k & 2) b = -b;
    if (b == 0) continue;
    if (a == LLONG_MIN && b == -1) continue;
    emit (a, b, a % b);
    count++;
  }
  printf ("};\n#define NTV %d\n", count);
  fprintf (stderr, "%d vectors\n", count);
  return 0;
}
