`timescale 1ns/1ps
// Gray-pointer FIFO. Read data and read_valid emerge together for one cycle.
// Both pointer domains must receive the same asynchronous reset assertion.
module async_event_fifo #(parameter WIDTH=40,ADDR_BITS=6)(
 input wire wclk,wrst_n,wen,input wire [WIDTH-1:0] wdata,
 output reg full,output reg overflow,
 input wire rclk,rrst_n,ren,(* DONT_TOUCH="TRUE" *)output reg [WIDTH-1:0] rdata,
 output reg rvalid,output wire empty);
 localparam DEPTH=1<<ADDR_BITS;
 (* ram_style="distributed" *) reg [WIDTH-1:0] mem[0:DEPTH-1];
 reg [ADDR_BITS:0] wbin,wgray,rbin,rgray;
 (* ASYNC_REG="TRUE" *) reg [ADDR_BITS:0] rgray_meta,rgray_sync,wgray_meta,wgray_sync;
 wire push=wen&&!full;
 wire pop=ren&&!empty;
 wire [ADDR_BITS:0] wn=wbin+push,rn=rbin+pop;
 wire [ADDR_BITS:0] wg=(wn>>1)^wn,rg=(rn>>1)^rn;
 assign empty=rgray==wgray_sync;
 always @(posedge wclk or negedge wrst_n)begin
  if(!wrst_n)begin rgray_meta<=0;rgray_sync<=0;end
  else begin rgray_meta<=rgray;rgray_sync<=rgray_meta;end
 end
 always @(posedge rclk or negedge rrst_n)begin
  if(!rrst_n)begin wgray_meta<=0;wgray_sync<=0;end
  else begin wgray_meta<=wgray;wgray_sync<=wgray_meta;end
 end
 always @(posedge wclk or negedge wrst_n)begin
  if(!wrst_n)begin wbin<=0;wgray<=0;full<=0;overflow<=0;end
  else begin
   wbin<=wn;wgray<=wg;
   full<=wg=={~rgray_sync[ADDR_BITS:ADDR_BITS-1],rgray_sync[ADDR_BITS-2:0]};
   if(wen&&full)overflow<=1;
  end
 end
 always @(posedge wclk)if(push)mem[wbin[ADDR_BITS-1:0]]<=wdata;
 always @(posedge rclk or negedge rrst_n)begin
  if(!rrst_n)begin rbin<=0;rgray<=0;rvalid<=0;end
  else begin rbin<=rn;rgray<=rg;rvalid<=pop;end
 end
 // This is the bounded bundled-data CDC endpoint. Preserve its flops when
 // downstream address arithmetic or BRAM inputs are optimized/replicated.
 always @(posedge rclk)if(pop)rdata<=mem[rbin[ADDR_BITS-1:0]];
endmodule
