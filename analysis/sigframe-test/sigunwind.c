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

/* a captured return/interrupt address belongs to fn if it lands in a small
   window at or after fn's entry; the marker functions are tiny and noinline */
#define FN_WINDOW 0x800
static int in_fn (void *ip, void *fn)
{
  unsigned long a = (unsigned long) ip, b = (unsigned long) fn;
  return a >= b && a < b + FN_WINDOW;
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

  int found = 0, last = -1, ordered = 1;
  for (int w = 0; w < nwant; w++)
    {
      int at = -1;
      for (int i = 0; i < nframes; i++)
	if (in_fn (frames[i], want[w])) { at = i; break; }
      if (at >= 0) { found++; if (at < last) ordered = 0; last = at; }
      printf ("  expect %-6s : %s\n", wname[w], at >= 0 ? "present" : "MISSING");
    }

  if (found == nwant && ordered)
    printf ("RESULT: PASS -- unwound through the signal frame, all %d interrupted frames in order\n", nwant);
  else
    printf ("RESULT: FAIL -- %d/%d interrupted frames recovered%s (signal-frame unwinder wrong for this libc/kernel)\n",
	    found, nwant, ordered ? "" : ", out of order");
  poweroff_or_exit (found == nwant && ordered ? 0 : 1);
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
