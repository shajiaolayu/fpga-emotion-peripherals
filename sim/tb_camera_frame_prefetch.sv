`timescale 1ns/1ps
module tb_camera_frame_prefetch #(parameter W=8,H=6);
 localparam N=W*H;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sof=0,eof=0,ok=0,pv=0,request=0,manual=0,shutter=0,consumer_busy=0;
 reg [15:0]pixel=0;reg [9:0]x=0,y=0;
 wire os,oe,oo,op;wire [15:0]od;wire [9:0]ox,oy;wire [31:0]replayed,dropped;
 camera_frame_prefetch #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst_n,sof,eof,ok,pv,pixel,x,y,
  request,manual,shutter,consumer_busy,os,oe,oo,op,od,ox,oy,replayed,dropped);
 integer count=0,results=0,expected_tag=-1,received_tag=-1;
 reg in_frame=0;
 function [15:0]value_at(input integer tag,index);
  value_at=(tag*16'h1357)^index^((index>>6)*16'h002d);
 endfunction
 always @(negedge clk)if(rst_n)begin
  if(dut.write_enable&&dut.replay_active&&dut.write_bank==dut.replay_bank)$fatal(1,"write/replay ownership collision");
  if(dut.pending_valid&&dut.capture_active&&dut.pending_bank==dut.capture_bank)$fatal(1,"capturing into pending frame");
  if(os)begin
   if(in_frame)$fatal(1,"overlapping replay");
   in_frame=1;count=0;received_tag=-1;
  end
  if(op)begin
   if(!in_frame||ox!==count%W||oy!==count/W)$fatal(1,"coordinate sequence mismatch %0d",count);
   if(received_tag<0)received_tag=expected_tag;
   if(expected_tag>=0&&od!==value_at(expected_tag,count))$fatal(1,"mixed/stale frame pixel %0d got %h tag=%0d",count,od,received_tag);
   count++;
  end
  if(oe)begin
   if(!in_frame||!oo||count!=N)$fatal(1,"incomplete replay");
   if(expected_tag>=0&&received_tag!=expected_tag)$fatal(1,"wrong selected frame expected=%0d got=%0d",expected_tag,received_tag);
   in_frame=0;results++;
  end
 end
 task camera_frame(input integer tag,input bit valid_frame);
  integer i;
  begin
   @(negedge clk);sof=1;@(negedge clk);sof=0;
   for(i=0;i<N;i++)begin
    x=i%W;y=i/W;pixel=value_at(tag,i);pv=1;
    @(negedge clk);pv=0;@(negedge clk);
   end
   eof=1;ok=valid_frame;@(negedge clk);eof=0;ok=0;repeat(3)@(negedge clk);
  end
 endtask
 task consume(input integer tag);
  integer target;
  begin
   target=results+1;expected_tag=tag;request=1;
   wait(os);@(negedge clk);request=0;consumer_busy=1;
   wait(results==target);repeat(4)@(negedge clk);consumer_busy=0;
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  camera_frame(1,1);camera_frame(2,1);camera_frame(3,0);
  // A rejected camera frame must not replace the last valid pending frame.
  consume(2);
  camera_frame(4,1);
  fork consume(4);camera_frame(5,1);join
  consume(5);
  // Back-to-back camera publication and dispatch must retain both owners.
  camera_frame(6,1);fork consume(6);begin repeat(130)@(negedge clk);camera_frame(7,1);end join
  consume(7);
  // A manual trigger must select a frame starting after the trigger.
  manual=1;request=0;camera_frame(8,1);
  expected_tag=10;request=1;shutter=1;@(negedge clk);shutter=0;
  fork
   begin camera_frame(9,0);camera_frame(10,1);end
   begin
    wait(os);@(negedge clk);request=0;consumer_busy=1;
    shutter=1;@(negedge clk);shutter=0; // busy flip is not a new request
    wait(results==6);repeat(4)@(negedge clk);consumer_busy=0;
   end
  join
  repeat(20)@(negedge clk);if(os||dut.manual_wait)$fatal(1,"busy flip queued extra photo");
  manual=0;camera_frame(11,1);expected_tag=11;request=1;wait(op);
  @(negedge clk);rst_n=0;request=0;in_frame=0;
  repeat(5)@(negedge clk);rst_n=1;camera_frame(12,1);consume(12);
  $display("CAMERA_PREFETCH_PASS pixels=%0d complete_frame_ownership=PASS latest_valid=PASS manual_freshness=PASS busy_flip=PASS reset=PASS results=%0d",N,results);
  $finish;
 end
 initial begin #(N*20000);$fatal(1,"timeout results=%0d state=%0d",results,dut.state);end
endmodule
