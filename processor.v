//System Level Stuff (word sizes, memory sizes, etc.)
`define WORD  [15:0]
`define REGSIZE [15:0]
`define MEMSIZE [65535:0]
`define PRESIZE [11:0]
`define REG [3:0]

//Instruction Encoding (format of AIK generated assembly code)
`define Opcode [15:11]
`define CC [10:9]
`define AL 2'b00
`define S   2'b01
`define EQ 2'b10
`define NE 2'b11
`define isReg [8]
`define Dest  [7:4]
`define Op2 [3:0]

//OPcodes w/ matching State #s
`define OPadd 5'b00000
`define OPand 5'b00010
`define OPbic 5'b00011
`define OPeor 5'b00100
`define OPldr 5'b00111
`define OPmov 5'b01000
`define OPmul 5'b01001
`define OPneg 5'b01011
`define OPorr 5'b01100
`define OPsha 5'b01110
`define OPstr 5'b01111
`define OPslt 5'b10000
`define OPsub 5'b10001
`define OPsys 5'b10011
`define OPpre 2'b11
`define OPaddf 5'b00001  //not implemented yet
`define OPsubf 5'b10010  //not implemented yet
`define OPitof 5'b00110
`define OPftoi 5'b00101
`define OPmulf 5'b01010
`define OPrecf 5'b01101  //low accuracy

//NOP instruction. First bit is 1 to distinguish it from all x's
`define NOP 16'b1xxxxxxxxxxxxxxx

module processor(halt, reset, clk);
    output reg halt;
    input reset, clk;

    reg `WORD regfile `REGSIZE;
    reg `WORD datamem `MEMSIZE;     //instantiate data memory
    reg `WORD instrmem `MEMSIZE;    //instantiate instruction memory
    reg[7:0] reclookup [127:0];	    //lookup table for reciprocals
    reg init;
    reg frz;
    reg Zflag;
    reg PREflag; 		//is PRE set?
    reg `PRESIZE PREval; 	//PRE val
    reg regWrite; 		//do we write to reg?

    always @(reset) begin
        halt = 0;
        init = 1;
        frz = 0;
        Zflag = 0;
        PC_in0 = 0;
        PREval = 0;
        PREflag = 0;
        $readmemh0(instrmem);          
        $readmemh1(regfile);               
        $readmemh2(datamem);          
        $readmemh3(reclookup);        
    end
           
        reg `WORD ir_in0, ir_in1, ir_in2, ir_inF, ir_in3;
        reg `WORD PC_in0, PC_in1, PC_in2, PC_inF, PC_in3;
        reg `WORD outputVal; //write output to ALU or MEM
        reg `WORD op1, op2;
	reg `WORD op1_prev, op2_prev; //used for the float stage
        reg `WORD op2_prev_opp, op2_opp; //just in case... used for itof

        //Used for counting lead zeroes; leadzeroes2 used for mulf
        reg[7:0] s8;
        reg[3:0] s4;
        reg[1:0] s2;
        reg[4:0] leadzeroes, leadzeroes2;

        //Used for ftoi
        reg `WORD shift, mantissa;

        //Used for mulf
        reg[15:0]  bigmantissa;
       
/*
Stage 0 (owns PC)
-Determine value of PC
-Set the Z flag
-Write to regfile
*/
    always @(posedge clk) begin
      //reg write
      if ((!init) && regWrite && !(ir_in0 `Dest == 4'b1111)) regfile[ir_in0 `Dest] = outputVal;

      //set Z-flag
      if ((ir_in0 `CC == `S) && (ir_in0[15:14]!=2'b11) && (!init)) Zflag = !outputVal;

      //process jmps
      if(ir_in0 `Dest == 4'b1111 && ir_in0[15:14]!=2'b11) begin
          PC_in0 <= outputVal+1;
          PC_in1 <= outputVal;
          regfile[15] <=outputVal;
          frz<=0;
      end else if(!frz) begin    //processing regular instrs that aren't jpms
          PC_in0 <= PC_in0 + 1;
          PC_in1 <= PC_in0;
          if(PC_in3===16'bxxxxxxxxxxxxxxxx) begin
             regfile[15]<=0;    
          end else begin
             regfile[15] <= PC_in3+1; //set the pc
          end
      end
    end

/*
Stage 1
-fetch an instruction from memory
-set PREval
-handle dependencies
-checks conditionals for EQ and NE
*/

    always @(posedge clk) begin
  
      //set PRE val
      if (instrmem[PC_in1-frz][15:14] == 2'b11) begin
          PREval<=instrmem[PC_in1-frz][11:0];
           frz <= 0; 
           if( !((instrmem[PC_in1-frz] `CC == `EQ && Zflag==0) || (instrmem[PC_in1-frz] `CC == `NE && Zflag==1))) begin
              ir_in2 <= instrmem[PC_in1-frz];
              PC_in2 <= PC_in1;
           end

      end else if (ir_in0 `Dest == 4'b1111) begin
            #0;	 //do nothing. this is neccessary because it gets confused with the 2'b11 in the PRE instruction

      //check for dependencies. send set frz flag and send nops until resolved
      end else if ((ir_in3 `Dest == 4'b1111) ||
          (ir_in2 `Dest == 4'b1111) || 
          (ir_in0 `Dest == 4'b1111) || 
          (ir_inF `Dest == 4'b1111) ||
          ((instrmem[PC_in1-frz] `isReg) && (instrmem[PC_in1-frz] `Op2 == ir_in3 `Dest)) || 
          ((instrmem[PC_in1-frz] `isReg) && (instrmem[PC_in1-frz] `Op2 == ir_in2 `Dest)) || 
          ((instrmem[PC_in1-frz] `isReg) && (instrmem[PC_in1-frz] `Op2 == ir_in0 `Dest)) || 
          ((instrmem[PC_in1-frz] `isReg) && (instrmem[PC_in1-frz] `Op2 == ir_inF `Dest)) ||
          (instrmem[PC_in1-frz] `Dest == ir_in3 `Dest) ||
          (instrmem[PC_in1-frz] `Dest == ir_in2 `Dest) ||
          (instrmem[PC_in1-frz] `Dest == ir_in0 `Dest) ||
          (instrmem[PC_in1-frz] `Dest == ir_inF `Dest) ||
          (ir_in0 `CC == `S) || (ir_in2 `CC == `S) || (ir_in3 `CC == `S) || (ir_inF `CC == `S) ||
          ((instrmem[PC_in1-frz] == `OPldr) && ((ir_in0 `Opcode  == `OPstr) || (ir_in2 `Opcode  == `OPstr) || (ir_inF `Opcode  == `OPstr) || (ir_in3 `Opcode  == `OPstr))) ||
          ((instrmem[PC_in1-frz] == `OPstr) && ((ir_in0 `Opcode  == `OPldr) || (ir_in2 `Opcode  == `OPldr) || (ir_inF `Opcode  == `OPldr) || (ir_in3 `Opcode  == `OPldr)))) begin
          ir_in2 <= `NOP;
          frz <= 1; 

      //do nothing if conditional EQ or NE instruction and Z-flag does not match
      end else begin 
          frz <= 0; 
          if( !((instrmem[PC_in1-frz] `CC == `EQ && Zflag==0) || (instrmem[PC_in1-frz] `CC == `NE && Zflag==1))) begin
              ir_in2 <= instrmem[PC_in1-frz];
              PC_in2 <= PC_in1;
          end
      end
    end

/*
Stage 2
-decode the instruction
-sign extension
-read from reg files
-store negation for itof, just in case
*/
  always @(posedge clk) begin

       if(ir_in2[15:14] ==`OPpre) PREflag<=1;

       op1_prev <= regfile[ir_in2 `Dest];

	//Op2 is reg
        if (ir_in2 `isReg == 1) begin
          op2_prev <= regfile[ir_in2 `Op2];
          op2_prev_opp <= -regfile[ir_in2 `Op2];

	//Op2 is long immed
        end else if (PREflag && (ir_in2!=`NOP)) begin
          op2_prev <= {PREval, ir_in2 `Op2};
          op2_prev_opp <= -{PREval, ir_in2 `Op2};
          PREflag <=0;

	//Op2 is short immed
        end else begin
          op2_prev <= {{12{ir_in2[3]}}, ir_in2 `Op2};
          op2_prev_opp <= -{{12{ir_in2[3]}}, ir_in2 `Op2};
        end
    
      ir_inF <= ir_in2;
      PC_inF <= PC_in2;
  end

/*
Stage 2.5
-setup for floats
-all other instrs just chill
*/
  always @(posedge clk) begin

      //count lead zeroes
      if(ir_inF `Opcode == `OPitof) begin
          if(op2_prev[15:0] == 0) begin
            leadzeroes=5'b1000;
          end else if (op2_prev[15]==0) begin
            leadzeroes[4] =0;
            {leadzeroes[3],s8} = ((|op2_prev[15:8]) ? {1'b0, op2_prev[15:8]} : {1'b1, op2_prev[7:0]});
            {leadzeroes[2],s4} = ((|s8[7:4]) ? {1'b0, s8[7:4]} : {1'b1, s8[3:0]});
            {leadzeroes[1],s2} = ((|s4[3:2]) ? {1'b0, s4[3:2]} : {1'b1, s4[1:0]});
             leadzeroes[0] <= !s2[1];
          end else if (op2_prev[15]==1) begin
            leadzeroes[4] =0;
            {leadzeroes[3],s8} = ((|op2_prev_opp[15:8]) ? {1'b0, op2_prev_opp[15:8]} : {1'b1, op2_prev_opp[7:0]});
            {leadzeroes[2],s4} = ((|s8[7:4]) ? {1'b0, s8[7:4]} : {1'b1, s8[3:0]});
            {leadzeroes[1],s2} = ((|s4[3:2]) ? {1'b0, s4[3:2]} : {1'b1, s4[1:0]});
             leadzeroes[0] <= !s2[1];
          end
      end
 
      //store mantissa and exp
      if(ir_inF `Opcode == `OPftoi) begin
             mantissa <= {1'b1, op2_prev[6:0]};
             shift <= (op2_prev[14:7] - 134);
      end

      //store mantiss and exp; count lead zeroes
      if(ir_inF `Opcode == `OPmulf) begin
             bigmantissa = {1'b1, op2_prev[6:0]} * {1'b1, op1_prev[6:0]};
             shift <= (op2_prev[14:7] - 134) + (op1_prev[14:7] - 134);
             leadzeroes[4] =0;
             {leadzeroes[3],s8} = ((|bigmantissa[15:8]) ? {1'b0, bigmantissa[15:8]} : {1'b1, bigmantissa[7:0]});
             {leadzeroes[2],s4} = ((|s8[7:4]) ? {1'b0, s8[7:4]} : {1'b1, s8[3:0]});
             {leadzeroes[1],s2} = ((|s4[3:2]) ? {1'b0, s4[3:2]} : {1'b1, s4[1:0]});
             leadzeroes[0] = !s2[1];
      end

      //store mantissa and exp; count lead zeroes
      if(ir_inF `Opcode == `OPrecf) begin
             mantissa = reclookup[op2_prev[6:0]];
             shift <= ((op2_prev[6:0]==0) ? (121) : (120));
             leadzeroes[4] =0;
             leadzeroes[3] =0;
             {leadzeroes[2],s4} = ((|mantissa[7:4]) ? {1'b0, mantissa[7:4]} : {1'b1, mantissa[3:0]});
             {leadzeroes[1],s2} = ((|s4[3:2]) ? {1'b0, s4[3:2]} : {1'b1, s4[1:0]});
             leadzeroes[0] = !s2[1];
             
      end

      //one step delay for nonfloats
      op1 <= op1_prev;
      op2 <= op2_prev;  
      op2_opp <= op2_prev_opp;
      ir_in3 <= ir_inF;
      PC_in3 <= PC_inF;
  end     

/*
Stage 3
-ALU
-float ALU
-compute output
*/
  always @(posedge clk) begin
    //if statement to check for first time around
    if(ir_in3 === 16'bxxxxxxxxxxxxxxxx || ir_in3 === 16'b1xxxxxxxxxxxxxxx || ir_in3 [15:14] == `OPpre) begin #0; end 
    else begin case (ir_in3 `Opcode) 
        `OPadd: begin outputVal<=op1+op2; regWrite<=1; end
        `OPsub: begin outputVal<=op1-op2; regWrite<=1; end
        `OPmul: begin outputVal<=op1*op2; regWrite<=1; end
        `OPand: begin outputVal<=op1&op2; regWrite<=1; end
        `OPorr: begin outputVal<=op1|op2; regWrite<=1; end
        `OPeor: begin outputVal<=op1^op2; regWrite<=1; end
        `OPbic: begin outputVal<=op1&~op2; regWrite<=1; end
        `OPslt: begin outputVal<=op1<op2; regWrite<=1; end
        `OPmov: begin outputVal<=op2; regWrite<=1; end
        `OPneg: begin outputVal<=-1*op2; regWrite<=1; end
        `OPsha: begin outputVal<=((op2>0) ? (op1 << op2) : (op1 >> -1*op2)); regWrite<=1; end
        `OPstr: begin datamem[op2] <= regfile[ir_in3 `Dest]; regWrite<=0; end
        `OPldr: begin outputVal<=datamem[op2]; regWrite<=1; end

	//conversion from integer to float based on whether value is 0, positive, or negative
        `OPitof: begin 
            regWrite<=1; 
            if(op2==0) begin
                outputVal<=0;
            end else if (op2[15]==0) begin
              outputVal[15] <= op2[15];
              outputVal[14:7] <= (142 - leadzeroes); // 8 - leadzeroes + 7 + 127
              outputVal[6:0] <= ((leadzeroes>8) ? (op2<<(leadzeroes-8)) : (op2 >> (8-leadzeroes))); 
            end else begin  //for neg values
              outputVal[15] <= op2[15];
              outputVal[14:7] <= (142 - leadzeroes); // 8 - leadzeroes + 7 + 127
              outputVal[6:0] <= ((leadzeroes>8) ? (op2_opp<<(leadzeroes-8)) : (op2_opp >> (8-leadzeroes))); 
            end
         end

	//conversion from float to int
        `OPftoi: begin
            if(op2==0) begin
                outputVal<=0;
            end else begin
              outputVal[15] <= op2[15];
              if(op2[15]==0) begin
                outputVal[14:0] <= ((shift[7]==0) ? (mantissa << shift) : (mantissa >> -shift));
              end else begin
                outputVal[14:0] <= ((shift[7]==0) ? (-mantissa << shift) : (-mantissa >> -shift));
              end
            end
         end  

	//float multiplication
        `OPmulf: begin 
             if(bigmantissa==0) begin
                outputVal<=0;
             end else begin
                 outputVal[6:0] <= bigmantissa >> (8-leadzeroes);
                 outputVal[14:7] <= shift + (8 - leadzeroes +134);
                 outputVal[15] <= op1[15]^op2[15];
             end
         end 

	//float reciprocal
         `OPrecf: begin 
              if(op2==0) begin
                 outputVal<=0;
              end else begin
                 outputVal[15] <= op2[15];
                 outputVal[14:7] <= shift - leadzeroes;
                 outputVal[6:0] <= mantissa << (leadzeroes - 1);
              end
           end

        default: begin halt<=1; end	//catchall
    endcase
    end       

    //when the first instr gets here, init is set to 0
    if(ir_in3 !== 16'bxxxxxxxxxxxxxxxx && init==1) init<=0;
          
    //avoid infinite loops
    if(ir_in3 === 16'bxxxxxxxxxxxxxxxx && init==0 && frz==0) begin
      halt<=1;
    end

    //avoid infinite loops
    if(PC_in0==2000) begin
      halt<=1;
    end
    
    ir_in0 <= ir_in3;
  end
endmodule

module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted,reset,clk);
initial begin
    $dumpfile;                                
    $dumpvars(0,PE);                    
    $dumpvars(0, PE, PE.regfile[0],PE.regfile[1],PE.regfile[2], PE.regfile[3]);      
    #10 reset = 1;
    #10 reset = 0;
    while (!halted) begin
        #10 clk = 1;
        #10 clk = 0;
    end
    $finish;
end
endmodule
