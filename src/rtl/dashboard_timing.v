`timescale 1ns/1ps
// 1280x720p60: 74.25MHz, totals 1650x750, positive H/V sync.
module dashboard_timing(input wire clk,rst_n,output reg [10:0] x,
 output reg [9:0] y,output wire de,hsync,vsync,frame_start);
 always @(posedge clk)begin
   if(!rst_n)begin x<=0;y<=0;end
   else if(x==1649)begin x<=0;y<=y==749?0:y+1'b1;end
   else x<=x+1'b1;
 end
 assign de=x<1280&&y<720;
 assign hsync=x>=1390&&x<1430;
 assign vsync=y>=725&&y<730;
 assign frame_start=x==0&&y==0;
endmodule
