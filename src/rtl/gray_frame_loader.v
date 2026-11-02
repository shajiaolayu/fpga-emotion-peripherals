`timescale 1ns/1ps
// Consumes a complete 48x48 frame through frame_buffer_cdc. Acknowledge the
// publication only when idle; load 2304 pixels before raising core_start.
// Raw grey goes unchanged to inference_core.load_data.
module gray_frame_loader(input wire clk,rst_n,core_busy,core_done,
 input wire [7:0] rd_data,input wire rd_valid,new_frame,
 output wire swap_boundary,output reg [11:0] rd_addr,
 output reg core_load_en,output reg [11:0] core_load_addr,
 output reg [7:0] core_load_data,output reg core_start,
 output reg thumbnail_we,output reg [11:0] thumbnail_addr,
 output reg [7:0] thumbnail_data);
 localparam WAIT_FRAME=0,WAIT_READ=1,LOAD=2,START=3,RUN=4;
 reg [2:0] state;
 reg [11:0] index;
 assign swap_boundary=(state==WAIT_FRAME && !core_busy);
 always @(posedge clk) begin
   if(!rst_n) begin
     state<=WAIT_FRAME;index<=0;rd_addr<=0;core_load_en<=0;
     core_load_addr<=0;core_load_data<=0;core_start<=0;
     thumbnail_we<=0;thumbnail_addr<=0;thumbnail_data<=0;
   end else begin
     core_load_en<=0;core_start<=0;thumbnail_we<=0;
     case(state)
       WAIT_FRAME: if(new_frame && !core_busy) begin
         state<=WAIT_READ;index<=0;rd_addr<=0;
       end
       WAIT_READ: begin state<=LOAD;rd_addr<=1;end
       LOAD: if(rd_valid && !core_busy) begin
         core_load_en<=1;core_load_addr<=index;core_load_data<=rd_data;
         thumbnail_we<=1;thumbnail_addr<=index;thumbnail_data<=rd_data;
         if(index==2303) begin state<=START;rd_addr<=0;end
         else begin index<=index+1'b1;rd_addr<=index+2'd2;end
       end else begin state<=WAIT_FRAME;rd_addr<=0;end
       START: begin core_start<=1;state<=RUN;end
       RUN: if(core_done) begin state<=WAIT_FRAME;rd_addr<=0;end
       default: state<=WAIT_FRAME;
     endcase
   end
 end
endmodule
