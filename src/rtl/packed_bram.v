`timescale 1ns/1ps
// Explicit 4K pages and <=9-bit slices prevent 32Kx1 aspect-ratio expansion.
// Both ports retain a single synchronous read latency. No RAM reset is used.
module packed_bram_tdp #(
 parameter WIDTH=8, DEPTH=73728, ADDR_WIDTH=17,
 parameter PAGE_BITS=(ADDR_WIDTH<12)?ADDR_WIDTH:12, SLICE_BITS=9
)(input wire clk_a,en_a,we_a,input wire [ADDR_WIDTH-1:0] addr_a,
 input wire [WIDTH-1:0] din_a,output wire [WIDTH-1:0] q_a,
 input wire clk_b,en_b,input wire [ADDR_WIDTH-1:0] addr_b,
 output wire [WIDTH-1:0] q_b);
 localparam PAGE_SIZE=1<<PAGE_BITS;
 localparam PAGES=(DEPTH+PAGE_SIZE-1)/PAGE_SIZE;
 localparam SELECT_BITS=(PAGES>1)?$clog2(PAGES):1;
 wire [WIDTH-1:0] page_a[0:PAGES-1],page_b[0:PAGES-1];
 reg [SELECT_BITS-1:0] select_a,select_b;
 always @(posedge clk_a)if(en_a&&addr_a<DEPTH)select_a<=addr_a>>PAGE_BITS;
 always @(posedge clk_b)if(en_b&&addr_b<DEPTH)select_b<=addr_b>>PAGE_BITS;
 assign q_a=page_a[select_a];assign q_b=page_b[select_b];
 genvar p,c;
 generate for(p=0;p<PAGES;p=p+1)begin: pages
  localparam LENGTH=(DEPTH-p*PAGE_SIZE<PAGE_SIZE)?DEPTH-p*PAGE_SIZE:PAGE_SIZE;
  wire a_selected=en_a&&addr_a<DEPTH&&(addr_a>>PAGE_BITS)==p;
  wire b_selected=en_b&&addr_b<DEPTH&&(addr_b>>PAGE_BITS)==p;
  for(c=0;c<(WIDTH+SLICE_BITS-1)/SLICE_BITS;c=c+1)begin: columns
   localparam CW=(WIDTH-c*SLICE_BITS<SLICE_BITS)?WIDTH-c*SLICE_BITS:SLICE_BITS;
   (* ram_style="block" *)reg [CW-1:0] mem[0:LENGTH-1];
   reg [CW-1:0] a_value,b_value;
   always @(posedge clk_a)if(a_selected)begin
    if(we_a)mem[addr_a[PAGE_BITS-1:0]]<=din_a[c*SLICE_BITS+:CW];
    a_value<=mem[addr_a[PAGE_BITS-1:0]];
   end
   always @(posedge clk_b)if(b_selected)b_value<=mem[addr_b[PAGE_BITS-1:0]];
   assign page_a[p][c*SLICE_BITS+:CW]=a_value;
   assign page_b[p][c*SLICE_BITS+:CW]=b_value;
  end
 end endgenerate
endmodule
