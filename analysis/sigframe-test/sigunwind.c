/* sigunwind.c -- validate the MicroBlaze libgcc signal-frame unwinder.
 *
 * A fault (or SIGALRM with -DMODE_ALRM) is raised from deep in a known call
 * chain; from the handler we run _Unwind_Backtrace and check that unwinding
 * steps THROUGH the signal frame back into the interrupted functions.
 *
 * This is the direct test for libgcc/config/microblaze/linux-unwind.h and for
 * gcc patch 0001.  On a target where the sigcontext is located correctly for
 * this C library and this kernel, the backtrace reaches main(); if the offset
 * is wrong -- Ramin's upstream "uc = pc - sizeof(ucontext_t)" arithmetic under
 * glibc, or the kernel's signal-frame arg-save reserve shifting &siginfo away
 * from the handler's SP -- unwinding stops at the handler and the interrupted
 * frames are MISSING.
 *
 * Build (with the PATCHED cross toolchain):
 *   microblazeel-linux-gnu-gcc -O1 -g -static -fasynchronous-unwind-tables \
 *       sigunwind.c -o sigunwind
 * -static pulls in the patched static libgcc unwinder.  For the shared libgcc_s
 * instead, drop -static and put the patched libgcc_s.so.1 on the target.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <unwind.h>
#include <unistd.h>
#include <sys/reboot.h>

/* non-static so their addresses are real and not inlined away */
void leaf(void);
void mid(void);
void outer(void);

static void *want[8];
static const char *wname[8];
static int nwant;
#define MARK(fn) do { want[nwant] = (void *)(fn); wname[nwant] = #fn; nwant++; } while (0)

static void *frames[64];
static int nframes;
static volatile int sink;

static _Unwind_Reason_Code trace_cb(struct _Unwind_Context *ctx, void *arg)
{
  (void) arg;
  if (nframes < 64)
    frames[nframes++] = (void *) _Unwind_GetIP (ctx);
  return _URC_NO_REASON;
}

/* Identify which marker a captured address belongs to: the marker with the
   greatest entry <= ip, provided ip is within FN_WINDOW of it.  Using the
   closest preceding marker (rather than "within a window of each") stops the
   small, adjacent marker functions from all matching one address.  Returns the
   marker index, or -1.  */
#define FN_WINDOW 0x400
static int marker_of (void *ip)
{
  unsigned long a = (unsigned long) ip;
  int best = -1;
  unsigned long best_start = 0;
  for (int w = 0; w < nwant; w++)
    {
      unsigned long b = (unsigned long) want[w];
      if (a >= b && a - b < FN_WINDOW && (best < 0 || b > best_start))
	{ best = w; best_start = b; }
    }
  return best;
}

static void poweroff_or_exit (int code)
{
  fflush (NULL);
  sync ();
  /* if we are PID 1 in an initramfs, power the machine off so qemu exits */
  reboot (code == 0 ? RB_POWER_OFF : RB_POWER_OFF);
  _exit (code);
}

static void handler (int sig)
{
  (void) sig;
  nframes = 0;
  _Unwind_Backtrace (trace_cb, NULL);

  printf ("captured %d frames:\n", nframes);
  for (int i = 0; i < nframes; i++)
    printf ("  #%-2d ip=%p\n", i, frames[i]);

  printf ("markers: ");
  for (int w = 0; w < nwant; w++)
    printf ("%s=%p ", wname[w], want[w]);
  printf ("\n");

  /* label each captured frame with the marker it lands in (or -1) */
  printf ("frame markers:");
  for (int i = 0; i < nframes; i++)
    { int m = marker_of (frames[i]); printf (" %s", m >= 0 ? wname[m] : "."); }
  printf ("\n");

  /* the markers must appear as an ordered subsequence in distinct frames:
     leaf, then mid, then outer, then main, each in a later frame */
  int fi = 0, found = 0;
  for (int w = 0; w < nwant; w++)
    {
      while (fi < nframes && marker_of (frames[fi]) != w)
	fi++;
      if (fi < nframes) { found++; fi++; printf ("  %-6s : frame %d\n", wname[w], fi - 1); }
      else              { printf ("  %-6s : MISSING\n", wname[w]); }
    }

  if (found == nwant)
    printf ("RESULT: PASS -- unwound through the signal frame, all %d interrupted frames in order\n", nwant);
  else
    printf ("RESULT: FAIL -- only %d/%d interrupted frames recovered (unwinder stopped early: %d frames total; signal-frame offset wrong for this libc/kernel)\n",
	    found, nwant, nframes);
  poweroff_or_exit (found == nwant ? 0 : 1);
}

void leaf (void)
{
#ifdef MODE_ALRM
  raise (SIGALRM);           /* interrupted PC lands in raise(); leaf is its caller */
#else
  *(volatile int *) 0 = 1;   /* SIGSEGV: interrupted PC lands inside leaf itself */
#endif
  sink++;                    /* keep leaf off a tail-call position */
}
void mid (void)   { leaf ();  sink++; }
void outer (void) { mid ();   sink++; }

int main (void)
{
  MARK (leaf); MARK (mid); MARK (outer); MARK (main);

  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = handler;
  sigaction (SIGSEGV, &sa, NULL);
  sigaction (SIGALRM, &sa, NULL);

  outer ();
  printf ("RESULT: FAIL -- handler never ran\n");
  poweroff_or_exit (2);
  return 2;
}
