`timescale 1ns/1ps
module tb_async_event_fifo;
 reg wc=0,rc=0;always #7 wc=~wc;always #11 rc=~rc;
 reg rst=0,wen=0,ren=0;reg [39:0] wd=0;
 wire full,overflow,rv,empty;wire [39:0] rd;
 async_event_fifo #(.ADDR_BITS(3)) dut(wc,rst,wen,wd,full,overflow,rc,rst,ren,rd,rv,empty);
 integer expected=0,received=0,i;
 reg check=1;
 always @(negedge rc)if(rst&&rv&&check)begin
  if(rd!==expected)$fatal(1,"FIFO order/CDC got=%0d expected=%0d",rd,expected);
  expected++;received++;
 end
 initial begin
  #100;rst=1;
  // Force full and overflow, then check accepted data survived unmodified.
  for(i=0;i<12;i++)begin @(negedge wc);wen=1;wd=i;end
  @(negedge wc);wen=0;
  if(!full||!overflow)$fatal(1,"full/overflow did not latch");
  ren=1;wait(received==8);repeat(6)@(negedge rc);
  if(!empty||received!=8)$fatal(1,"overflow corrupted FIFO");
  rst=0;#100;rst=1;expected=0;received=0;
  // More than 100 pointer wraps, while asynchronous reader applies stalls.
  fork
   begin
    for(i=0;i<1000;i++)begin
     @(negedge wc);wen=0;
     while(full)@(negedge wc);
     wd=i;wen=1;@(negedge wc);wen=0;
    end
   end
   begin
    repeat(1000)begin repeat(3)@(negedge rc);ren=0;repeat(2)@(negedge rc);ren=1;end
   end
  join
  wait(received==1000);repeat(5)@(negedge rc);
  if(!empty||overflow)$fatal(1,"wraparound/backpressure fault");
  check=0;rst=0;#100;rst=1;repeat(8)@(negedge rc);
  if(rv||!empty||overflow)$fatal(1,"reset did not flush FIFO");
  $display("ASYNC_EVENT_FIFO_PASS accepted=1000 full=PASS overflow=PASS wrap=PASS reset=PASS");$finish;
 end
 initial begin #1000000;$fatal(1,"FIFO timeout received=%0d",received);end
endmodule
