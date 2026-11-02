`timescale 1ns/1ps
// OV5640 direct plug: camera J2 -> JA and J1 -> JB, pin-for-pin.
module ov5640_photo_top #(parameter TEST_PATTERN=0,UART_DEBUG_ENABLE=0,CORE_HZ=120000000)(
 input wire sysclk_p,sysclk_n,cpu_resetn,sw_mode,sw_shutter,
 input wire [7:0] cam_data,input wire cam_pclk,cam_href,cam_vsync,
 inout wire cam_scl,cam_sda,
 output wire cam_xclk,cam_reset_n,cam_pwdn,
 output wire uart_rx_out,output wire [7:0] led,
 output wire hdmi_tx_clk_p,hdmi_tx_clk_n,output wire [2:0] hdmi_tx_p,hdmi_tx_n);
 wire clk,rst_n,board_rst_n,locked,clk200;
 wire manual_mode,shutter;
 wire xclk_locked,init_rst_n;
 camera_clock24 camera_clock(clk200,~cpu_resetn,cam_xclk,xclk_locked);
 reset_sync init_reset(clk,cpu_resetn&&locked&&xclk_locked,init_rst_n);
 // Keep camera-configuration ROM addresses and UART BRAM enables behind a
 // synchronous reset bridge; asynchronous lock/reset must not reach RAM pins.
 (* DONT_TOUCH="TRUE" *)reg control_active;
 always @(posedge clk)control_active<=init_rst_n;
 assign rst_n=control_active;
 board_clock50 #(.CORE_HZ(CORE_HZ)) clocks(sysclk_p,sysclk_n,cpu_resetn,clk,board_rst_n,locked,clk200);
 photo_controls #(.CLK_HZ(CORE_HZ)) controls(clk,board_rst_n,sw_mode,sw_shutter,manual_mode,shutter);
 wire scl_low,sda_low,bus_start,bus_read,bus_busy,bus_done,bus_error,nack;
 wire [15:0] bus_addr;wire [7:0] bus_write,bus_data,error_code;
 wire ready,failed;
 wire [15:0] chip_id;
 assign cam_scl=scl_low?1'b0:1'bz;assign cam_sda=sda_low?1'b0:1'bz;
 sccb16_master #(.CLK_HZ(CORE_HZ)) bus_i(clk,rst_n,bus_start,bus_read,bus_addr,bus_write,
   cam_scl,cam_sda,scl_low,sda_low,bus_busy,bus_done,bus_error,bus_data,nack);
 ov5640_init #(.CLK_HZ(CORE_HZ),.TEST_PATTERN(TEST_PATTERN)) init_i(clk,rst_n,bus_busy,bus_done,bus_error,bus_data,
   bus_start,bus_read,bus_addr,bus_write,cam_reset_n,cam_pwdn,ready,failed,error_code,chip_id);
 wire sof,eof,frame_ok,pv,fifo_fault;
 wire [15:0] pixel;
 wire [9:0] x,y;
 wire [31:0] frames_read;
 wire frame_error;
 // Register the camera's reset request before the PCLK reset synchronizer.
 // A common lock loss still asserts reset asynchronously in every domain.
 (* ASYNC_REG="TRUE" *)reg [2:0] camera_enable_bridge;
 always @(posedge clk or negedge stream_arst_n)
  if(!stream_arst_n)camera_enable_bridge<=0;
  else camera_enable_bridge<={camera_enable_bridge[1:0],ready};
 wire camera_arst_n=camera_enable_bridge[2];
 ov5640_capture capture(clk,cam_pclk,camera_arst_n,cam_vsync,cam_href,cam_data,
   sof,eof,frame_ok,pv,pixel,x,y,fifo_fault,frame_error,frames_read);
 wire fb,fb_buf,pix_raw,ser_raw,pix,ser,video_locked,pix_rst_n;
 MMCME2_BASE #(.CLKIN1_PERIOD(5.0),.DIVCLK_DIVIDE(10),.CLKFBOUT_MULT_F(37.125),
   .CLKOUT0_DIVIDE_F(10.0),.CLKOUT1_DIVIDE(2)) video_clocks(
   .CLKIN1(clk200),.CLKFBIN(fb_buf),.CLKFBOUT(fb),.CLKOUT0(pix_raw),.CLKOUT1(ser_raw),
   .LOCKED(video_locked),.RST(~cpu_resetn),.PWRDWN(1'b0));
 BUFG feedback(.I(fb),.O(fb_buf));BUFG pixel_clock(.I(pix_raw),.O(pix));
 BUFG serial_clock(.I(ser_raw),.O(ser));
 // All frame/result ownership tokens assert reset together on either clock
 // losing lock; each domain releases through its local three-stage bridge.
 wire stream_arst_n=cpu_resetn&&locked&&video_locked&&xclk_locked;
 reset_sync pixel_reset(pix,stream_arst_n,pix_rst_n);
 wire [23:0] rgb,base_rgb;
 wire de,hs,vs,base_de,base_hs,base_vs,core_busy,core_done,tw,debug_busy,osd_pending,osd_rst_n;
 wire [10:0] display_x;wire [9:0] display_y;
 reset_sync osd_reset(clk,stream_arst_n,osd_rst_n);
 wire [2:0] prediction;
 wire [223:0] scores;
 wire [11:0] ta;
 wire [7:0] td;
 wire [31:0] video_dropped,inferences;
 wire photo_source_bank,photo_display_bank,photo_valid,work_busy;
 reg work_busy_registered;
 always @(posedge clk)if(!rst_n)work_busy_registered<=0;else work_busy_registered<=work_busy;
 reg [31:0] no_frame_cycles;
 reg camera_timeout;
 always @(posedge clk)begin
   if(!rst_n||!ready||eof&&frame_ok)begin no_frame_cycles<=0;camera_timeout<=0;end
   else if(no_frame_cycles<2*CORE_HZ)no_frame_cycles<=no_frame_cycles+1'b1;
   else camera_timeout<=1;
 end
 reg camera_error;
 always @(posedge clk)if(!rst_n)camera_error<=0;else camera_error<=fifo_fault||failed||frame_error||camera_timeout;
 photo_overlap_pipeline pipeline(
   clk,pix,stream_arst_n,debug_busy||osd_pending,manual_mode,shutter,
   photo_source_bank,photo_display_bank,photo_valid,osd_pending,sof,eof,frame_ok,pv,pixel,x,y,
   base_rgb,base_de,base_hs,base_vs,prediction,scores,core_busy,core_done,tw,ta,td,
   video_dropped,work_busy,display_x,display_y);
 photo_dashboard_osd #(.CLK_HZ(CORE_HZ)) overlay(clk,osd_rst_n,tw,ta,td,core_done,core_busy,prediction,scores,osd_pending,
   pix,pix_rst_n,ready,camera_error,base_rgb,base_de,base_hs,base_vs,display_x,display_y,rgb,de,hs,vs,
   manual_mode,work_busy_registered,photo_source_bank,photo_display_bank,photo_valid);
 // Serial image export is optional. Count completed inferences independently
 // when no UART receiver is used, with no serial busy backpressure.
 generate if(UART_DEBUG_ENABLE)begin: serial_debug_enabled
  inference_debug_uart #(.CLK_HZ(CORE_HZ)) debug_serial(clk,rst_n,tw,ta,td,core_done,prediction,scores,
    debug_busy,uart_rx_out,inferences);
 end else begin: serial_debug_disabled
  reg [31:0] result_count;
  always @(posedge clk)if(!rst_n)result_count<=0;else if(core_done)result_count<=result_count+1'b1;
  assign inferences=result_count;
  assign debug_busy=1'b0;
  assign uart_rx_out=1'b1;
 end endgenerate
 rgb2dvi #(.kGenerateSerialClk(1'b0),.kRstActiveHigh(1'b1)) transmitter(
   .TMDS_Clk_p(hdmi_tx_clk_p),.TMDS_Clk_n(hdmi_tx_clk_n),
   .TMDS_Data_p(hdmi_tx_p),.TMDS_Data_n(hdmi_tx_n),.aRst(~pix_rst_n),.aRst_n(1'b1),
   .vid_pData({rgb[23:16],rgb[7:0],rgb[15:8]}),.vid_pVDE(de),.vid_pHSync(hs),
   .vid_pVSync(vs),.PixelClk(pix),.SerialClk(ser));
 reg [2:0] last_class;
 always @(posedge clk)if(!rst_n)last_class<=7;else if(core_done)last_class<=prediction;
 assign led={last_class,camera_error,inferences[0],core_busy,ready,locked&&video_locked};
endmodule
