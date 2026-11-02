`timescale 1ns/1ps
module tb_ov5640_init;
 parameter MODE=0;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 tri1 scl,sda;
 wire sl,sd,start,rdop,busy,done,error,nack,ready,failed,reset_n,pwdn;
 wire [15:0] addr,id;wire [7:0] wd,rd,code;
 assign scl=sl?0:1'bz;
 assign sda=(sd||(MODE==4&&rst_n))?0:1'bz;
 sccb16_master #(.CLK_HZ(4000000),.BUS_HZ(100000),.WATCHDOG_TICKS(512))
  master(clk,rst_n,start,rdop,addr,wd,scl,sda,sl,sd,busy,done,error,rd,nack);
 ov5640_init #(.WAIT_MS(MODE==5?400:2)) init_i(clk,rst_n,busy,done,error,rd,
  start,rdop,addr,wd,reset_n,pwdn,ready,failed,code,id);
 ov5640_sccb_model #(.STARTUP_READ_GUARD_NS(MODE==5?100000:0),.ONE_BAD_VERIFY(MODE==6))
  sensor(rst_n,scl,sda,MODE==1,MODE==2,MODE==3);
 integer transactions=0;
 always @(posedge clk)if(start)begin
  transactions++;
  if(!reset_n||pwdn)$fatal(1,"SCCB started before power/reset release");
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  wait(ready||failed);repeat(5)@(negedge clk);
  if(MODE==0||MODE==5||MODE==6)begin
   if(!ready||failed||id!==16'h5640||transactions!=(MODE==6?292:291))
    $fatal(1,"init mode=%0d ID=%h code=%h transactions=%0d",MODE,id,code,transactions);
   if(sensor.regs[16'h3808]!==1||sensor.regs[16'h3809]!==8'h40||
      sensor.regs[16'h380a]!==0||sensor.regs[16'h380b]!==8'hf0||
      sensor.regs[16'h4300]!==8'h61||sensor.regs[16'h3008]!==2||sensor.regs[16'h300e]!==8'h58||
      sensor.regs[16'h380c]!==8'h07||sensor.regs[16'h380d]!==8'h68||
      sensor.regs[16'h380e]!==8'h03||sensor.regs[16'h380f]!==8'hd8)
    $fatal(1,"incorrect QVGA/RGB565/streaming registers");
  end else begin
   if(ready||!failed)$fatal(1,"fault accepted");
   if((MODE==1||MODE==4)&&code!==8'he1)$fatal(1,"bus fault not rejected");
   if(MODE==2&&code!==8'he2)$fatal(1,"bad ID not rejected");
   if(MODE==3&&code!==8'h46)$fatal(1,"readback mismatch not rejected code=%h",code);
  end
  $display("OV5640_INIT_PASS mode=%0d transactions=%0d chip=%h error=%h",MODE,transactions,id,code);
  $finish;
 end
 initial begin #18000000;$fatal(1,"initialization timeout");end
endmodule
