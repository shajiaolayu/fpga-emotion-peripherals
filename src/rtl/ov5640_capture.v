`timescale 1ns/1ps
module ov5640_capture(
 input wire clk,pclk,arst_n,vsync,href,input wire [7:0] data,
 output wire sof,eof,frame_ok,pv,output wire [15:0] pixel,
 output wire [9:0] x,y,output wire overflow_fault,
 output reg frame_error,output reg [31:0] frames_read);
 wire wrst_n,rrst_n;
 reset_sync camera_reset(pclk,arst_n,wrst_n);
 reset_sync reader_reset(clk,arst_n,rrst_n);
 wire cs,ce,co,cv;wire [15:0] cp;wire [9:0] cx,cy;
 wire [31:0] good,bad;
 dvp_rgb565_rx receiver(pclk,wrst_n,vsync,href,data,
  cs,ce,co,cv,cp,cx,cy,good,bad);
 wire [39:0] q;wire valid,empty,full,overflow;
 async_event_fifo events(pclk,wrst_n,cs||ce||cv,{cs,ce,co,cv,cx,cy,cp},
  full,overflow,clk,rrst_n,1'b1,q,valid,empty);
 (* ASYNC_REG="TRUE" *)reg [1:0] fault_sync;
 always @(posedge clk or negedge rrst_n)begin
  if(!rrst_n)fault_sync<=0;
  else fault_sync<={fault_sync[0],overflow};
 end
 assign overflow_fault=fault_sync[1];
 assign sof=valid&&q[39];assign eof=valid&&q[38];
 assign frame_ok=q[37]&&!overflow_fault;
 assign pv=valid&&q[36];assign x=q[35:26];assign y=q[25:16];assign pixel=q[15:0];
 always @(posedge clk)begin
  if(!rrst_n)begin frame_error<=0;frames_read<=0;end
  else if(eof)begin
   frame_error<=!frame_ok;
   if(frame_ok)frames_read<=frames_read+1'b1;
  end
 end
endmodule
