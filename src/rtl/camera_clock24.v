`timescale 1ns/1ps
module camera_clock24(input wire clk200,reset,
 output wire xclk,locked);
 wire feedback,feedback_buf,raw,camera_clock;
 MMCME2_BASE #(.CLKIN1_PERIOD(5.0),.DIVCLK_DIVIDE(5),
  .CLKFBOUT_MULT_F(24.0),.CLKOUT0_DIVIDE_F(40.0)) mmcm(
  .CLKIN1(clk200),.CLKFBIN(feedback_buf),.CLKFBOUT(feedback),
  .CLKOUT0(raw),.LOCKED(locked),.RST(reset),.PWRDWN(1'b0));
 BUFG fb(.I(feedback),.O(feedback_buf));
 BUFG camera_buffer(.I(raw),.O(camera_clock));
 ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) clock_output(
  .C(camera_clock),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0),.Q(xclk));
endmodule
