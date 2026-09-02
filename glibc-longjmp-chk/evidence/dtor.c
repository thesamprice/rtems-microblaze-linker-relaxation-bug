#include <stdio.h>
#include <stdlib.h>
static void at_exit_fn (void) { puts ("atexit handler ran"); }
__attribute__ ((constructor)) static void ctor (void) { puts ("constructor ran"); }
__attribute__ ((destructor)) static void dtor (void) { puts ("destructor ran"); }
int main (void) { atexit (at_exit_fn); puts ("main"); return 0; }
