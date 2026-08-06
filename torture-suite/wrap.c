/* Wraps a gcc.c-torture/execute test as an RTEMS application.
   The test is compiled with -Dmain=torture_main.  A clean return means the
   test passed; abort() means it failed, which RTEMS turns into a fatal.  */
#include <rtems.h>
#include <rtems/bspIo.h>
#include <stdlib.h>

extern int torture_main (void);

rtems_task Init (rtems_task_argument arg)
{
  (void) arg;
  torture_main ();
  printk ("\nTORTURE-PASS\n");
  rtems_shutdown_executive (0);
}

#define CONFIGURE_APPLICATION_NEEDS_SIMPLE_CONSOLE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 4
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT_TASK_STACK_SIZE (64u * 1024u)
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
