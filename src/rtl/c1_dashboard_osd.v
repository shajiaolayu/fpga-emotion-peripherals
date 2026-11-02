`timescale 1ns/1ps
// R13 English dashboard: atomic image, class and model-confidence publication.
(* use_dsp="no" *) module photo_dashboard_osd #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,gray_we,input wire [11:0] gray_addr,input wire [7:0] gray_data,
 input wire done,core_busy,input wire [2:0] prediction,input wire [223:0] scores,
 output wire pending,input wire pix,pix_rst_n,input wire camera_ready,camera_error,
 input wire [23:0] in_rgb,input wire in_de,in_hs,in_vs,input wire [10:0] in_x,input wire [9:0] in_y,
 output reg [23:0] rgb,output reg de,hs,vs,input wire manual_mode,work_busy,
 output wire source_bank,display_bank,display_valid);
 `include "photo_dashboard_glyphs.vh"
 `include "c1_static_style.vh"
 localparam [23:0] BASE=24'hedf3fa,PANEL=24'hffffff,INK=24'h16324f,
  MUTED=24'h536d87,LINE=24'hc9d9e9,ACCENT=24'h1f62b7,GOLD=24'h8e6928,SOFT=24'he3edf8;
 (* DONT_TOUCH="TRUE" *)reg pix_active;
 always @(posedge pix)pix_active<=pix_rst_n;
 (* ram_style="block" *)reg [11:0] bank0[0:4095],bank1[0:4095];
 reg req,ack,read_bank,read_bank_q,valid;
 assign source_bank=!req;assign display_bank=read_bank;assign display_valid=valid;
 (* ASYNC_REG="TRUE" *)reg [1:0] req_sync,ack_sync,ready_sync,error_sync,mode_sync,work_sync;
 wire format_busy,meta_we,confidence_commit;wire [11:0] meta_address,meta_data;
 wire metrics_busy,metrics_we,metrics_complete;wire [11:0]metrics_address,metrics_data;
 wire accepted_done=done&&(req==ack_sync[1]);
 wire image_write=gray_we&&gray_addr<2304;
 reg confidence_ready,metrics_ready;
 wire commit=confidence_ready&&metrics_ready;
 wire [69:0] confidence_debug;
 photo_formatter #(.CLK_HZ(CLK_HZ)) formatter(.clk(clk),.rst_n(rst_n),
  .done(accepted_done),.core_busy(core_busy),.prediction(prediction),.scores(scores),
  .busy(format_busy),.we(meta_we),.address(meta_address),.data(meta_data),.commit(confidence_commit),.confidence_values(confidence_debug));
 dashboard_metrics #(.CLK_HZ(CLK_HZ)) metrics(clk,rst_n,accepted_done,core_busy,
  !image_write&&!meta_we,metrics_busy,metrics_we,metrics_address,metrics_data,metrics_complete);
 always @(posedge clk)begin
  if(!rst_n)begin confidence_ready<=0;metrics_ready<=0;end
  else begin
   if(confidence_commit)confidence_ready<=1;
   if(metrics_complete)metrics_ready<=1;
   if(commit||accepted_done)begin confidence_ready<=0;metrics_ready<=0;end
  end
 end
 assign pending=format_busy||confidence_commit||metrics_busy||metrics_complete||confidence_ready||metrics_ready||(req!=ack_sync[1]);
 always @(posedge clk)begin
  if(!rst_n)begin req<=0;ack_sync<=0;end
  else begin ack_sync<={ack_sync[0],ack};if(commit)req<=!req;end
 end
 wire write_enable=image_write||meta_we||metrics_we;
 wire [11:0] write_address=image_write?gray_addr:(meta_we?meta_address:metrics_address);
 wire [11:0] write_data=image_write?{4'd0,gray_data}:(meta_we?meta_data:metrics_data);
 always @(posedge clk)if(write_enable)begin
  if(req)bank0[write_address]<=write_data;else bank1[write_address]<=write_data;
 end
 always @(posedge pix)begin
  if(!pix_active)begin req_sync<=0;ack<=0;read_bank<=0;read_bank_q<=0;valid<=0;
   ready_sync<=0;error_sync<=0;mode_sync<=0;work_sync<=0;end
  else begin
   req_sync<={req_sync[0],req};read_bank_q<=read_bank;
   ready_sync<={ready_sync[0],camera_ready};error_sync<={error_sync[0],camera_error};
   mode_sync<={mode_sync[0],manual_mode};work_sync<={work_sync[0],work_busy};
   if(in_x==0&&in_y==720&&req_sync[1]!=ack)begin read_bank<=req_sync[1];ack<=req_sync[1];valid<=1;end
  end
 end
 reg [2:0] displayed_class;
 wire [6:0] class_dx=in_x-11'd1080;
 wire [5:0] class_dy=in_y-10'd204;
 wire class_region=in_x>=1080&&in_x<1208&&in_y>=204&&in_y<268;
 wire top_confidence_region=in_x>=1096&&in_x<1192&&in_y>=296&&in_y<328;
 wire thumb_region=in_x>=704&&in_x<848&&in_y>=480&&in_y<624;
 wire [7:0] thumb_x=in_x-11'd704,thumb_y=in_y-10'd480;
 wire [11:0] thumb_address=(thumb_y/3)*12'd48+thumb_x/3;
 wire [7:0] score_y=in_y-10'd448;
 wire [2:0] score_row=score_y/26;
 wire [4:0] score_gy=score_y%26;
 wire score_region=in_x>=1184&&in_x<1232&&in_y>=448&&in_y<630&&score_gy<16;
 wire bar_region=in_x>=1120&&in_x<1176&&in_y>=448&&in_y<630;
 wire bar_line=bar_region&&score_gy>=6&&score_gy<10;
 reg meta_region,direct_region;
 reg [7:0] meta_index,direct_code;
 reg [2:0] glyph_x;
 reg [3:0] glyph_y,direct_style;
 reg [1:0] dynamic_kind;
 reg [4:0] class_character;
 integer dx;
 always @*begin
  meta_region=0;direct_region=0;meta_index=0;direct_code=32;glyph_x=0;glyph_y=0;
  direct_style=2;dynamic_kind=2;class_character=0;dx=0;
  if(class_region)begin
   dynamic_kind=0;
  end else if(top_confidence_region)begin
   dx=in_x-1096;meta_region=1;meta_index=87+(dx>>4);glyph_x=(dx>>1)&7;glyph_y=(in_y-296)>>1;
  end else if(score_region)begin
   dx=in_x-1184;meta_region=1;meta_index=score_row*11+(dx>>3);glyph_x=dx&7;glyph_y=score_gy;
  end else if(in_x>=928&&in_x<992&&((in_y>=584&&in_y<600)||(in_y>=616&&in_y<632)))begin
   dx=in_x-928;meta_region=1;meta_index=(in_y>=616?104:96)+(dx>>3);glyph_x=dx&7;
   glyph_y=in_y>=616?in_y-616:in_y-584;
  end else if(in_x>=1096&&in_x<1256&&in_y>=60&&in_y<76)begin
   dx=in_x-1096;direct_region=1;glyph_x=dx&7;glyph_y=in_y-60;
   direct_code=status_glyph(error_sync[1]?3'd4:(!ready_sync[1]?3'd0:(work_sync[1]?3'd3:(mode_sync[1]?3'd2:3'd1))),dx>>3);
   direct_style=error_sync[1]?5:(!ready_sync[1]?4:3);
  end
 end
 wire [11:0] read_address=thumb_region?thumb_address:(bar_region?12'd2447+score_row:(meta_region?12'd2304+meta_index:12'd2454));
 reg [11:0] q0,q1;
 always @(posedge pix)begin q0<=bank0[read_address];q1<=bank1[read_address];end
 wire [11:0] selected=read_bank_q?q1:q0;
 // The descriptor is sampled after the bank switch, entirely in pixel clock.
 always @(posedge pix)begin
  if(!pix_active)displayed_class<=7;
  else if(valid&&in_x==16&&in_y==720)
   displayed_class<=selected[6:4];
 end
 (* rom_style="block" *)reg [15:0] static_map[0:4095];
 (* rom_style="block" *)reg [15:0] static_masks[0:C1_MASK_DEPTH-1];
 (* rom_style="block" *)reg [7:0] font[0:2047];
 (* rom_style="block" *)reg [15:0] class_aa[0:16383];
 (* rom_style="block" *)reg [15:0] percent_aa[0:2047];
 initial begin
  $readmemh("c1_static_map.mem",static_map);$readmemh("c1_static_masks.mem",static_masks);$readmemh("glyph_rows.mem",font);
  $readmemh("class_aa.mem",class_aa);$readmemh("percent_aa.mem",percent_aa);
 end
 wire [11:0] tile_address=(in_x<1280&&in_y<720)?(in_y>>4)*12'd80+(in_x>>4):12'd0;
 reg [15:0] tile_q;
 always @(posedge pix)tile_q<=static_map[tile_address];
 function rounded(input integer x,y,l,t,w,h);
  integer ax,ay;
  begin
   ax=(x-l<w-1-x+l)?x-l:w-1-x+l;ay=(y-t<h-1-y+t)?y-t:h-1-y+t;
   rounded=x>=l&&x<l+w&&y>=t&&y<t+h&&(ax>=8||ay>=8||(ax>=1&&ay>=4)||(ax>=2&&ay>=2)||(ax>=4&&ay>=1));
  end
 endfunction
 reg [23:0] background;
 always @*begin
  background=BASE;
  if(rounded(in_x,in_y,1031,143,226,520)||rounded(in_x,in_y,687,431,322,232))background=LINE;
  if(rounded(in_x,in_y,1032,144,224,518)||rounded(in_x,in_y,688,432,320,230))background=PANEL;
  if(in_x>=23&&in_x<665&&in_y>=162&&in_y<644)background=LINE;
  if(in_x>=687&&in_x<1009&&in_y>=143&&in_y<385)background=LINE;
  if((in_x>=24&&in_x<664&&in_y>=163&&in_y<643)||(in_x>=688&&in_x<1008&&in_y>=144&&in_y<384))background=in_rgb;
  if(bar_line)background=SOFT;
  if(in_x>=1056&&in_x<1232&&in_y==364)background=LINE;
  if(in_x>=1076&&in_x<1084&&in_y>=64&&in_y<72)background=error_sync[1]?24'hba3434:ACCENT;
 end
 reg [23:0] bg0,bg1;
 reg [3:0] sx0,sx1,sy0,static_style0,static_style1,direct_style0,style1;
 reg [2:0] gx0,gx1;
 reg [3:0] gy0;
 reg meta0,direct0,thumb0,thumb1,bar0,bar1,valid0,valid1;
 reg [1:0] kind0;
 reg [7:0] direct_code0;
 reg [4:0] class_character0;
 reg [6:0] bar_dx0,bar_dx1;
 reg de0,hs0,vs0,de1,hs1,vs1;
 wire [13:0] class_aa_address={displayed_class,class_dy,class_dx[6:2]};
 reg [15:0]class_aa_q,class_aa_q1,percent_aa_q;
 reg class0,class1,top0,top1;reg [1:0]class_sub0,class_sub1,top_sub0,top_sub1;
 reg [4:0]top_y0;
 always @(posedge pix)begin
  class_aa_q<=class_aa[class_aa_address];class_aa_q1<=class_aa_q;
  class0<=class_region;class1<=class0;top0<=top_confidence_region;top1<=top0;
  class_sub0<=class_dx[1:0];class_sub1<=class_sub0;
  top_sub0<=in_x[1:0];top_sub1<=top_sub0;top_y0<=in_y-296;
 end
 always @(posedge pix)begin
  bg0<=background;sx0<=in_x[3:0];sy0<=in_y[3:0];static_style0<=c1_static_style(in_x,in_y);
  gx0<=glyph_x;gy0<=glyph_y;meta0<=meta_region;direct0<=direct_region;kind0<=dynamic_kind;
  direct_code0<=direct_code;direct_style0<=direct_style;class_character0<=class_character;
  thumb0<=thumb_region;bar0<=bar_line;bar_dx0<=in_x-1120;valid0<=valid;
  de0<=in_de&&pix_active;hs0<=in_hs;vs0<=in_vs;
 end
 reg [7:0] glyph_code;
 reg [3:0] glyph_style;
 always @*begin
  glyph_code=32;glyph_style=2;
  if(meta0)begin
   glyph_code=valid0?selected[7:0]:(kind0==0?class_english(7,class_character0):8'd32);
   glyph_style=valid0?selected[11:8]:3;
  end
  if(direct0)begin glyph_code=direct_code0;glyph_style=direct_style0;end
 end
 reg [15:0] mask_q;
 reg [7:0] font_q,gray1;
 reg [11:0] bar_word1;
 function [3:0] aa_digit(input [7:0]code);
  if(code>=48&&code<=57)aa_digit=code-48;
  else case(code)46:aa_digit=10;37:aa_digit=11;45:aa_digit=13;default:aa_digit=12;endcase
 endfunction
 always @(posedge pix)begin
  mask_q<=static_masks[(tile_q<<4)+sy0];font_q<=font[{glyph_code[6:0],gy0}];
  percent_aa_q<=percent_aa[{aa_digit(glyph_code),top_y0,gx0[2:1]}];
  sx1<=sx0;static_style1<=static_style0;gx1<=gx0;style1<=glyph_style;
  bg1<=bg0;gray1<=selected[7:0];thumb1<=thumb0;bar1<=bar0;bar_word1<=selected;bar_dx1<=bar_dx0;valid1<=valid0;
  de1<=de0;hs1<=hs0;vs1<=vs0;
 end
 function [23:0] color(input [3:0] s);
  case(s)
   1:color=INK;2:color=MUTED;3:color=ACCENT;4:color=GOLD;5:color=24'hba3434;
   6:color=24'hffffff;7:color=24'hf6e3ba;default:color=MUTED;
  endcase
 endfunction
 wire bar_fill=bar1&&valid1&&bar_dx1<bar_word1[6:0];
 `include "aa_palette.vh"
 always @(posedge pix)begin
  if(!pix_active)begin rgb<=0;de<=0;hs<=0;vs<=0;end
  else begin
   de<=de1;hs<=hs1;vs<=vs1;
   if(!de1)rgb<=0;
   else if(thumb1)rgb<=valid1?{gray1,gray1,gray1}:24'hdee6ef;
   else if(bar_fill)rgb<=bar_word1[10]?ACCENT:24'h9aafbf;
   else if(class1)rgb<=aa_color(class_aa_q1[15-class_sub1*4-:4]);
   else if(top1)rgb<=aa_color(percent_aa_q[15-top_sub1*4-:4]);
   else if(font_q[7-gx1])rgb<=color(style1);
   else if(mask_q[15-sx1])rgb<=color(static_style1);
   else rgb<=bg1;
  end
 end
endmodule
