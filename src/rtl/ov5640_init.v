`timescale 1ns/1ps
// OV5640 DVP, 24MHz XCLK, 28MHz PCLK, QVGA RGB565 MSB first.
module ov5640_init #(parameter CLK_HZ=50000000,TEST_PATTERN=0,
 parameter WAIT_MS=CLK_HZ/1000)(
 input wire clk,rst_n,bus_busy,bus_done,bus_error,input wire [7:0] bus_data,
 output reg bus_start,bus_read,output reg [15:0] bus_addr,output reg [7:0] bus_write,
 output reg reset_n,pwdn,ready,failed,output reg [7:0] error_code,
 output reg [15:0] chip_id);
 `include "ov5640_registers.vh"
 localparam VERIFY_COUNT=20;
 function [23:0] check_cfg(input integer i);
  case(i)
   0:check_cfg=24'h303418;1:check_cfg=24'h303511;
   2:check_cfg=24'h303638;3:check_cfg=24'h303716;
   4:check_cfg=24'h310801;5:check_cfg=24'h380801;
   6:check_cfg=24'h380940;7:check_cfg=24'h380a00;
   8:check_cfg=24'h380bf0;9:check_cfg=24'h430061;
   10:check_cfg=24'h501f01;11:check_cfg=24'h474020;
   12:check_cfg=24'h3017ff;13:check_cfg=24'h3018f3;
   14:check_cfg=24'h300802;
   15:check_cfg={16'h503d,(TEST_PATTERN ? 8'h80 : 8'h00)};
   16:check_cfg=24'h380c07;17:check_cfg=24'h380d68;
   18:check_cfg=24'h380e03;19:check_cfg=24'h380fd8;
   default:check_cfg=0;
  endcase
 endfunction
 localparam POWER=0,PWD_WAIT=1,RESET_WAIT=2,ID_HI=3,ID_LO=4,
  SELECT_CLOCK=5,SOFT_RESET=6,SOFT_WAIT=7,CONFIG=8,VERIFY=9,
  SETTLE=10,DONE=11,WAIT_BUS=12,FAIL=13,CONFIG_SETTLE=14,VERIFY_RETRY=15;
 reg [3:0] state,return_state;
 reg [31:0] delay_count;
 reg [8:0] index;
 reg [4:0] verify_index;
 reg [7:0] expected;
 reg [1:0] verify_retries;
 wire [23:0] entry=cfg(index),check_entry=check_cfg(verify_index);
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=POWER;return_state<=POWER;delay_count<=0;index<=0;verify_index<=0;
   bus_start<=0;bus_read<=0;bus_addr<=0;bus_write<=0;expected<=0;verify_retries<=0;
   reset_n<=0;pwdn<=1;ready<=0;failed<=0;error_code<=0;chip_id<=0;
  end else begin
   bus_start<=0;
   case(state)
    POWER:if(delay_count>=20*WAIT_MS-1)begin
      pwdn<=0;delay_count<=0;state<=PWD_WAIT;
     end else delay_count<=delay_count+1;
    PWD_WAIT:if(delay_count>=10*WAIT_MS-1)begin
      reset_n<=1;delay_count<=0;state<=RESET_WAIT;
     end else delay_count<=delay_count+1;
    RESET_WAIT:if(delay_count>=20*WAIT_MS-1)begin delay_count<=0;state<=ID_HI;end
     else delay_count<=delay_count+1;
    ID_HI,ID_LO,SELECT_CLOCK,SOFT_RESET,CONFIG,VERIFY:if(!bus_busy)begin
     bus_start<=1;bus_read<=state==ID_HI||state==ID_LO||state==VERIFY;
     case(state)
      ID_HI:begin bus_addr<=16'h300a;return_state<=ID_LO;end
      ID_LO:begin bus_addr<=16'h300b;return_state<=SELECT_CLOCK;end
      SELECT_CLOCK:begin bus_addr<=16'h3103;bus_write<=8'h11;return_state<=SOFT_RESET;end
      SOFT_RESET:begin bus_addr<=16'h3008;bus_write<=8'h82;return_state<=SOFT_WAIT;end
      CONFIG:begin
       bus_addr<=entry[23:8];bus_write<=entry[7:0];
       return_state<=index==CONFIG_COUNT-1?CONFIG_SETTLE:CONFIG;
      end
      VERIFY:begin
       bus_addr<=check_entry[23:8];expected<=check_entry[7:0];
       return_state<=verify_index==VERIFY_COUNT-1?SETTLE:VERIFY;
      end
     endcase
     state<=WAIT_BUS;
    end
    SOFT_WAIT:if(delay_count>=10*WAIT_MS-1)begin delay_count<=0;state<=CONFIG;end
     else delay_count<=delay_count+1;
    // Real AF-OV5640-V1.0 returned 00 for the first immediate PLL read, while
    // later independent reads returned the programmed 18. Allow the sensor's
    // post-configuration clock/stream state to settle before validating it.
    CONFIG_SETTLE:if(delay_count>=50*WAIT_MS-1)begin delay_count<=0;state<=VERIFY;end
     else delay_count<=delay_count+1;
    VERIFY_RETRY:if(delay_count>=10*WAIT_MS-1)begin delay_count<=0;state<=VERIFY;end
     else delay_count<=delay_count+1;
    WAIT_BUS:if(bus_done)begin
     if(bus_error)begin failed<=1;error_code<=8'he1;state<=FAIL;end
     else if(bus_read&&bus_addr==16'h300a)begin
      chip_id[15:8]<=bus_data;
      if(bus_data!=8'h56)begin failed<=1;error_code<=8'he2;state<=FAIL;end
      else state<=return_state;
     end else if(bus_read&&bus_addr==16'h300b)begin
      chip_id[7:0]<=bus_data;
      if(bus_data!=8'h40)begin failed<=1;error_code<=8'he3;state<=FAIL;end
      else state<=return_state;
     end else if(bus_read)begin
      if(bus_data!=expected)begin
       if(verify_retries<2)begin verify_retries<=verify_retries+1'b1;delay_count<=0;state<=VERIFY_RETRY;end
       else begin failed<=1;error_code<=8'h40+verify_index;state<=FAIL;end
      end else begin verify_retries<=0;verify_index<=verify_index+1'b1;state<=return_state;end
     end else begin
      if(return_state==CONFIG||return_state==CONFIG_SETTLE)index<=index+1'b1;
      state<=return_state;
     end
    end
    SETTLE:if(delay_count>=50*WAIT_MS-1)begin ready<=1;state<=DONE;end
     else delay_count<=delay_count+1;
    DONE:ready<=1;
    FAIL:begin ready<=0;failed<=1;end
    default:begin ready<=0;failed<=1;error_code<=8'hef;state<=FAIL;end
   endcase
  end
 end
endmodule
