`timescale 1ns/1ps
// Synthetic camera patterns and an independent software reference; no face images.
module tb_public_roi;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,sof=0,eof=0,frame_ok=0,pixel_valid=0;
 reg [9:0] x=0,y=0; reg [15:0] pixel=0;
 wire gray_valid,commit,abort_frame; wire [11:0] gray_addr; wire [7:0] gray;
 roi_gray48 dut(.*);
 reg [15:0] image0[0:76799],image1[0:76799];
 reg [7:0] expected0[0:2303],expected1[0:2303];
 integer tag=0,count=0,commits=0,aborts=0,xx,yy;
 always @(posedge clk)begin
  #1;
  if(rst_n)begin
   if(gray_valid)begin
    if(gray_addr!==count||gray!==(tag?expected1[count]:expected0[count]))
     $fatal(1,"ROI address/value mismatch tag=%0d index=%0d got=%h",tag,count,gray);
    count++;
   end
   if(commit)begin if(count!=2304)$fatal(1,"partial ROI committed");commits++;end
   if(abort_frame)aborts++;
  end
 end
 task frame(input integer variant,input bit valid_frame);
  begin
   tag=variant;count=0;
   @(negedge clk);sof=1;@(negedge clk);sof=0;
   for(yy=0;yy<240;yy++)for(xx=0;xx<320;xx++)begin
    x=xx;y=yy;pixel=variant?image1[yy*320+xx]:image0[yy*320+xx];pixel_valid=1;
    @(negedge clk);
   end
   pixel_valid=0;eof=1;frame_ok=valid_frame;
   @(negedge clk);eof=0;frame_ok=0;repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("camera0.mem",image0);$readmemh("camera1.mem",image1);
  $readmemh("gray0.mem",expected0);$readmemh("gray1.mem",expected1);
  repeat(4)@(negedge clk);rst_n=1;
  frame(0,1);frame(1,0);frame(1,1);
  if(commits!=2||aborts!=1)$fatal(1,"ROI frame acceptance mismatch");
  $display("PUBLIC_ROI_PASS compared=6912 commits=2 rejected=1");$finish;
 end
 initial begin #5000000;$fatal(1,"ROI timeout");end
endmodule
