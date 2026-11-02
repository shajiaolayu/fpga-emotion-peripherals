`timescale 1ns/1ps
// Camera and inference share the 50MHz clock. A selected complete frame owns
// one photo bank until its inference result is displayed and acknowledged.
(* use_dsp="no" *) module photo_overlap_pipeline #(parameter SIM_MAC=0)(
 input wire clk,pixel_clk,arst_n,hold_inference,manual_mode,shutter,
 input wire photo_write_bank,photo_read_bank,photo_valid,result_pending,
 input wire sof,eof,frame_ok,pv,input wire [15:0] pixel,input wire [9:0] cx,cy,
 output wire [23:0] video_rgb,output wire video_de,video_hsync,video_vsync,
 output wire [2:0] prediction,output wire [223:0] scores,
 output wire inference_busy,inference_done,
 output wire thumbnail_we,output wire [11:0] thumbnail_addr,output wire [7:0] thumbnail_data,
 output wire [31:0] video_dropped,output wire work_busy,
 output wire [10:0] video_x,output wire [9:0] video_y);
 wire qrst_n;
 reset_sync prefetch_reset(clk,arst_n,qrst_n);
 (* DONT_TOUCH="TRUE" *)reg queue_active;
 always @(posedge clk)queue_active<=qrst_n;
 wire request,qs,qe,qok,qp;
 wire [15:0]qd;wire [9:0]qx,qy;wire [31:0]replayed,queue_dropped;
 camera_frame_prefetch prefetch(clk,queue_active,sof,eof,frame_ok,pv,pixel,cx,cy,
  request,manual_mode,shutter,work_busy,qs,qe,qok,qp,qd,qx,qy,replayed,queue_dropped);
 photo_stream_consumer #(.SIM_MAC(SIM_MAC)) consumer(
  clk,pixel_clk,arst_n,hold_inference,manual_mode,shutter,
  photo_write_bank,photo_read_bank,photo_valid,result_pending,
  qs,qe,qok,qp,qd,qx,qy,video_rgb,video_de,video_hsync,video_vsync,prediction,scores,
  inference_busy,inference_done,thumbnail_we,thumbnail_addr,thumbnail_data,
  video_dropped,work_busy,video_x,video_y,sof,eof,frame_ok,pv,pixel,cx,cy,request);
endmodule
