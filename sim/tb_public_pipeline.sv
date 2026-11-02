`timescale 1ns/1ps
// Test the current overlap/prefetch consumer, not the archived serial pipeline.
// Display publication is acknowledged by a testbench handshake; no UI layout assertion.
module tb_public_pipeline;
 reg clk=0,pixel_clk=0;always #5 clk=~clk;always #10 pixel_clk=~pixel_clk;
 reg arst_n=0,hold_inference=0,manual_mode=1,shutter=0;
 reg photo_write_bank=1,photo_read_bank=0,photo_valid=0,result_pending=0;
 reg sof=0,eof=0,frame_ok=0,pv=0;reg [15:0]pixel=0;reg [9:0]cx=0,cy=0;
 wire [23:0]video_rgb;wire video_de,video_hsync,video_vsync;
 wire [2:0]prediction;wire [223:0]scores;wire inference_busy,inference_done;
 wire thumbnail_we;wire [11:0]thumbnail_addr;wire [7:0]thumbnail_data;
 wire [31:0]video_dropped;wire work_busy;wire [10:0]video_x;wire [9:0]video_y;
 photo_overlap_pipeline #(.SIM_MAC(1)) dut(.*);
 reg [15:0]image0[0:76799],image1[0:76799];reg [7:0]gray0[0:2303],gray1[0:2303];
 integer expected_tag=0,loaded=0,results=0,i,xx,yy,target;
 reg [223:0]held_scores;reg held_bank;
 always @(negedge clk)if(arst_n)begin
  if(thumbnail_we)begin
   if(thumbnail_addr!==loaded||thumbnail_data!==(expected_tag?gray1[loaded]:gray0[loaded]))
    $fatal(1,"synthetic frame/thumbnail ownership mismatch index=%0d",loaded);
   loaded++;
  end
  if(dut.consumer.write_enable&&photo_valid&&dut.consumer.write_bank==photo_read_bank)
   $fatal(1,"writing a displayed photo bank");
  if(inference_done)begin
   if(loaded!=2304||prediction!==(expected_tag?3'd0:3'd6))$fatal(1,"result/input identity mismatch");
   for(i=0;i<7;i++)if($signed(scores[i*32+:32])!==(expected_tag?(1024-i*256):(i*256-1024)))
    $fatal(1,"test-double result was mixed between frames");
   results++;loaded=0;
  end
 end
 task trigger;
  begin @(negedge clk);shutter=1;@(negedge clk);shutter=0;end
 endtask
 task camera_frame(input integer tag);
  begin
   @(negedge clk);sof=1;@(negedge clk);sof=0;
   for(yy=0;yy<240;yy++)for(xx=0;xx<320;xx++)begin
    cx=xx;cy=yy;pixel=tag?image1[yy*320+xx]:image0[yy*320+xx];pv=1;
    @(negedge clk);
   end
   pv=0;eof=1;frame_ok=1;@(negedge clk);eof=0;frame_ok=0;
  end
 endtask
 task acknowledge;
  begin
   @(negedge clk);result_pending=1;repeat(6)@(negedge clk);
   if(!work_busy)$fatal(1,"photo owner released before display acknowledgement");
   photo_read_bank=photo_write_bank;photo_write_bank=!photo_write_bank;photo_valid=1;
   result_pending=0;repeat(8)@(negedge clk);
   if(work_busy)$fatal(1,"display acknowledgement did not release consumer");
  end
 endtask
 initial begin
  $readmemh("camera0.mem",image0);$readmemh("camera1.mem",image1);
  $readmemh("gray0.mem",gray0);$readmemh("gray1.mem",gray1);
  repeat(10)@(negedge clk);arst_n=1;repeat(15)@(negedge clk);
  camera_frame(0);repeat(15)@(negedge clk);
  if(results||work_busy)$fatal(1,"manual mode consumed an untriggered frame");
  expected_tag=0;trigger();camera_frame(0);wait(inference_busy);trigger();
  wait(results==1);acknowledge();held_scores=scores;held_bank=photo_read_bank;
  camera_frame(1);repeat(50)@(negedge clk);
  if(results!=1||scores!==held_scores||photo_read_bank!==held_bank||work_busy)
   $fatal(1,"manual result did not remain frozen or busy trigger queued a shot");
  expected_tag=1;trigger();camera_frame(1);wait(results==2);acknowledge();
  manual_mode=0;expected_tag=0;camera_frame(0);wait(results==3);manual_mode=1;acknowledge();
  arst_n=0;repeat(5)@(negedge clk);arst_n=1;repeat(15)@(negedge clk);
  if(work_busy||inference_busy||inference_done)$fatal(1,"reset recovery failed");
  $display("PUBLIC_PIPELINE_PASS synthetic_frames=3 compared_inputs=6912 publication_ack=PASS manual_hold=PASS busy_flip=PASS continuous=PASS reset=PASS");$finish;
 end
 initial begin #30000000;$fatal(1,"pipeline timeout results=%0d consumer=%0d",results,dut.consumer.state);end
endmodule
