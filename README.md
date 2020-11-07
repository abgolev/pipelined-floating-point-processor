# pipelined-floating-point-processor
Verilog implementation of a five-stage floating point pipelined processor based on the PinKY instruction set. 

To run on terminal shell, enter instructions in vmem0.vmem and then:
> iverilog shellproc.v

> ./a.out

To run testing mode on a number of different prebuilt instructions:
> ./test.sh

Description:
The PinKY assembly language is a simple architecture with a variety of similarities to ARM that was built by Prof. Hank Dietz specifically for use by the University of Kentucky’s EE480 courses. A detailed description of PinKY can be found here: http://aggregate.org/EE480/pinky.html

To use this processor, first, a basic PinKY program has to be written and then assembled using the AIK assembler. The AIK assembler can be found here: http://super.ece.engr.uky.edu:8088/cgi-bin/aik.cgi

The  instructions are placed in VMEM0. VMEM1 holds the 16 registers and is instantiated as an array of 0's. VMEM2 holds the main memory and is also instantiated as an array of 0's. VMEM3 is a reciprocal lookup table used for the recf function. 

The line $dumpvars(0,PE,PE.regfile[...]) in the testbench can be used used to print the contents of any of the registers.

The processor can be tested using the Icarus Verilog Simulator CGI Interface:
http://super.ece.engr.uky.edu:8088/cgi-bin/iver.cgi

Known Bugs:
1. The reciprocal function isn't accurate for most values
2. The final instruction of the program must be a system call
