`timescale 1ns/1ps
// Two complete-frame staging banks, all in the 50MHz domain. A bank being
// replayed is immutable; only validated complete frames may be dispatched.
(* use_dsp="no" *)module camera_frame_prefetch #(parameter WIDTH=320,HEIGHT=240)(
 input wire clk,rst_n,sof,eof,frame_ok,pv,input wire [15:0]pixel,
 input wire [9:0]x,y,input wire request,manual_mode,shutter,consumer_busy,
 output reg out_sof,out_eof,out_ok,out_pv,output reg [15:0]out_pixel,
 output reg [9:0]out_x,out_y,output reg [31:0]replayed,dropped);
 localparam PIXELS=WIDTH*HEIGHT;
 localparam IDLE=0,START_FRAME=1,ADDRESS=2,WAIT_RAM=3,EMIT=4,END_FRAME=5,RELEASE=6;
 reg [2:0]state;
 reg capture_active,capture_bank,capture_bad,capture_eligible;
 reg pending_valid,pending_bank,replay_bank,manual_wait;
 reg [17:0]capture_count,replay_index;
 reg [9:0]capture_x,capture_y,replay_x,replay_y;
 wire replay_active=state!=IDLE;
 wire free0=!(pending_valid&&!pending_bank)&&!(replay_active&&!replay_bank);
 wire free1=!(pending_valid&&pending_bank)&&!(replay_active&&replay_bank);
 wire new_shutter=manual_mode&&shutter&&!consumer_busy&&request;
 wire dispatch=state==IDLE&&pending_valid&&request&&!new_shutter;
 reg write_enable,write_bank;
 reg [16:0]write_address,read_address;
 reg [15:0]write_pixel;
 wire [15:0]q0,q1;
 always @(posedge clk)begin
  write_enable<=rst_n&&capture_active&&pv&&capture_count<PIXELS&&x<WIDTH&&y<HEIGHT;
  write_bank<=capture_bank;write_address<=y*WIDTH+x;write_pixel<=pixel;
 end
 packed_bram_tdp #(.WIDTH(16),.DEPTH(PIXELS)) staging0(
  clk,write_enable&&!write_bank,1'b1,write_address,write_pixel,
  ,clk,1'b1,read_address,q0);
 packed_bram_tdp #(.WIDTH(16),.DEPTH(PIXELS)) staging1(
  clk,write_enable&&write_bank,1'b1,write_address,write_pixel,
  ,clk,1'b1,read_address,q1);
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;capture_active<=0;capture_bank<=0;capture_bad<=0;capture_eligible<=0;
   pending_valid<=0;pending_bank<=0;replay_bank<=0;manual_wait<=0;
   capture_count<=0;replay_index<=0;capture_x<=0;capture_y<=0;replay_x<=0;replay_y<=0;
   read_address<=0;out_sof<=0;out_eof<=0;out_ok<=0;out_pv<=0;
   out_pixel<=0;out_x<=0;out_y<=0;replayed<=0;dropped<=0;
  end else begin
   out_sof<=0;out_eof<=0;out_ok<=0;out_pv<=0;
   if(!manual_mode)manual_wait<=0;
   if(dispatch)begin
    replay_bank<=pending_bank;pending_valid<=0;replay_index<=0;
    replay_x<=0;replay_y<=0;state<=START_FRAME;
    if(manual_mode)manual_wait<=0;
   end
   case(state)
    START_FRAME:begin out_sof<=1;state<=ADDRESS;end
    ADDRESS:begin read_address<=replay_index;state<=WAIT_RAM;end
    WAIT_RAM:state<=EMIT;
    EMIT:begin
     out_pv<=1;out_pixel<=replay_bank?q1:q0;out_x<=replay_x;out_y<=replay_y;
     if(replay_index==PIXELS-1)state<=END_FRAME;
     else begin
      replay_index<=replay_index+1'b1;state<=ADDRESS;
      if(replay_x==WIDTH-1)begin replay_x<=0;replay_y<=replay_y+1'b1;end
      else replay_x<=replay_x+1'b1;
     end
    end
    END_FRAME:begin out_eof<=1;out_ok<=1;replayed<=replayed+1'b1;state<=RELEASE;end
    RELEASE:state<=IDLE;
    default:begin end
   endcase
   if(sof)begin
    capture_count<=0;capture_x<=0;capture_y<=0;capture_bad<=0;
    capture_eligible<=!manual_mode||manual_wait;
    if(free0||free1)begin capture_active<=1;capture_bank<=!free0;end
    else begin capture_active<=0;dropped<=dropped+1'b1;end
   end else if(capture_active&&pv)begin
    if(x!=capture_x||y!=capture_y||capture_count>=PIXELS)capture_bad<=1;
    if(capture_count<PIXELS)capture_count<=capture_count+1'b1;
    if(capture_x==WIDTH-1)begin capture_x<=0;capture_y<=capture_y+1'b1;end
    else capture_x<=capture_x+1'b1;
   end
   if(eof&&capture_active)begin
    capture_active<=0;
    if(frame_ok&&!capture_bad&&capture_count==PIXELS&&(!manual_mode||capture_eligible))begin
     pending_valid<=1;pending_bank<=capture_bank;
     if(pending_valid&&!dispatch)dropped<=dropped+1'b1;
    end
   end
   // A manual shutter invalidates older pending/in-progress images. Only a
   // frame whose SOF follows this trigger can be selected for that photo.
   if(new_shutter)begin pending_valid<=0;capture_eligible<=0;manual_wait<=1;end
  end
 end
endmodule
