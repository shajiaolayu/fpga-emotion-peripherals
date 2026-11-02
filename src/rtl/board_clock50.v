`timescale 1ns/1ps
// Historical module name retained; selected core/control frequency is explicit.
module board_clock50 #(parameter CORE_HZ=120000000)(input wire sysclk_p,sysclk_n,cpu_resetn,
 output wire clk,rst_n,locked,output wire clk200);
 wire fb,fb_buf,raw;
 IBUFDS oscillator(.I(sysclk_p),.IB(sysclk_n),.O(clk200));
 MMCME2_BASE #(.CLKIN1_PERIOD(5.0),.DIVCLK_DIVIDE(1),
  .CLKFBOUT_MULT_F(6.0),.CLKOUT0_DIVIDE_F(1200000000.0/CORE_HZ))
  clocks(.CLKIN1(clk200),.CLKFBIN(fb_buf),.CLKFBOUT(fb),
   .CLKOUT0(raw),.LOCKED(locked),.RST(~cpu_resetn),.PWRDWN(1'b0));
 BUFG feedback(.I(fb),.O(fb_buf));
 BUFG core_buffer(.I(raw),.O(clk));
 reset_sync reset_i(clk,cpu_resetn&&locked,rst_n);
endmodule
