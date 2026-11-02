`timescale 1ns/1ps
// Two full frames. Writer drops whole frames while a publication is pending.
// Reader acknowledges only on swap_boundary (vertical blank), never mid-frame.
// Both resets must derive from a common reset and assert together. A clock may
// stop: the other side then keeps its current frame and never reuses that bank.
module frame_buffer_cdc #(parameter DEPTH=76800,DATA_WIDTH=16,ADDR_WIDTH=17)(
 input wire wr_clk,wr_rst_n,sof,wr_en,commit,abort_frame,
 input wire [ADDR_WIDTH-1:0] wr_addr,input wire [DATA_WIDTH-1:0] wr_data,
 output wire wr_ready,output reg [31:0] dropped,
 input wire rd_clk,rd_rst_n,swap_boundary,
 input wire [ADDR_WIDTH-1:0] rd_addr,
 output wire [DATA_WIDTH-1:0] rd_data,output reg rd_valid,new_frame);

 reg req,ack,capture,read_bank,have_frame;
 wire [DATA_WIDTH-1:0] bank0_q,bank1_q;
 reg read_bank_q;
 assign rd_data=read_bank_q?bank1_q:bank0_q;
 (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,req_sync;
 assign wr_ready=(req==ack_sync[1]);
 always @(posedge wr_clk) begin
   if(!wr_rst_n) begin ack_sync<=0;req<=0;capture<=0;dropped<=0;end
   else begin
     ack_sync<={ack_sync[0],ack};
     if(sof) begin
       capture<=wr_ready;
       if(!wr_ready) dropped<=dropped+1'b1;
     end else if(abort_frame) capture<=0;
     else if(commit) begin
       if(capture) req<=!req;
       capture<=0;
     end
   end
 end
 // Register the complete write transaction. An asynchronously asserted reset
 // bridge must never directly drive a BRAM WE/EN pin (Vivado REQP-1839).
 reg write_enable,write_bank;
 reg [ADDR_WIDTH-1:0] write_address;
 reg [DATA_WIDTH-1:0] write_value;
 always @(posedge wr_clk) begin
   write_enable<=wr_rst_n && capture && wr_en && wr_addr<DEPTH;
   write_bank<=!req;write_address<=wr_addr;write_value<=wr_data;
 end
 // No reset in the memory process. Publication takes two receiver clocks to
 // propagate, after this one-stage write pipeline has finished.
 packed_bram_tdp #(.WIDTH(DATA_WIDTH),.DEPTH(DEPTH),.ADDR_WIDTH(ADDR_WIDTH)) bank0_storage(
  .clk_a(wr_clk),.en_a(write_enable&&!write_bank),.we_a(1'b1),
  .addr_a(write_address),.din_a(write_value),.q_a(),
  .clk_b(rd_clk),.en_b(rd_addr<DEPTH),.addr_b(rd_addr),.q_b(bank0_q));
 packed_bram_tdp #(.WIDTH(DATA_WIDTH),.DEPTH(DEPTH),.ADDR_WIDTH(ADDR_WIDTH)) bank1_storage(
  .clk_a(wr_clk),.en_a(write_enable&&write_bank),.we_a(1'b1),
  .addr_a(write_address),.din_a(write_value),.q_a(),
  .clk_b(rd_clk),.en_b(rd_addr<DEPTH),.addr_b(rd_addr),.q_b(bank1_q));
 always @(posedge rd_clk) begin
   if(!rd_rst_n) begin req_sync<=0;ack<=0;read_bank<=0;have_frame<=0;new_frame<=0;end
   else begin
     new_frame<=0;
     req_sync<={req_sync[0],req};
     if(swap_boundary && req_sync[1]!=ack) begin
       read_bank<=req_sync[1];have_frame<=1;ack<=req_sync[1];new_frame<=1;
     end
   end
 end
 // Separate registered read ports are essential for true dual-clock BRAM
 // inference. A mux before a shared output register becomes distributed RAM.
 always @(posedge rd_clk) begin
   rd_valid<=rd_rst_n && have_frame && rd_addr<DEPTH;
   read_bank_q<=read_bank;
 end
endmodule
