`timescale 1ns/1ps
// Independent sensor pin model applies the real 4740/4300 register semantics.
// This couples wire-level SCCB initialization to the physical DVP waveform.
module tb_ov5640_configured_dvp;
 reg clk=0,pclk=0;always #10 clk=~clk;
 initial begin #3;forever #71 pclk=~pclk;end
 reg rst_n=0;tri1 scl,sda;
 wire sl,sd,start,read_op,busy,done,error,nack,ready,failed,reset_n,pwdn;
 wire [15:0]addr,id;wire [7:0]wd,rd,code;
 assign scl=sl?0:1'bz;assign sda=sd?0:1'bz;
 sccb16_master #(.CLK_HZ(4000000),.BUS_HZ(100000))
  master(clk,rst_n,start,read_op,addr,wd,scl,sda,sl,sd,busy,done,error,rd,nack);
 ov5640_init #(.WAIT_MS(2)) init_i(clk,rst_n,busy,done,error,rd,
  start,read_op,addr,wd,reset_n,pwdn,ready,failed,code,id);
 ov5640_sccb_model sensor(rst_n,scl,sda,1'b0,1'b0,1'b0);
 reg frame_active=0,line_active=0;reg [7:0] data=0;
 // OV5640 app note: 4740[1]=1 means active-low HREF; [0]=0 means
 // data-valid VSYNC low. 4300=61 emits RGB565 high byte first on DVP.
 wire href=sensor.regs[16'h4740][1]?!line_active:line_active;
 wire vsync=sensor.regs[16'h4740][0]?frame_active:!frame_active;
 wire sof,eof,ok,pv,overflow,frame_error;wire [15:0]pixel;
 wire [9:0]x,y;wire [31:0]frames;
 ov5640_capture capture(clk,pclk,rst_n&&ready,vsync,href,data,
  sof,eof,ok,pv,pixel,x,y,overflow,frame_error,frames);
 integer received=0;
 function [15:0]pattern(input integer xx,yy);pattern=(yy*320+xx)^16'h4b29;endfunction
 always @(negedge clk)if(ready)begin
  if(pv)begin
   if(pixel!==pattern(x,y))$fatal(1,"configured DVP byte order/data mismatch x=%0d y=%0d",x,y);
   received++;
  end
  if(eof)begin
   if(!ok||overflow||received!=76800)$fatal(1,"configured DVP frame rejected polarity=%h pixels=%0d",sensor.regs[16'h4740],received);
   $display("OV5640_CONFIGURED_DVP_PASS pixels=76800 polarity=%h format=%h",sensor.regs[16'h4740],sensor.regs[16'h4300]);$finish;
  end
 end
 task byte_cycle(input reg fa,la,input [7:0]value);
  begin
   if(sensor.regs[16'h4740][5])@(negedge pclk);else @(posedge pclk);
   #2;frame_active=fa;line_active=la;data=value;
  end
 endtask
 integer xx,yy,width,height;reg [15:0]value;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;wait(ready||failed);
  if(failed)$fatal(1,"sensor setup failed code=%h",code);
  width={sensor.regs[16'h3808],sensor.regs[16'h3809]};
  height={sensor.regs[16'h380a],sensor.regs[16'h380b]};
  repeat(12)byte_cycle(0,0,0);byte_cycle(1,0,0);repeat(4)byte_cycle(1,0,0);
  for(yy=0;yy<height;yy++)begin
   for(xx=0;xx<width;xx++)begin
    value=pattern(xx,yy);
    byte_cycle(1,1,sensor.regs[16'h4300]==8'h61 ? value[15:8] : value[7:0]);
    byte_cycle(1,1,sensor.regs[16'h4300]==8'h61 ? value[7:0] : value[15:8]);
   end
   repeat(8)byte_cycle(1,0,0);
  end
  byte_cycle(0,0,0);repeat(8)byte_cycle(0,0,0);
 end
 initial begin #50000000;$fatal(1,"configured camera timeout");end
endmodule
