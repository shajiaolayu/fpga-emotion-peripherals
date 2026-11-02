`timescale 1ns/1ps
// SIMULATION TEST DOUBLE ONLY. These scores are fabricated test stimuli, not inference.
// Both guards deliberately prevent using this module as a hardware implementation.
module inference_core #(parameter SIM_MAC=0)(
 input wire clk,rst_n,load_en,input wire [11:0]load_addr,input wire [7:0]load_data,
 input wire start,output reg busy,done,output reg [223:0]scores,output reg [2:0]prediction,
 output wire trace_valid,output wire [5:0]trace_op,output wire [16:0]trace_addr,output wire [31:0]trace_value);
`ifndef PUBLIC_PERIPHERAL_TEST
 PRIVATE_CORE_REQUIRED__TEST_DOUBLE_IS_NOT_A_CORE missing_public_test_define();
`endif
`ifdef SYNTHESIS
 PRIVATE_CORE_REQUIRED__TEST_DOUBLE_MUST_NOT_BE_SYNTHESIZED synthesis_forbidden();
`endif
 reg [7:0] image0[0:2303],image1[0:2303];
 integer loaded,timer,i;reg [1:0]candidates;reg tag;
 initial begin $readmemh("gray0.mem",image0);$readmemh("gray1.mem",image1);end
 assign trace_valid=0;assign trace_op=0;assign trace_addr=0;assign trace_value=0;
 always @(posedge clk)begin
  if(!rst_n)begin busy<=0;done<=0;scores<=0;prediction<=7;loaded<=0;timer<=0;candidates<=3;tag<=0;end
  else begin
   done<=0;
   if(load_en)begin
    if(busy||load_addr!==loaded||loaded>=2304)$fatal(1,"invalid peripheral load ordering");
    candidates<=candidates&{load_data===image1[loaded],load_data===image0[loaded]};loaded<=loaded+1;
   end
   if(start)begin
    if(busy||loaded!=2304||(candidates!=1&&candidates!=2))$fatal(1,"incomplete or mixed synthetic frame");
    tag<=candidates==2;busy<=1;timer<=64;
   end
   if(busy)begin
    if(timer==0)begin
     for(i=0;i<7;i=i+1)scores[i*32+:32]<=tag?(1024-i*256):(i*256-1024);
     prediction<=tag?0:6;busy<=0;done<=1;loaded<=0;candidates<=3;
    end else timer<=timer-1;
   end
  end
 end
endmodule
