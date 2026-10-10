ENTRY(_start)
MEMORY { ram : ORIGIN = 0x90000000, LENGTH = 32M }
SECTIONS {
  .vectors 0x90000000 : { *(.vectors) } > ram
  .text : { *(.text*) } > ram
  .rodata : { *(.rodata*) } > ram
  .data : { *(.data*) } > ram
  .bss : { *(.bss*) *(COMMON) } > ram
  . = ALIGN(16);
  _stack_top = . + 0x10000;
}
