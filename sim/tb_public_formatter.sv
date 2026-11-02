`timescale 1ns/1ps
module tb_public_formatter;
 localparam CASES=39;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,done=0,core_busy=0;reg [2:0]prediction=0;reg [223:0]scores=0;
 wire busy,we,commit;wire [11:0]address,data;wire [69:0]confidence_values;
 photo_formatter dut(.*);
 reg [31:0] input_scores[0:CASES*7-1];reg [11:0] expected[0:CASES*7-1];
 reg [11:0] metadata[0:2499];reg written[0:2499];
 integer c,i,j,value,total,difference,writes=0;
 function [7:0]digit(input integer number,position);
  case(position)
   0:digit=number>=1000?8'd49:8'd32;
   1:digit=number>=100?48+(number/100)%10:32;
   2:digit=48+(number/10)%10;
   3:digit=46;
   4:digit=48+number%10;
   default:digit=37;
  endcase
 endfunction
 always @(negedge clk)if(rst_n&&we)begin
  if(address>=2500||written[address])$fatal(1,"duplicate/out-of-range metadata write");
  metadata[address]=data;written[address]=1;writes++;
 end
 initial begin
  $readmemh("formatter_scores.mem",input_scores);$readmemh("formatter_expected.mem",expected);
  repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  for(c=0;c<CASES;c++)begin
   for(i=0;i<2500;i++)written[i]=0;
   writes=0;prediction=c%7;
   for(i=0;i<7;i++)scores[i*32+:32]=input_scores[c*7+i];
   done=1;@(negedge clk);done=0;
   repeat(3)@(negedge clk);scores=0; // Result must use the accepted snapshot.
   wait(commit);@(negedge clk);#1;total=0;
   if(writes!=64)$fatal(1,"metadata publication incomplete writes=%0d",writes);
   for(i=0;i<7;i++)begin
    value=confidence_values[i*10+:10];difference=value-expected[c*7+i];total+=value;
    if(value>1000||difference>2||difference< -2)$fatal(1,"softmax mismatch case=%0d class=%0d got=%0d",c,i,value);
    for(j=0;j<6;j++)if(!written[2304+i*11+j]||metadata[2304+i*11+j][7:0]!==digit(value,j))
     $fatal(1,"percentage text mismatch case=%0d class=%0d",c,i);
    if(!written[2447+i]||metadata[2447+i][6:0]>56)$fatal(1,"bar metadata invalid");
   end
   if(total!=1000||!written[2454])$fatal(1,"confidence sum or class metadata invalid");
   repeat(3)@(negedge clk);
  end
  $display("PUBLIC_FORMATTER_PASS vectors=39 includes_zero_negative_int32_boundaries=PASS sum=1000 snapshot=PASS");$finish;
 end
 initial begin #5000000;$fatal(1,"formatter timeout");end
endmodule
