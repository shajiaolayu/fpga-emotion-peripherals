`timescale 1ns/1ps
// Toggle switches only. Initial positions establish a baseline without an
// unintended shutter/reset event. Both directions of a stable flip trigger.
module photo_controls #(parameter CLK_HZ=50000000,DEBOUNCE_MS=20)(
 input wire clk,rst_n,sw0,sw1,
 output wire manual_mode,output reg shutter);
 (* ASYNC_REG="TRUE" *)reg [1:0] switch_meta,switch_sync;
 reg [1:0] stable,candidate;
 reg initialized;
 localparam DEBOUNCE_TICKS=CLK_HZ/1000*DEBOUNCE_MS;
 localparam DEBOUNCE_BITS=(DEBOUNCE_TICKS<2)?1:$clog2(DEBOUNCE_TICKS+1);
 reg [DEBOUNCE_BITS-1:0] debounce_count;
 assign manual_mode=stable[0];
 always @(posedge clk)begin
   if(!rst_n)begin
     switch_meta<=0;switch_sync<=0;stable<=0;candidate<=0;
     initialized<=0;debounce_count<=0;shutter<=0;
   end else begin
     switch_meta<={sw1,sw0};switch_sync<=switch_meta;shutter<=0;
     if(switch_sync!=candidate)begin candidate<=switch_sync;debounce_count<=0;end
     else if(debounce_count<DEBOUNCE_TICKS)debounce_count<=debounce_count+1'b1;
     else if(!initialized)begin stable<=candidate;initialized<=1;end
     else if(stable!=candidate)begin
       stable<=candidate;
       if(stable[1]!=candidate[1])shutter<=1;
     end
   end
 end
endmodule
