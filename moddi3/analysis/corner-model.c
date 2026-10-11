/* Bit-exact host model of moddi3.S's loop, instrumented to report whether the
   internal states the review asks about are actually reached.

   Mirrors the assembly exactly: RES is 64 bits with no 65th bit, the carry out
   of RES_H is discarded, and the keep/skip decision is the SIGN BIT of the
   64-bit difference RES - D, which is what BLTi TRIAL_H tests.  */
#include <stdio.h>
#include <string.h>
#include <limits.h>
typedef unsigned long long u64;
typedef long long s64;

static struct {
  u64 calls, iters;
  u64 res_top_bit_set;      /* R_new >= 2^63: the signed-boundary case */
  u64 res_top_set_and_kept; /* ...and the subtraction was kept (q[i] = 1) */
  u64 carry_out_of_res;     /* would need a 65th bit -- must stay 0 */
  u64 d_is_2_63;            /* |divisor| == 2^63, i.e. LLONG_MIN */
  u64 d_ge_2_62;
  u64 signed_vs_borrow_differ;  /* sign-bit test != true unsigned compare */
  u64 wrong;
} st;

static s64 model (s64 a, s64 b) {
  u64 X, D, R = 0;
  int neg = a < 0, i, count = 64;
  st.calls++;
  if (a == 0) return 0;
  if (b == 0) return 0;
  X = neg ? -(u64) a : (u64) a;          /* RSUBI/RSUBIC: unsigned magnitude */
  D = b < 0 ? -(u64) b : (u64) b;
  if (D == (u64) 1 << 63) st.d_is_2_63++;
  if (D >= (u64) 1 << 62) st.d_ge_2_62++;
  if (!(X >> 63))                         /* BLTi OPX_H skips normalization */
    while (!(X >> 63)) { X <<= 1; count--; }
  for (i = 0; i < count; i++) {
      u64 top = X >> 63, prev = R;
      X <<= 1;
      if (prev >> 63) st.carry_out_of_res++;   /* carry lost out of RES_H */
      R = (R << 1) | top;
      st.iters++;
      if (R >> 63) st.res_top_bit_set++;
      {
        u64 t = R - D;                         /* RSUB/RSUBC, 64-bit wrap */
        int sign_says_keep = !(t >> 63);       /* BLTi TRIAL_H falls through */
        int borrow_says_keep = (R >= D);       /* the true unsigned compare */
        if (sign_says_keep != borrow_says_keep) st.signed_vs_borrow_differ++;
        if (sign_says_keep) {
          R = t;
          if (prev >> 63 || (R + D) >> 63) st.res_top_set_and_kept++;
        }
      }
  }
  return neg ? -(s64) R : (s64) R;
}

/* arith-rand-ll.c's generator, verbatim. */
static s64 simple_rand (void) {
  static u64 seed = 47114711;
  u64 this = seed * 1103515245 + 12345;
  seed = this;
  return this >> 8;
}
static u64 random_bitstring (void) {
  u64 x = 0; int n_bits, tot_bits = 0; s64 ran;
  for (;;) {
      ran = simple_rand ();
      n_bits = (ran >> 1) % 16;
      tot_bits += n_bits;
      if (n_bits == 0) return x;
      x <<= n_bits;
      if (ran & 1) x |= (1 << n_bits) - 1;
      if (tot_bits > 8 * (int) sizeof (long long) + 6) return x;
  }
}

static void report (const char *what) {
  printf ("%-34s calls %-7llu iters %-9llu\n", what, st.calls, st.iters);
  printf ("    R_new >= 2^63 (sign boundary)   %llu\n", st.res_top_bit_set);
  printf ("    ...and subtraction kept         %llu\n", st.res_top_set_and_kept);
  printf ("    |D| == 2^63 (LLONG_MIN divisor) %llu\n", st.d_is_2_63);
  printf ("    |D| >= 2^62                     %llu\n", st.d_ge_2_62);
  printf ("    carry lost out of RES_H         %llu  (must be 0)\n", st.carry_out_of_res);
  printf ("    sign test != unsigned compare   %llu  (must be 0)\n", st.signed_vs_borrow_differ);
  printf ("    wrong answers                   %llu\n\n", st.wrong);
  memset (&st, 0, sizeof st);
}

int main (void) {
  /* 1. The upstream torture test's own signed stream. */
  for (int i = 0; i < 10000; i++) {
      u64 x = random_bitstring (), y = random_bitstring ();
      s64 xx = x, yy = y;
      if (yy == 0) continue;
      if (xx == LLONG_MIN && yy == -1) continue;
      if (model (xx, yy) != xx % yy) st.wrong++;
  }
  report ("gcc.c-torture arith-rand-ll.c");

  /* 2. Targeted sweep of the divisors the review names, against dividends
        chosen to drive the partial remainder across 2^63. */
  {
    s64 ds[] = { LLONG_MIN, LLONG_MIN + 1, LLONG_MAX, LLONG_MAX - 1,
                 -LLONG_MAX, (s64) 1 << 62, ((s64) 1 << 62) + 1,
                 ((s64) 1 << 62) - 1, -((s64) 1 << 62), 3, -3 };
    for (unsigned di = 0; di < sizeof ds / sizeof ds[0]; di++)
      for (int k = 0; k < 4096; k++) {
          /* values hugging 2^63, 2^62 and the word boundary */
          s64 xs[] = { (s64) (((u64) 1 << 63) - k), (s64) (((u64) 1 << 63) + k),
                       (s64) (((u64) 1 << 62) - k), (s64) (((u64) 1 << 62) + k),
                       LLONG_MIN + k, LLONG_MAX - k,
                       (s64) (((u64) 1 << 32) + k), -(s64) k - 1 };
          for (unsigned xi = 0; xi < sizeof xs / sizeof xs[0]; xi++) {
              s64 a = xs[xi], b = ds[di];
              if (b == 0) continue;
              if (a == LLONG_MIN && b == -1) continue;
              if (model (a, b) != a % b) st.wrong++;
          }
      }
  }
  report ("targeted corner-case sweep");
  return 0;
}
