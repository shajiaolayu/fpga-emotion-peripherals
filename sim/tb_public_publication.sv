`timescale 1ns/1ps
// Verify real display-buffer publication and CDC acknowledgement, not visual layout.
module tb_public_publication;
 reg clk=0,pix=0;always #5 clk=~clk;always #7 pix=~pix;
 reg rst_n=0,pix_rst_n=0,gray_we=0,done=0,core_busy=0;
 reg [11:0]gray_addr=0;reg [7:0]gray_data=0;reg [2:0]prediction=0;reg [223:0]scores=0;
 wire pending;reg camera_ready=1,camera_error=0;reg [23:0]in_rgb=0;
 reg in_de=0,in_hs=0,in_vs=0;reg [10:0]in_x=25;reg [9:0]in_y=25;
 wire [23:0]rgb;wire de,hs,vs;reg manual_mode=1,work_busy=0;
 wire source_bank,display_bank,display_valid;
 photo_dashboard_osd #(.CLK_HZ(100000)) dut(.*);
 integer i,number=0;reg old_bank,target_bank;
 task transaction(input [2:0]category,input [7:0]value);
  begin
   old_bank=display_bank;target_bank=source_bank;
   @(negedge clk);gray_we=1;gray_addr=0;gray_data=value;core_busy=1;
   @(negedge clk);gray_addr=1;gray_data=value+1;
   @(negedge clk);gray_we=0;
   repeat(20)@(negedge clk);
   for(i=0;i<7;i++)scores[i*32+:32]=i*4096-12288;
   prediction=category;core_busy=0;done=1;
   @(negedge clk);done=0;
   wait(pending);wait(dut.req==target_bank);repeat(6)@(negedge pix);
   if(display_bank!==old_bank||!pending)$fatal(1,"display changed before the blanking boundary");
   if(target_bank)begin
    if(dut.bank1[0]!=={4'd0,value}||dut.bank1[1]!=={4'd0,(value+8'd1)}||dut.bank1[2454][6:4]!==category)
     $fatal(1,"image/class metadata not in the same publication bank");
   end else begin
    if(dut.bank0[0]!=={4'd0,value}||dut.bank0[1]!=={4'd0,(value+8'd1)}||dut.bank0[2454][6:4]!==category)
     $fatal(1,"image/class metadata not in the same publication bank");
   end
   @(negedge pix);in_x=0;in_y=720;
   @(negedge pix);in_x=25;in_y=25;
   wait(!pending);repeat(4)@(negedge clk);
   if(!display_valid||display_bank!==target_bank||source_bank===target_bank)
    $fatal(1,"publication ownership/CDC acknowledgement mismatch");
   number++;
  end
 endtask
 initial begin
  repeat(6)@(negedge clk);rst_n=1;pix_rst_n=1;
  repeat(10)@(negedge clk);transaction(2,8'h35);transaction(5,8'ha1);
  rst_n=0;pix_rst_n=0;repeat(8)@(negedge clk);
  if(display_valid||pending)$fatal(1,"reset retained a pending/displayed transaction");
  $display("PUBLIC_PUBLICATION_PASS transactions=%0d metadata_atomic=PASS blanking=PASS acknowledgement=PASS reset=PASS",number);$finish;
 end
 initial begin #1000000;$fatal(1,"publication timeout");end
endmodule
