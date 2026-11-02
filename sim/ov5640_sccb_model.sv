`timescale 1ns/1ps
// Independent wire-level SCCB slave model: decodes SCL/SDA, no DUT state access.
module ov5640_sccb_model #(parameter STARTUP_READ_GUARD_NS=0,ONE_BAD_VERIFY=0)(input wire rst_n,input wire scl,inout wire sda,
 input wire suppress_ack,bad_id,corrupt_readback);
 reg drive_low=0;
 assign sda=drive_low?1'b0:1'bz;
 reg [7:0] regs[0:65535];
 reg [15:0] ptr;reg [7:0] shift,send_value;
 integer state=0,bits=0,byte_index=0,read_bit=7;
 reg selected=0,read_mode=0;
 time stream_started=0;
 reg transient_used=0;
 localparam RX=1,ACK_SETUP=2,ACK_HOLD=3,ACK_DONE=4,TX=5,TX_DONE=6,MASTER_NA=7;
 integer i;
 initial begin
   for(i=0;i<65536;i++)regs[i]=0;
   regs[16'h300a]=8'h56;regs[16'h300b]=8'h40;ptr=0;shift=0;send_value=0;
 end
 always @(negedge sda) if(rst_n && scl===1'b1) begin
   state=RX;bits=0;byte_index=0;shift=0;selected=0;read_mode=0;
 end
 always @(posedge sda) if(rst_n && scl===1'b1) begin state=0;drive_low=0;end
 always @(posedge scl) if(rst_n) begin
   case(state)
    RX: begin
      shift={shift[6:0],sda};
      if(bits==7) begin
        if(byte_index==0) begin selected=(shift==8'h78 || shift==8'h79);read_mode=shift[0];end
        else if(byte_index==1)ptr[15:8]=shift;
        else if(byte_index==2)ptr[7:0]=shift;
        else if(selected) begin
          if(ptr==16'h3008 && shift==8'h82) regs[ptr]=0;
          else begin regs[ptr]=shift;if(ptr==16'h3008&&shift==8'h02)stream_started=$time;end
        end
        byte_index=byte_index+1;bits=0;state=ACK_SETUP;
      end else bits=bits+1;
    end
    ACK_HOLD:state=ACK_DONE;
    TX:if(read_bit==0)state=TX_DONE;else read_bit=read_bit-1;
    MASTER_NA:begin
      if(sda!==1'b1)$fatal(1,"SCCB master must release NA bit");
      state=0;
    end
   endcase
 end
 always @(negedge scl) if(rst_n) begin
   case(state)
    ACK_SETUP:begin drive_low=selected&&!suppress_ack;state=ACK_HOLD;end
    ACK_DONE:begin
      drive_low=0;
      if(read_mode && selected) begin
        send_value=regs[ptr];
        if(ptr==16'h300a && bad_id)send_value=0;
        if(ptr==16'h3809 && corrupt_readback)send_value=0;
        if(ptr==16'h3034 && STARTUP_READ_GUARD_NS && $time-stream_started<STARTUP_READ_GUARD_NS)send_value=0;
        if(ptr==16'h3809 && ONE_BAD_VERIFY && !transient_used)begin send_value=0;transient_used=1;end
        read_bit=7;drive_low=!send_value[7];state=TX;
      end else state=RX;
    end
    TX:drive_low=!send_value[read_bit];
    TX_DONE:begin drive_low=0;state=MASTER_NA;end
   endcase
 end
endmodule
