`timescale 1ns/1ps
module tb_public_loader;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,core_busy=0,core_done=0,rd_valid=1,new_frame=0;
 reg [7:0] rd_data=0; wire swap_boundary;
 wire [11:0] rd_addr,core_load_addr,thumbnail_addr;
 wire core_load_en,core_start,thumbnail_we;wire [7:0]core_load_data,thumbnail_data;
 reg [7:0] image[0:2303];integer loaded=0,starts=0;
 gray_frame_loader dut(.*);
 always @(posedge clk)if(rd_addr<2304)rd_data<=image[rd_addr];
 always @(negedge clk)if(rst_n)begin
  if(core_load_en)begin
   if(core_load_addr!==loaded||core_load_data!==image[loaded]||!thumbnail_we||
      thumbnail_addr!==core_load_addr||thumbnail_data!==core_load_data)
    $fatal(1,"loader address/data/thumbnail mismatch at %0d",loaded);
   loaded++;
  end
  if(core_start)begin
   if(loaded!=2304||core_load_en)$fatal(1,"early start or incomplete input");starts++;
  end
 end
 task request_frame;
  begin @(negedge clk);loaded=0;new_frame=1;@(negedge clk);new_frame=0;end
 endtask
 initial begin
  $readmemh("gray0.mem",image);
  repeat(4)@(negedge clk);rst_n=1;
  core_busy=1;request_frame();repeat(8)@(negedge clk);
  if(loaded||starts||swap_boundary)$fatal(1,"busy core accepted a frame");
  core_busy=0;request_frame();wait(core_start);repeat(2)@(negedge clk);
  core_busy=1;repeat(5)@(negedge clk);core_busy=0;core_done=1;
  @(negedge clk);core_done=0;repeat(3)@(negedge clk);
  request_frame();wait(loaded==100);@(negedge clk);rd_valid=0;
  repeat(5)@(negedge clk);
  if(starts!=1||!swap_boundary)$fatal(1,"interrupted read did not abort");
  rd_valid=1;request_frame();wait(starts==2);repeat(2)@(negedge clk);
  rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  repeat(3)@(negedge clk);
  if(core_start||core_load_en||!swap_boundary)$fatal(1,"reset did not clear loader");
  $display("PUBLIC_LOADER_PASS complete_frames=2 busy=PASS interrupted_read=PASS reset=PASS");$finish;
 end
 initial begin #200000;$fatal(1,"loader timeout");end
endmodule
