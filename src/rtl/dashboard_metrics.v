`timescale 1ns/1ps
// Measured core time and completed-result rate; metadata published with the photo.
(* use_dsp="no" *) module dashboard_metrics #(parameter CLK_HZ=120000000)(
 input wire clk,rst_n,start,core_busy,write_ready,
 output wire busy,we,output wire [11:0] address,data,output reg complete);
 localparam TENTH_CYCLES=CLK_HZ/10000;
 localparam PHASE_BITS=TENTH_CYCLES<2?1:$clog2(TENTH_CYCLES);
 localparam IDLE=0,TIME_SETUP=1,DIVIDE=2,TIME_STORE=3,RATE_SETUP=4,
  RATE_STORE=5,DIGIT_SETUP=6,BCD=7,WRITE_TEXT=8,FINISH=9;
 (* DONT_TOUCH="TRUE" *)reg local_rst_n;
 always @(posedge clk)local_rst_n<=rst_n;
 reg [3:0]state;reg busy_d,seen_result,valid_rate;
 reg [31:0]core_cycles,period_ticks,saved_cycles,saved_period;
 reg [PHASE_BITS-1:0]phase;
 wire tick=phase==TENTH_CYCLES-1;
 reg [39:0]dividend,quotient;reg [31:0]divisor;reg [32:0]remainder;
 reg [5:0]bits_left;reg rate_division;
 wire [32:0]shifted={remainder[31:0],dividend[39]};
 wire subtract=shifted>={1'b0,divisor};
 reg [13:0]time_value,rate_value;
 reg field;reg [3:0]position;reg [15:0]binary,decimal,adjusted;
 reg [7:0]character;
 assign busy=state!=IDLE;assign we=state==WRITE_TEXT;
 assign address=12'd2400+(field?12'd8:12'd0)+position;
 assign data={4'd1,character};
 always @*begin
  adjusted=decimal;
  for(integer d=0;d<4;d=d+1)if(decimal[d*4+:4]>=5)adjusted[d*4+:4]=decimal[d*4+:4]+3;
  case(position)
   0:character=decimal[15:12]!=0?48+decimal[15:12]:32;
   1:character=decimal[15:8]!=0?48+decimal[11:8]:32;
   2:character=48+decimal[7:4];3:character=46;
   4:character=48+decimal[3:0];5:character=field?47:109;
   6:character=115;default:character=32;
  endcase
  if(field&&!valid_rate)begin
   case(position)
    0:character=32;1,2,4:character=45;3:character=46;
    5:character=47;6:character=115;default:character=32;
   endcase
  end
 end
 always @(posedge clk)begin
  if(!local_rst_n)begin
   phase<=0;busy_d<=0;core_cycles<=0;period_ticks<=0;seen_result<=0;
  end else begin
   busy_d<=core_busy;
   phase<=tick?0:phase+1'b1;
   if(core_busy)begin
    if(!busy_d)core_cycles<=1;
    else if(core_cycles!=32'hffffffff)core_cycles<=core_cycles+1'b1;
   end
   if(start&&!busy)begin period_ticks<=0;seen_result<=1;end
   else if(tick&&period_ticks!=32'hffffffff)period_ticks<=period_ticks+1'b1;
  end
 end
 always @(posedge clk)begin
  if(!local_rst_n)begin
   state<=IDLE;complete<=0;saved_cycles<=0;saved_period<=0;valid_rate<=0;
   dividend<=0;quotient<=0;divisor<=1;remainder<=0;bits_left<=0;rate_division<=0;
   time_value<=0;rate_value<=0;field<=0;position<=0;binary<=0;decimal<=0;
  end else begin
   complete<=0;
   case(state)
    IDLE:if(start)begin
     saved_cycles<=core_cycles;saved_period<=period_ticks;
     valid_rate<=seen_result&&period_ticks!=0;state<=TIME_SETUP;
    end
    TIME_SETUP:begin
     dividend<={8'd0,saved_cycles}+TENTH_CYCLES/2;divisor<=TENTH_CYCLES;
     quotient<=0;remainder<=0;bits_left<=39;rate_division<=0;state<=DIVIDE;
    end
    DIVIDE:begin
     dividend<=dividend<<1;quotient<={quotient[38:0],subtract};
     remainder<=subtract?shifted-{1'b0,divisor}:shifted;
     if(bits_left==0)state<=rate_division?RATE_STORE:TIME_STORE;else bits_left<=bits_left-1'b1;
    end
    TIME_STORE:begin time_value<=quotient>9999?14'd9999:quotient[13:0];state<=RATE_SETUP;end
    RATE_SETUP:begin
     if(valid_rate)begin
      dividend<=40'd100000+({8'd0,saved_period}>>1);divisor<=saved_period;
      quotient<=0;remainder<=0;bits_left<=39;rate_division<=1;state<=DIVIDE;
     end else begin rate_value<=0;field<=0;state<=DIGIT_SETUP;end
    end
    RATE_STORE:begin rate_value<=quotient>9999?14'd9999:quotient[13:0];field<=0;state<=DIGIT_SETUP;end
    DIGIT_SETUP:begin binary<=field?{2'd0,rate_value}:{2'd0,time_value};decimal<=0;bits_left<=15;position<=0;state<=BCD;end
    BCD:begin
     decimal<={adjusted[14:0],binary[15]};binary<=binary<<1;
     if(bits_left==0)state<=WRITE_TEXT;else bits_left<=bits_left-1'b1;
    end
    WRITE_TEXT:if(write_ready)begin
     if(position==7)begin
      if(field)state<=FINISH;else begin field<=1;state<=DIGIT_SETUP;end
     end else position<=position+1'b1;
    end
    FINISH:begin complete<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
