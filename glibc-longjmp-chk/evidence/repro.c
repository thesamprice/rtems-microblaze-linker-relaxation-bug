#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
static jmp_buf b;
int main (void)
{
  if (setjmp (b) == 0)
    {
      puts ("calling longjmp");
      fflush (stdout);
      longjmp (b, 1);
      puts ("BUG: longjmp returned");
      return 1;
    }
  puts ("OK: setjmp returned nonzero after longjmp");
  return 0;
}
