ENTRY(_start)
MEMORY { ram : ORIGIN = 0x90000000, LENGTH = 64M }
SECTIONS {
  .vectors 0x90000000 : { *(.vectors) } > ram
  .text : { *(.text*) } > ram
  .rodata : { *(.rodata*) *(.gcc_except_table*) } > ram
  .data : { *(.data*) *(.sdata*) *(.eh_frame*) } > ram
  . = ALIGN(4);
  __bss_start = .;
  .bss : { *(.bss*) *(.sbss*) *(COMMON) } > ram
  . = ALIGN(4);
  __bss_end = .;
  . = ALIGN(16);
  _stack_top = . + 0x400000;
  _heap_start = _stack_top + 0x10;
}
