`timescale 1ns/1ps
// VSYNC active high (blanking), HREF active high, MSB byte first.
// All ports are in PCLK domain. EOF is a transaction boundary; only frame_ok
// permits consumers to publish the frame. Partial frames can emit pixels.
module dvp_rgb565_rx #(parameter WIDTH=320, HEIGHT=240)(
 input wire pclk,rst_n,vsync,href,input wire [7:0] data,
 output reg sof,eof,frame_ok,pixel_valid,output reg [15:0] pixel,
 output reg [9:0] x,y,output reg [31:0] good_frames,bad_frames);
 reg vs_d,href_d,armed,bad,phase;
 reg [7:0] msb;
 reg [10:0] bytes_in_line;
 reg [9:0] lines;
 always @(posedge pclk) begin
   if(!rst_n) begin
     vs_d<=1;href_d<=0;armed<=0;bad<=0;phase<=0;msb<=0;
     bytes_in_line<=0;lines<=0;sof<=0;eof<=0;frame_ok<=0;
     pixel_valid<=0;pixel<=0;x<=0;y<=0;good_frames<=0;bad_frames<=0;
   end else begin
     vs_d<=vsync;href_d<=href;
     sof<=0;eof<=0;frame_ok<=0;pixel_valid<=0;
     if(vs_d && !vsync) begin
       armed<=1;bad<=href;phase<=0;bytes_in_line<=0;lines<=0;sof<=1;
     end else if(!vs_d && vsync) begin
       if(armed) begin
         eof<=1;
         frame_ok<=!bad && lines==HEIGHT && !href_d && !href;
         if(!bad && lines==HEIGHT && !href_d && !href) good_frames<=good_frames+1;
         else bad_frames<=bad_frames+1;
       end
       armed<=0;phase<=0;
     end else if(armed && !vsync) begin
       if(href) begin
         if(bytes_in_line<2*WIDTH) begin
           bytes_in_line<=bytes_in_line+1'b1;
           phase<=!phase;
           if(!phase) msb<=data;
           else if(lines<HEIGHT) begin
             pixel<={msb,data};x<=bytes_in_line>>1;y<=lines;pixel_valid<=1;
           end
         end else bad<=1;
       end else if(href_d) begin
         if(bytes_in_line!=2*WIDTH || phase || lines>=HEIGHT) bad<=1;
         if(lines<1023) lines<=lines+1'b1;
         bytes_in_line<=0;phase<=0;
       end
     end
   end
 end
endmodule
