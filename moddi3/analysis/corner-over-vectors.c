/* Run the model over the harness's own 4701 vectors and report which of the
   corner states they reach.  */
#include <stdio.h>
#include <limits.h>
typedef unsigned long long u64; typedef long long s64;
#include "vectors.h"
static u64 iters, boundary, d_2_63, d_ge_2_62, viol, disagree, wrong, maxR;
static int hit;
static s64 model (s64 a, s64 b) {
  u64 X, D, R = 0; int neg = a < 0, count = 64; hit = 0;
  if (a == 0 || b == 0) return 0;
  X = neg ? -(u64) a : (u64) a;
  D = b < 0 ? -(u64) b : (u64) b;
  if (D == (u64) 1 << 63) d_2_63++;
  if (D >= (u64) 1 << 62) d_ge_2_62++;
  if (!(X >> 63)) while (!(X >> 63)) { X <<= 1; count--; }
  for (int i = 0; i < count; i++) {
      u64 Rold = R, top = X >> 63;
      if (Rold >= D) viol++;
      X <<= 1; R = (R << 1) | top; iters++;
      if (R > maxR) maxR = R;
      if (R >> 63) { boundary++; hit = 1; }
      { u64 t = R - D;
        int sk = !(t >> 63), tk = (R >= D);
        if (sk != tk) disagree++;
        if (sk) R = t; }
  }
  return neg ? -(s64) R : (s64) R;
}
int main (void) {
  u64 boundary_cases = 0;
  for (int i = 0; i < NTV; i++) {
      if (model (tv[i].a, tv[i].b) != tv[i].r) wrong++;
      if (hit) boundary_cases++;
  }
  printf ("harness's own %d vectors\n", NTV);
  printf ("  iterations                      %llu\n", iters);
  printf ("  max partial remainder           %#018llx\n", maxR);
  printf ("  iterations with R >= 2^63       %llu\n", boundary);
  printf ("  vectors reaching R >= 2^63      %llu\n", boundary_cases);
  printf ("  |D| == 2^63 (LLONG_MIN divisor) %llu\n", d_2_63);
  printf ("  |D| >= 2^62                     %llu\n", d_ge_2_62);
  printf ("  invariant R_old < D violated    %llu\n", viol);
  printf ("  sign test != unsigned compare   %llu\n", disagree);
  printf ("  wrong answers                   %llu\n", wrong);
  return 0;
}
