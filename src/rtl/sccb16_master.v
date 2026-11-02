`timescale 1ns/1ps
// OV5640 16-bit register address, 7-bit device 0x3c; reads use STOP: read uses STOP between address-write and data-read.
// Open-drain outputs. Ninth write bit is recorded; SCCB specifies don't-care.
// OV5640 ACKs every address/data byte; timeout and NACK are errors.
module sccb16_master #(parameter CLK_HZ=50000000,BUS_HZ=100000,
 parameter REQUIRE_ACK=1, WATCHDOG_TICKS=4096)(
 input wire clk,rst_n,start,read_op,input wire [15:0] reg_addr,input wire [7:0] write_data,
 input wire scl_in,sda_in,output reg scl_low,sda_low,
 output reg busy,done,error,output reg [7:0] read_data,
 output reg nack_seen);
 localparam DIV=(CLK_HZ/(BUS_HZ*4)<1)?1:CLK_HZ/(BUS_HZ*4);
 localparam IDLE=0,BUS_FREE=1,START_A=2,START_B=3,
 TX_SETUP=4,TX_RISE=5,TX_SAMPLE=6,TX_FALL=7,
 ACK_SETUP=8,ACK_RISE=9,ACK_SAMPLE=10,ACK_FALL=11,
 RX_SETUP=12,RX_RISE=13,RX_SAMPLE=14,RX_FALL=15,
 NA_SETUP=16,NA_RISE=17,NA_SAMPLE=18,NA_FALL=19,
 STOP_A=20,STOP_B=21,STOP_C=22,STOP_D=23;
 reg [4:0] state;
 reg [31:0] divider,watchdog;
 reg op_read,second;
 reg [15:0] address;
 reg [7:0] value,tx,rx;
 reg [2:0] bitno;
 reg [1:0] byte_no;
 (* ASYNC_REG="TRUE" *) reg [1:0] scl_sync,sda_sync;
 always @(posedge clk) begin
   if(!rst_n) begin scl_sync<=3;sda_sync<=3;end
   else begin scl_sync<={scl_sync[0],scl_in};sda_sync<={sda_sync[0],sda_in};end
 end
 always @(posedge clk) begin
   if(!rst_n) begin
     state<=IDLE;divider<=0;watchdog<=0;scl_low<=0;sda_low<=0;
     busy<=0;done<=0;error<=0;read_data<=0;nack_seen<=0;
     op_read<=0;second<=0;address<=0;value<=0;tx<=0;rx<=0;bitno<=7;byte_no<=0;
   end else begin
     done<=0;
     if(state==IDLE) begin
       divider<=0;scl_low<=0;sda_low<=0;
       if(start) begin
         busy<=1;error<=0;nack_seen<=0;watchdog<=0;
         op_read<=read_op;second<=0;address<=reg_addr;value<=write_data;
         tx<=8'h78;bitno<=7;byte_no<=0;state<=BUS_FREE;
       end
     end else if(divider==DIV-1) begin
       divider<=0;watchdog<=watchdog+1;
       if(watchdog==WATCHDOG_TICKS-1) begin
         state<=IDLE;scl_low<=0;sda_low<=0;busy<=0;done<=1;error<=1;
       end else case(state)
         BUS_FREE: if(scl_sync[1] && sda_sync[1]) state<=START_A;
         START_A: begin sda_low<=1;state<=START_B;end
         START_B: begin scl_low<=1;state<=TX_SETUP;end
         TX_SETUP: begin sda_low<=!tx[bitno];state<=TX_RISE;end
         TX_RISE: begin scl_low<=0;state<=TX_SAMPLE;end
         TX_SAMPLE: if(scl_sync[1]) state<=TX_FALL;
         TX_FALL: begin
           scl_low<=1;
           if(bitno==0) state<=ACK_SETUP;
           else begin bitno<=bitno-1'b1;state<=TX_SETUP;end
         end
         ACK_SETUP: begin sda_low<=0;state<=ACK_RISE;end
         ACK_RISE: begin scl_low<=0;state<=ACK_SAMPLE;end
         ACK_SAMPLE: if(scl_sync[1]) begin
           if(sda_sync[1]) begin nack_seen<=1;if(REQUIRE_ACK) error<=1;end
           state<=ACK_FALL;
         end
         ACK_FALL: begin
           scl_low<=1;bitno<=7;
           if(second) begin rx<=0;state<=RX_SETUP;end
           else if(byte_no==0) begin tx<=address[15:8];byte_no<=1;state<=TX_SETUP;end
           else if(byte_no==1) begin tx<=address[7:0];byte_no<=2;state<=TX_SETUP;end
           else if(byte_no==2 && !op_read) begin tx<=value;byte_no<=3;state<=TX_SETUP;end
           else state<=STOP_A;
         end
         RX_SETUP: begin sda_low<=0;state<=RX_RISE;end
         RX_RISE: begin scl_low<=0;state<=RX_SAMPLE;end
         RX_SAMPLE: if(scl_sync[1]) begin rx<={rx[6:0],sda_sync[1]};state<=RX_FALL;end
         RX_FALL: begin
           scl_low<=1;
           if(bitno==0) begin read_data<=rx;state<=NA_SETUP;end
           else begin bitno<=bitno-1'b1;state<=RX_SETUP;end
         end
         NA_SETUP: begin sda_low<=0;state<=NA_RISE;end
         NA_RISE: begin scl_low<=0;state<=NA_SAMPLE;end
         NA_SAMPLE: if(scl_sync[1]) state<=NA_FALL;
         NA_FALL: begin scl_low<=1;state<=STOP_A;end
         STOP_A: begin sda_low<=1;state<=STOP_B;end
         STOP_B: begin scl_low<=0;state<=STOP_C;end
         STOP_C: if(scl_sync[1]) begin sda_low<=0;state<=STOP_D;end
         STOP_D: begin
           if(op_read && !second && !error) begin
             second<=1;tx<=8'h79;byte_no<=0;bitno<=7;state<=BUS_FREE;
           end else begin state<=IDLE;busy<=0;done<=1;end
         end
         default: begin state<=IDLE;busy<=0;done<=1;error<=1;end
       endcase
     end else divider<=divider+1;
   end
 end
endmodule
