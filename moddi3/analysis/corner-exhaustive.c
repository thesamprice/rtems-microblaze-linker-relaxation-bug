/* Exhaustive sweep of the only corner where the partial remainder can cross
   2^63: both |X| and |D| within 4096 of 2^63.  Emits the pairs that actually
   reach R >= 2^63 so the real assembly can be run on them.  */
#include <stdio.h>
#include <limits.h>
typedef unsigned long long u64;
typedef long long s64;
static u64 cases, boundary_cases, boundary_iters, disagree, wrong, maxR;
static int reached;

static s64 model (s64 a, s64 b) {
  u64 X, D, R = 0; int neg = a < 0, count = 64;
  reached = 0;
  if (a == 0 || b == 0) return 0;
  X = neg ? -(u64) a : (u64) a;
  D = b < 0 ? -(u64) b : (u64) b;
  if (!(X >> 63)) while (!(X >> 63)) { X <<= 1; count--; }
  for (int i = 0; i < count; i++) {
      u64 top = X >> 63;
      X <<= 1;
      R = (R << 1) | top;
      if (R > maxR) maxR = R;
      if (R >> 63) { reached = 1; boundary_iters++; }
      { u64 t = R - D;
        int sign_keep = !(t >> 63), true_keep = (R >= D);
        if (sign_keep != true_keep) disagree++;
        if (sign_keep) R = t; }
  }
  return neg ? -(s64) R : (s64) R;
}

int main (void) {
  FILE *f = fopen ("corner-vectors.txt", "w");
  for (int xd = 0; xd < 4096; xd++)
    for (int dd = 0; dd < 4096; dd++)
      for (int sx = 0; sx < 2; sx++)
        for (int sd = 0; sd < 2; sd++) {
            /* 2^63 - k as a magnitude; LLONG_MIN is the k == 0, negative case */
            s64 a = sx ? LLONG_MIN + xd : LLONG_MAX - xd + 1 - 1;
            s64 b = sd ? LLONG_MIN + dd : LLONG_MAX - dd + 1 - 1;
            if (sx == 0) a = LLONG_MAX - xd;   /* +(2^63 - 1 - xd) */
            if (sd == 0) b = LLONG_MAX - dd;
            if (b == 0) continue;
            if (a == LLONG_MIN && b == -1) continue;
            cases++;
            s64 got = model (a, b);
            if (got != a % b) wrong++;
            if (reached) {
                boundary_cases++;
                if (boundary_cases <= 40)
                  fprintf (f, "%lld %lld %lld\n", a, b, a % b);
            }
        }
  fclose (f);
  printf ("exhaustive corner: |X| and |D| within 4096 of 2^63, all four signs\n");
  printf ("  cases                           %llu\n", cases);
  printf ("  max partial remainder           %#018llx\n", maxR);
  printf ("  cases reaching R >= 2^63        %llu\n", boundary_cases);
  printf ("  iterations with R >= 2^63       %llu\n", boundary_iters);
  printf ("  sign test != unsigned compare   %llu\n", disagree);
  printf ("  wrong answers                   %llu\n", wrong);
  return 0;
}
