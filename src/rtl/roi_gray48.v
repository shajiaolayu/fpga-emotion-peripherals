`timescale 1ns/1ps
// Streaming, 192x192 fixed ROI -> 48x48 using rounded 4x4 box average.
// Output remains raw unsigned grey: inference_core performs the ^8'h80 itself.
module roi_gray48 #(parameter ROI_X=64, ROI_Y=24)(
 input wire clk,rst_n,sof,eof,frame_ok,pixel_valid,
 input wire [9:0] x,y,input wire [15:0] pixel,
 output reg gray_valid,output reg [11:0] gray_addr,
 output reg [7:0] gray,output reg commit,abort_frame);
 wire [7:0] r={pixel[15:11],pixel[15:13]};
 wire [7:0] g={pixel[10:5],pixel[10:9]};
 wire [7:0] b={pixel[4:0],pixel[4:2]};
 wire [17:0] weighted=77*r+150*g+29*b+18'd128;
 wire [7:0] lum=weighted[15:8];
 wire inside_roi=(x>=ROI_X && x<ROI_X+192 && y>=ROI_Y && y<ROI_Y+192);
 wire [9:0] rx=x-ROI_X,ry=y-ROI_Y;
 wire [5:0] col=rx[7:2];
 reg [11:0] sums[0:47];
 wire first_sample=(rx[1:0]==0 && ry[1:0]==0);
 wire [12:0] next_sum=(first_sample?13'd0:{1'b0,sums[col]})+lum;
 wire [12:0] rounded=next_sum+13'd8;
 reg [11:0] count;
 reg active;
 always @(posedge clk) begin
   if(!rst_n) begin
     gray_valid<=0;gray_addr<=0;gray<=0;commit<=0;abort_frame<=0;count<=0;active<=0;
   end else begin
     gray_valid<=0;commit<=0;abort_frame<=0;
     if(sof) begin count<=0;active<=1;end
     else if(eof) begin
       commit<=active && frame_ok && count==2304;
       abort_frame<=active && !(frame_ok && count==2304);
       active<=0;
     end else if(active && pixel_valid && inside_roi) begin
       sums[col]<=next_sum[11:0];
       if(rx[1:0]==3 && ry[1:0]==3) begin
         gray_valid<=1;gray<=rounded[11:4];
         gray_addr<=ry[7:2]*12'd48+col;count<=count+1'b1;
       end
     end
   end
 end
endmodule
