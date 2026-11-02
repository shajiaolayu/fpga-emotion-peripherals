`timescale 1ns/1ps
module tb_public_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sw0=1,sw1=1;wire manual_mode,shutter;
 integer pulses=0;reg previous=0;
 photo_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(4)) dut(.*);
 always @(negedge clk)begin
  if(rst_n&&shutter)begin
   if(previous)$fatal(1,"shutter pulse exceeded one clock");pulses++;
  end
  previous=shutter;
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
  if(!manual_mode||pulses)$fatal(1,"initial switch position triggered a shot");
  sw1=0;@(negedge clk);sw1=1;repeat(12)@(negedge clk);
  if(pulses)$fatal(1,"switch bounce triggered a shot");
  sw1=0;repeat(16)@(negedge clk);sw1=1;repeat(16)@(negedge clk);
  if(pulses!=2)$fatal(1,"stable flips must trigger in both directions");
  sw0=0;repeat(16)@(negedge clk);
  if(manual_mode||pulses!=2)$fatal(1,"mode switch triggered a shutter");
  $display("PUBLIC_CONTROLS_PASS baseline=PASS debounce=PASS bidirectional=PASS");$finish;
 end
 initial begin #20000;$fatal(1,"controls timeout");end
endmodule
