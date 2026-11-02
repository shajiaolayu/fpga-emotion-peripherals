// Generated from the frozen C1 serial pipeline; live display is fed directly.
`timescale 1ns/1ps
// Camera and inference share the 50MHz clock. A selected complete frame owns
// one photo bank until its inference result is displayed and acknowledged.
(* use_dsp="no" *) module photo_stream_consumer #(parameter SIM_MAC=0)(
 input wire clk,pixel_clk,arst_n,hold_inference,manual_mode,shutter,
 input wire photo_write_bank,photo_read_bank,photo_valid,result_pending,
 input wire sof,eof,frame_ok,pv,input wire [15:0] pixel,input wire [9:0] cx,cy,
 output reg [23:0] video_rgb,output reg video_de,video_hsync,video_vsync,
 output wire [2:0] prediction,output wire [223:0] scores,
 output wire inference_busy,inference_done,
 output wire thumbnail_we,output wire [11:0] thumbnail_addr,output wire [7:0] thumbnail_data,
 output wire [31:0] video_dropped,output wire work_busy,
 output reg [10:0] video_x,output reg [9:0] video_y,
 input wire live_sof,live_eof,live_ok,live_pv,input wire [15:0]live_input_pixel,
 input wire [9:0]live_x,live_y,output wire frame_request);
 wire core_rst_n,pix_rst_n;
 reset_sync core_reset(clk,arst_n,core_rst_n);
 reset_sync pixel_reset(pixel_clk,arst_n,pix_rst_n);
 // Keep optimizer-derived BRAM read enables behind a synchronous bridge.
 (* DONT_TOUCH="TRUE" *)reg pixel_active;
 always @(posedge pixel_clk)pixel_active<=pix_rst_n;
 // RAM output-register reset must be synchronous even if implementation
 // absorbs the loader's register into the BRAM output pipeline.
 (* DONT_TOUCH="TRUE" *)reg core_active;
 always @(posedge clk)core_active<=core_rst_n;
 localparam IDLE=0,CAPTURE=1,WAIT_GRAY=2,WAIT_CORE=3,WAIT_PUBLISH=4,WAIT_ACK=5;
 reg [2:0] state;
 reg armed,capture_bank,have_gray,available,gray_new;
 assign work_busy=state!=IDLE||armed;
 assign frame_request=state==IDLE&&!hold_inference&&(!manual_mode||armed||shutter);
 wire take_sof=state==IDLE&&sof&&!hold_inference&&(!manual_mode||armed||shutter);
 wire take_pixel=state==CAPTURE&&pv;
 wire take_eof=state==CAPTURE&&eof;
 wire gv,gray_commit,gray_abort;
 wire [11:0] ga;wire [7:0] gray;
 roi_gray48 preprocess(clk,core_active,take_sof,take_eof,frame_ok,take_pixel,cx,cy,pixel,
   gv,ga,gray,gray_commit,gray_abort);
 wire swap_boundary;
 always @(posedge clk)begin
   if(!core_active)begin state<=IDLE;armed<=0;capture_bank<=1;have_gray<=0;available<=0;gray_new<=0;end
   else begin
     gray_new<=0;
     case(state)
       IDLE:begin
         if(!manual_mode)armed<=0;
         else if(shutter&&!hold_inference)armed<=1;
         if(take_sof)begin state<=CAPTURE;capture_bank<=photo_write_bank;armed<=0;have_gray<=0;end
       end
       CAPTURE:if(eof)begin
         if(frame_ok)state<=WAIT_GRAY;else state<=IDLE;
       end
       WAIT_GRAY:if(gray_commit)begin have_gray<=1;available<=1;state<=WAIT_CORE;end
         else if(gray_abort)state<=IDLE;
       WAIT_CORE:begin
         if(available&&swap_boundary&&!hold_inference)begin gray_new<=1;available<=0;end
         if(inference_done)state<=WAIT_PUBLISH;
       end
       WAIT_PUBLISH:if(result_pending)state<=WAIT_ACK;
       WAIT_ACK:if(!result_pending&&!hold_inference)state<=IDLE;
       default:state<=IDLE;
     endcase
   end
 end
 reg write_enable,write_bank;reg [16:0] write_address;reg [15:0] write_data;
 always @(posedge clk)begin
   write_enable<=core_active&&take_pixel&&cx<320&&cy<240;
   write_bank<=capture_bank;write_address<=cy*17'd320+cx;write_data<=pixel;
 end
 (* ram_style="block" *)reg [7:0] gray_memory[0:2303];
 wire [11:0] gray_rd_addr;reg [7:0] gray_q;
 always @(posedge clk)begin
   if(gv&&ga<2304)gray_memory[ga]<=gray;
   if(gray_rd_addr<2304)gray_q<=gray_memory[gray_rd_addr];
 end
 wire load,start;wire [11:0] load_addr;wire [7:0] load_data;
 gray_frame_loader loader(clk,core_active,inference_busy||hold_inference,inference_done,
   gray_q,have_gray,gray_new,swap_boundary,gray_rd_addr,
   load,load_addr,load_data,start,thumbnail_we,thumbnail_addr,thumbnail_data);
 wire trace_valid;wire [5:0] trace_op;wire [16:0] trace_addr;wire [31:0] trace_value;
 inference_core #(.SIM_MAC(SIM_MAC)) core(
   .clk(clk),.rst_n(core_active),.load_en(load),.load_addr(load_addr),.load_data(load_data),
   .start(start),.busy(inference_busy),.done(inference_done),.scores(scores),.prediction(prediction),
   .trace_valid(trace_valid),.trace_op(trace_op),.trace_addr(trace_addr),.trace_value(trace_value));
 wire [10:0] vx;wire [9:0] vy;wire de,hs,vs,unused_sof;
 dashboard_timing timing(pixel_clk,pixel_active,vx,vy,de,hs,vs,unused_sof);
 wire live_region=vx>=24&&vx<664&&vy>=163&&vy<643;
 wire frozen_region=vx>=688&&vx<1008&&vy>=144&&vy<384;
 wire [16:0] live_addr=live_region?((vy-10'd163)>>1)*17'd320+((vx-11'd24)>>1):17'd0;
 wire [16:0] frozen_addr=frozen_region?(vy-10'd144)*17'd320+(vx-11'd688):17'd0;
 wire [15:0] live_pixel;wire live_valid,video_ready,video_new;
 frame_buffer_cdc video_buffer(clk,core_active,live_sof,live_pv,live_eof&&live_ok,live_eof&&!live_ok,
   live_y*17'd320+live_x,live_input_pixel,video_ready,video_dropped,pixel_clk,pixel_active,
   vx==0&&vy==720,live_addr,live_pixel,live_valid,video_new);
 wire [15:0] p0,p1;reg photo_bank_q,photo_valid_q;
 packed_bram_tdp #(.WIDTH(16),.DEPTH(76800)) photo0_storage(
  .clk_a(clk),.en_a(write_enable&&!write_bank),.we_a(1'b1),
  .addr_a(write_address),.din_a(write_data),.q_a(),
  .clk_b(pixel_clk),.en_b(1'b1),.addr_b(frozen_addr),.q_b(p0));
 packed_bram_tdp #(.WIDTH(16),.DEPTH(76800)) photo1_storage(
  .clk_a(clk),.en_a(write_enable&&write_bank),.we_a(1'b1),
  .addr_a(write_address),.din_a(write_data),.q_a(),
  .clk_b(pixel_clk),.en_b(1'b1),.addr_b(frozen_addr),.q_b(p1));
 always @(posedge pixel_clk)begin
   photo_bank_q<=photo_read_bank;photo_valid_q<=photo_valid;
 end
 wire [15:0] frozen_pixel=photo_bank_q?p1:p0;
 reg [10:0] dx;reg [9:0] dy;reg dde,dhs,dvs,live_region_q,frozen_region_q;
 always @(posedge pixel_clk)begin
   if(!pixel_active)begin dx<=0;dy<=0;dde<=0;dhs<=0;dvs<=0;live_region_q<=0;frozen_region_q<=0;end
   else begin dx<=vx;dy<=vy;dde<=de;dhs<=hs;dvs<=vs;live_region_q<=live_region;frozen_region_q<=frozen_region;end
 end
 wire live_border=dx>=152&&dx<536&&dy>=211&&dy<595&&(dx<154||dx>=534||dy<213||dy>=593);
 wire frozen_border=dx>=752&&dx<944&&dy>=168&&dy<360&&(dx<754||dx>=942||dy<170||dy>=358);
 wire [15:0] display_pixel=live_region_q?live_pixel:frozen_pixel;
 function [23:0] expand(input [15:0] p);
   expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
 endfunction
 always @(posedge pixel_clk)begin
   if(!pixel_active)begin video_rgb<=0;video_de<=0;video_hsync<=0;video_vsync<=0;video_x<=0;video_y<=0;end
   else begin
     video_x<=dx;video_y<=dy;video_de<=dde;video_hsync<=dhs;video_vsync<=dvs;
     if(!dde)video_rgb<=0;
     else if(live_region_q)video_rgb<=live_border?24'h1f62b7:(live_valid?expand(display_pixel):24'd0);
     else if(frozen_region_q)video_rgb<=!photo_valid_q?24'd0:(frozen_border?24'h8e6928:expand(display_pixel));
     else video_rgb<=0;
   end
 end
endmodule
