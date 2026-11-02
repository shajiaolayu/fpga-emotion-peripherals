`timescale 1ns/1ps
// Atomic actual-input record: OV48 + sequence LE32 + class + 2304 grey bytes
// + 7 signed LE32 scores + CRC32 LE32. Hold the next inference while busy.
module inference_debug_uart #(parameter CLK_HZ=50000000,BAUD=460800)(
 input wire clk,rst_n,gray_we,input wire [11:0] gray_addr,input wire [7:0] gray_data,
 input wire done,input wire [2:0] prediction,input wire [223:0] scores,
 output reg busy,output wire tx,output reg [31:0] count);
 (* ram_style="block" *) reg [7:0] image[0:2303];
 reg [7:0] image_q;
 reg [11:0] index;
 wire [11:0] image_addr=(index>=9 && index<2313)?index-12'd9:12'd0;
 always @(posedge clk) begin
   if(gray_we && gray_addr<2304)image[gray_addr]<=gray_data;
   image_q<=image[image_addr];
 end
 reg [2:0] saved_class,state;
 reg [223:0] saved_scores;
 reg [31:0] saved_sequence,crc;
 reg tx_start;
 reg [7:0] tx_data;
 wire tx_busy;
 uart_tx #(.CLK_FREQ(CLK_HZ),.BAUD(BAUD)) uart(clk,rst_n,tx_start,tx_data,tx,tx_busy);
 function [31:0] crc_byte(input [31:0] old,input [7:0] value);
   reg [31:0] c;integer b;
   begin c=old^value;for(b=0;b<8;b=b+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 function [7:0] next_byte(input [11:0] n);
   reg [31:0] final_crc;
   begin
     final_crc=~crc;
     if(n==0)next_byte=8'h4f;else if(n==1)next_byte=8'h56;
     else if(n==2)next_byte=8'h34;else if(n==3)next_byte=8'h38;
     else if(n<8)next_byte=saved_sequence[(n-4)*8+:8];
     else if(n==8)next_byte={5'b0,saved_class};
     else if(n<2313)next_byte=image_q;
     else if(n<2341)next_byte=saved_scores[(n-2313)*8+:8];
     else next_byte=final_crc[(n-2341)*8+:8];
   end
 endfunction
 always @(posedge clk) begin
   if(!rst_n)begin
     busy<=0;count<=0;index<=0;state<=0;saved_class<=0;saved_scores<=0;
     saved_sequence<=0;crc<=32'hffffffff;tx_start<=0;tx_data<=0;
   end else begin
     tx_start<=0;
     case(state)
      0:if(done)begin
        saved_class<=prediction;saved_scores<=scores;saved_sequence<=count+1;
        count<=count+1;index<=0;crc<=32'hffffffff;busy<=1;state<=4;
      end
      4:state<=1; // allow a synchronous RAM read before each byte
      1:if(!tx_busy)begin
        tx_data<=next_byte(index);tx_start<=1;
        if(index<2341)crc<=crc_byte(crc,next_byte(index));
        state<=2;
      end
      2:if(tx_busy)state<=3;
      3:if(!tx_busy)begin
        if(index==2344)begin busy<=0;state<=0;end
        else begin index<=index+1'b1;state<=4;end
      end
      default:begin state<=0;busy<=0;end
     endcase
   end
 end
endmodule
