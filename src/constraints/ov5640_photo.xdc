# OV5640 wiring; Digilent Genesys 2 Rev.H Master XDC and previous physical G2 baseline.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property -dict {PACKAGE_PIN AD12 IOSTANDARD LVDS} [get_ports sysclk_p]
set_property -dict {PACKAGE_PIN AD11 IOSTANDARD LVDS} [get_ports sysclk_n]
create_clock -period 5.000 -name sys_clk200 [get_ports sysclk_p]
# Only the first stages of the explicit bundled-data frame handshake cross
# clocks. Keep downstream synchronous paths timed; no blanket clock grouping.
set_false_path -to [get_pins -hier -filter {NAME =~ *req_sync_reg[0]/D || NAME =~ *ack_sync_reg[0]/D}]
# Reset assertion is asynchronous by design, release uses three local stages.
set_false_path -to [get_pins -hier -filter {NAME =~ pipeline/*_reset/stages_reg*/CLR}]
# Direct plug: camera J2 -> JA, J1 -> JB, each header pin maps 1:1.
# JA1=SDA, JA2=RESET_n, JA3=HREF, JA4=XCLK, JA7=SCL,
# JA8=VSYNC, JA9=PWDN, JA10=D7. JB8=PCLK (U25, SRCC).
set_property -dict {PACKAGE_PIN U25 IOSTANDARD LVCMOS33} [get_ports cam_pclk]
set_property -dict {PACKAGE_PIN T27 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports cam_xclk]
set_property -dict {PACKAGE_PIN T26 IOSTANDARD LVCMOS33} [get_ports cam_href]
set_property -dict {PACKAGE_PIN T23 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33 PULLUP true DRIVE 4 SLEW SLOW} [get_ports cam_scl]
set_property -dict {PACKAGE_PIN U27 IOSTANDARD LVCMOS33 PULLUP true DRIVE 4 SLEW SLOW} [get_ports cam_sda]
set_property -dict {PACKAGE_PIN U28 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports cam_reset_n]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports cam_pwdn]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports {cam_data[0]}]
set_property -dict {PACKAGE_PIN U23 IOSTANDARD LVCMOS33} [get_ports {cam_data[1]}]
set_property -dict {PACKAGE_PIN W26 IOSTANDARD LVCMOS33} [get_ports {cam_data[2]}]
set_property -dict {PACKAGE_PIN V25 IOSTANDARD LVCMOS33} [get_ports {cam_data[3]}]
set_property -dict {PACKAGE_PIN V30 IOSTANDARD LVCMOS33} [get_ports {cam_data[4]}]
set_property -dict {PACKAGE_PIN V29 IOSTANDARD LVCMOS33} [get_ports {cam_data[5]}]
set_property -dict {PACKAGE_PIN T25 IOSTANDARD LVCMOS33} [get_ports {cam_data[6]}]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {cam_data[7]}]
# U25 is the N side of SRCC; single-ended DVP PCLK cannot use its dedicated
# pad-to-BUFG connection (Place 30-876). Permit fabric only on this ingress.
# PCLK still uses a BUFG, remains timed, and must pass setup/hold sign-off.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {cam_pclk_IBUF}]
# Sensor samples data on rising PCLK; launch is falling PCLK.
# R5 28MHz preset. IO budget assumes <=12ns sensor+board+cable delay;
# this is a design assumption, not a measured AF-OV5640-V1.0 timing guarantee.
create_clock -period 35.714 -name camera_pclk [get_ports cam_pclk]
set_input_delay -clock camera_pclk -clock_fall -max 12.000 [get_ports {cam_data[*] cam_href cam_vsync}]
set_input_delay -clock camera_pclk -clock_fall -min 0.000 [get_ports {cam_data[*] cam_href cam_vsync}]
create_generated_clock -name camera_xclk -source [get_pins camera_clock/clock_output/C] -divide_by 1 [get_ports cam_xclk]
# Constrain Gray pointer arrival/skew; no blanket asynchronous clock cut.
# Synthesis may merge the Gray MSB with the identical binary MSB. Include both
# register names so that the physical constraints still cover that endpoint.
set_max_delay -datapath_only 8.333 -from [get_cells -hier -filter {NAME =~ capture/events/rgray_reg* || NAME =~ capture/events/rbin_reg*}] -to [get_cells -hier -filter {NAME =~ capture/events/rgray_meta_reg*}]
set_max_delay -datapath_only 35.714 -from [get_cells -hier -filter {NAME =~ capture/events/wgray_reg* || NAME =~ capture/events/wbin_reg*}] -to [get_cells -hier -filter {NAME =~ capture/events/wgray_meta_reg*}]
set_bus_skew 8.333 -from [get_cells -hier -filter {NAME =~ capture/events/rgray_reg* || NAME =~ capture/events/rbin_reg*}] -to [get_cells -hier -filter {NAME =~ capture/events/rgray_meta_reg*}]
set_bus_skew 35.714 -from [get_cells -hier -filter {NAME =~ capture/events/wgray_reg* || NAME =~ capture/events/wbin_reg*}] -to [get_cells -hier -filter {NAME =~ capture/events/wgray_meta_reg*}]
# FIFO payload is a bundled-data crossing. Empty is released only after the
# registered write Gray pointer has crossed two receiving flip-flops. The
# corresponding memory word is stable before pop; it is not a synchronous path.
set_max_delay -datapath_only 8.333 -from [get_pins -hier -filter {NAME =~ capture/events/mem_reg*/CLK}] -to [get_cells -hier -filter {NAME =~ capture/events/rdata_reg*}]
set_false_path -to [get_pins -hier -filter {NAME =~ capture/fault_sync_reg[0]/D}]
set_false_path -from [get_ports {cam_scl cam_sda}] -to [get_pins -hier -filter {NAME =~ *scl_sync_reg[0]/D || NAME =~ *sda_sync_reg[0]/D}]
set_false_path -to [get_ports {cam_scl cam_sda cam_reset_n cam_pwdn}]
set_property -dict {PACKAGE_PIN Y23 IOSTANDARD LVCMOS33} [get_ports uart_rx_out]
set_false_path -to [get_ports uart_rx_out]
set_property -dict {PACKAGE_PIN T28 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U30 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN U29 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN V26 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN W24 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN W23 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_false_path -to [get_ports {led[*]}]

set_property -dict {PACKAGE_PIN AA20 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_p]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD TMDS_33} [get_ports hdmi_tx_clk_n]
set_property -dict {PACKAGE_PIN AC20 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[0]}]
set_property -dict {PACKAGE_PIN AC21 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[0]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[1]}]
set_property -dict {PACKAGE_PIN AA23 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[1]}]
set_property -dict {PACKAGE_PIN AB24 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[2]}]
set_property -dict {PACKAGE_PIN AC25 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[2]}]

# Additional two-stage dashboard status inputs, first stage only.
set_false_path -to [get_pins -hier -filter {NAME =~ overlay/ready_sync_reg[0]/D || NAME =~ overlay/error_sync_reg[0]/D}]

# Slide switches only. Digilent Rev.H Master XDC.
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS12} [get_ports sw_mode]
set_property -dict {PACKAGE_PIN G25 IOSTANDARD LVCMOS12} [get_ports sw_shutter]
set_false_path -from [get_ports {sw_mode sw_shutter}] -to [get_pins -hier -filter {NAME =~ controls/switch_meta_reg*/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ overlay/mode_sync_reg[0]/D || NAME =~ overlay/work_sync_reg[0]/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *_reset/stages_reg*/CLR}]

set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports cpu_resetn]
set_false_path -from [get_ports cpu_resetn]
