`timescale 1ns/1ps
// Display-only softmax at the raw/8192 scale used in R8 cross-entropy training.
// Largest-remainder rounding makes the seven displayed values sum to100.0%.
(* use_dsp="no" *) module photo_formatter #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,done,core_busy,input wire [2:0] prediction,
 input wire [223:0] scores,output wire busy,output reg we,
 output reg [11:0] address,data,output reg commit,
 output wire [69:0] confidence_values);
 `include "photo_dashboard_glyphs.vh"
 // Keep asynchronous reset assertion behind a clocked boundary at ROM pins.
 (* DONT_TOUCH="TRUE" *) reg local_rst_n;
 always @(posedge clk)local_rst_n<=rst_n;
 localparam IDLE=0,MAXIMUM=1,DELTA=2,EXP_READ=3,EXP_ACCUM=4,
  DIV_SETUP=5,DIVIDE=6,DIV_STORE=7,CORR_INIT=8,CORR_RESET=9,
  CORR_SCAN=10,CORR_APPLY=11,DIGIT_SETUP=12,BCD=13,WRITE_TEXT=14,
  CLASS_META=15,BAR_SETUP=16,BAR_WRITE=17,PUBLISH=18;
 reg [4:0] state;
 assign busy=state!=IDLE;
 reg [223:0] saved_scores;
 reg [2:0] saved_class,index,scan_index,best_index;
 reg signed [31:0] maximum;
 wire signed [31:0] current_score=$signed(saved_scores[index*32+:32]);
 wire signed [32:0] delta=$signed({maximum[31],maximum})-$signed({current_score[31],current_score});
 wire [32:0] rounded_delta=delta+33'd64;
 reg [9:0] exp_index;
 reg exp_zero;
 (* rom_style="block" *)reg [20:0] exp_lut[0:1023];
 initial $readmemh("confidence_exp.mem",exp_lut);
 reg [20:0] exp_value,weights[0:6];
 reg [23:0] sum_weight,remainders[0:6],best_remainder;
 reg [9:0] confidence[0:6];
 genvar g;
 generate for(g=0;g<7;g=g+1)begin: confidence_outputs
  assign confidence_values[g*10+:10]=confidence[g];
 end endgenerate
 reg [13:0] sum_floor;
 reg [3:0] remaining;
 reg [6:0] assigned;
 reg [31:0] dividend,quotient;
 reg [23:0] divisor;
 reg [24:0] remainder;
 wire [24:0] shifted_remainder={remainder[23:0],dividend[31]};
 wire subtract=shifted_remainder>={1'b0,divisor};
 wire [31:0] next_quotient={quotient[30:0],subtract};
 reg [5:0] bits_left;
 reg division_is_bar;
 wire [31:0] wide_weight={11'd0,weights[index]};
 wire [31:0] weighted_thousand=(wide_weight<<10)-(wide_weight<<4)-(wide_weight<<3);
 reg [3:0] field,position;
 reg [9:0] binary;
 reg [15:0] decimal,adjusted;
 wire [2:0] selected_class=saved_class<7?saved_class:3'd0;
 wire [31:0] wide_confidence={22'd0,confidence[index]};
 reg [7:0] character;
 integer i;
 always @*begin
  adjusted=decimal;
  for(integer d=0;d<4;d=d+1)if(decimal[d*4+:4]>=5)adjusted[d*4+:4]=decimal[d*4+:4]+4'd3;
  case(position)
   0:character=decimal[15:12]!=0?48+decimal[15:12]:32;
   1:character=decimal[15:8]!=0?48+decimal[11:8]:32;
   2:character=48+decimal[7:4];
   3:character=46;
   4:character=48+decimal[3:0];
   default:character=37;
  endcase
 end
 always @(posedge clk)begin
  if(!local_rst_n)begin
   state<=IDLE;we<=0;commit<=0;address<=0;data<=0;saved_scores<=0;saved_class<=7;
   index<=0;scan_index<=0;best_index<=0;maximum<=32'sh80000000;
   exp_index<=0;exp_zero<=0;exp_value<=0;sum_weight<=0;sum_floor<=0;
   best_remainder<=0;remaining<=0;assigned<=0;dividend<=0;quotient<=0;
   divisor<=1;remainder<=0;bits_left<=0;division_is_bar<=0;
   field<=0;position<=0;binary<=0;decimal<=0;
   for(i=0;i<7;i=i+1)begin weights[i]<=0;remainders[i]<=0;confidence[i]<=0;end
  end else begin
   we<=0;commit<=0;
   case(state)
    IDLE:if(done)begin
     saved_scores<=scores;saved_class<=prediction;maximum<=32'sh80000000;
     index<=0;sum_weight<=0;sum_floor<=0;assigned<=0;division_is_bar<=0;
     state<=MAXIMUM;
    end
    MAXIMUM:begin
     if(current_score>maximum)maximum<=current_score;
     if(index==6)begin index<=0;state<=DELTA;end else index<=index+1'b1;
    end
    DELTA:begin
     exp_zero<=delta>=33'd131072||rounded_delta>=33'd131072;
     exp_index<=rounded_delta[16:7];state<=EXP_READ;
    end
    EXP_READ:begin exp_value<=exp_zero?21'd0:exp_lut[exp_index];state<=EXP_ACCUM;end
    EXP_ACCUM:begin
     weights[index]<=exp_value;sum_weight<=sum_weight+{3'd0,exp_value};
     if(index==6)begin index<=0;state<=DIV_SETUP;end else begin index<=index+1'b1;state<=DELTA;end
    end
    DIV_SETUP:begin
     divisor<=sum_weight;dividend<=weighted_thousand;quotient<=0;remainder<=0;
     bits_left<=31;division_is_bar<=0;state<=DIVIDE;
    end
    DIVIDE:begin
     dividend<=dividend<<1;quotient<=next_quotient;
     remainder<=subtract?shifted_remainder-{1'b0,divisor}:shifted_remainder;
     if(bits_left==0)state<=division_is_bar?BAR_WRITE:DIV_STORE;else bits_left<=bits_left-1'b1;
    end
    DIV_STORE:begin
     confidence[index]<=quotient[9:0];remainders[index]<=remainder[23:0];sum_floor<=sum_floor+quotient[9:0];
     if(index==6)begin index<=0;state<=CORR_INIT;end else begin index<=index+1'b1;state<=DIV_SETUP;end
    end
    CORR_INIT:begin
     remaining<=14'd1000-sum_floor;assigned<=0;field<=0;
     state<=sum_floor==1000?DIGIT_SETUP:CORR_RESET;
    end
    CORR_RESET:begin scan_index<=0;best_index<=0;best_remainder<=0;state<=CORR_SCAN;end
    CORR_SCAN:begin
     if(!assigned[scan_index]&&remainders[scan_index]>best_remainder)begin
      best_remainder<=remainders[scan_index];best_index<=scan_index;
     end
     if(scan_index==6)state<=CORR_APPLY;else scan_index<=scan_index+1'b1;
    end
    CORR_APPLY:begin
     confidence[best_index]<=confidence[best_index]+1'b1;assigned[best_index]<=1;
     remaining<=remaining-1'b1;
     if(remaining==1)begin field<=0;state<=DIGIT_SETUP;end else state<=CORR_RESET;
    end
    DIGIT_SETUP:begin
     binary<=field==7?confidence[selected_class]:confidence[field];decimal<=0;
     bits_left<=9;position<=0;state<=BCD;
    end
    BCD:begin
     decimal<={adjusted[14:0],binary[9]};binary<=binary<<1;
     if(bits_left==0)state<=WRITE_TEXT;else bits_left<=bits_left-1'b1;
    end
    WRITE_TEXT:begin
     we<=1;address<=12'd2304+(field==7?12'd87:field*11)+position;
     data<={(field==7||field==saved_class)?4'd3:4'd1,character};
     if(position==5)begin
      if(field==7)begin position<=0;state<=CLASS_META;end
      else begin field<=field+1'b1;state<=DIGIT_SETUP;end
     end else position<=position+1'b1;
    end
    CLASS_META:begin
     we<=1;
     if(position<8)begin address<=12'd2381+position;data<={4'd3,class_english(saved_class,{1'b0,position})};end
     else begin address<=12'd2454;data<={5'd0,saved_class,class_length(saved_class)};end
     if(position==8)begin index<=0;state<=BAR_SETUP;end else position<=position+1'b1;
    end
    BAR_SETUP:begin
     dividend<=(wide_confidence<<6)-(wide_confidence<<3)+32'd500;divisor<=1000;
     quotient<=0;remainder<=0;bits_left<=31;division_is_bar<=1;state<=DIVIDE;
    end
    BAR_WRITE:begin
     we<=1;address<=12'd2447+index;data<={1'b0,index==saved_class,3'd0,(quotient>56?7'd56:quotient[6:0])};
     if(index==6)state<=PUBLISH;else begin index<=index+1'b1;state<=BAR_SETUP;end
    end
    PUBLISH:begin commit<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
