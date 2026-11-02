`timescale 1ns/1ps
module tb_ov5640_capture;
 parameter HALF=71;
 reg clk=0,pclk=0;always #10 clk=~clk;
 initial begin #3;forever #(HALF) pclk=~pclk;end
 reg rst_n=0,vsync=1,href=0;reg [7:0] data=0;
 wire sof,eof,ok,pv,overflow,frame_error;wire [15:0] pixel;
 wire [9:0] x,y;wire [31:0] frames;
 ov5640_capture dut(clk,pclk,rst_n,vsync,href,data,
  sof,eof,ok,pv,pixel,x,y,overflow,frame_error,frames);
 integer count=0,good=0,bad=0,expected=0;
 function [15:0] pattern(input integer xx,yy);pattern=(yy*320+xx)^16'h5aa5;endfunction
 always @(negedge clk)if(rst_n)begin
  if(overflow)$fatal(1,"capture overflow");
  if(sof)begin count=0;expected=0;end
  if(pv)begin
   if(pixel!==pattern(x,y))$fatal(1,"RGB565/CDC corrupt x=%0d y=%0d got=%h",x,y,pixel);
   if(y*320+x!==expected)$fatal(1,"missing or reordered pixel");
   expected++;count++;
  end
  if(eof)begin
   if(ok)begin if(count!=76800)$fatal(1,"incomplete accepted frame");good++;end
   else bad++;
  end
 end
 task sample(input reg vs,hr,input [7:0] b);
  begin @(negedge pclk);#2;vsync=vs;href=hr;data=b;end
 endtask
 task frame(input integer kind);
  integer xx,yy,n;reg [15:0] p;
  begin
   repeat(6)sample(1,0,0);
   sample(0,0,0);repeat(4)sample(0,0,0);
   for(yy=0;yy<(kind==2?239:240);yy++)begin
    for(xx=0;xx<320;xx++)begin
     p=pattern(xx,yy);sample(0,1,p[15:8]);
     if(!(kind==1&&yy==239&&xx==319))sample(0,1,p[7:0]);
    end
    repeat(8)sample(0,0,0);
   end
   sample(1,0,0);repeat(8)sample(1,0,0);
  end
 endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;repeat(8)sample(1,0,0);
  frame(0);frame(1);frame(2);frame(0);
  #3000;
  if(good!=2||bad!=2||frames!=2)$fatal(1,"framing good=%0d bad=%0d",good,bad);
  // Reset during an incomplete transaction; the next complete frame recovers.
  sample(0,0,0);sample(0,1,8'hab);rst_n=0;#200;rst_n=1;
  repeat(8)sample(1,0,0);frame(0);#3000;
  if(frames!=1||frame_error)$fatal(1,"reset recovery failed");
  $display("OV5640_CAPTURE_PASS half_ns=%0d good=%0d bad=%0d reset=PASS",HALF,good,bad);$finish;
 end
 initial begin #250000000;$fatal(1,"capture timeout");end
endmodule
