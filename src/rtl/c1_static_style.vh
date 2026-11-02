function [3:0] c1_static_style(input [10:0] x,input [9:0] y);begin
c1_static_style=2;
if(x>=33&&x<57&&y>=58&&y<71)c1_static_style=3;
if(x>=24&&x<67&&y>=44&&y<87)c1_static_style=3;
if(x>=80&&x<288&&y>=55&&y<80)c1_static_style=1;
if(x>=24&&x<96&&y>=138&&y<155)c1_static_style=3;
if(x>=688&&x<760&&y>=119&&y<136)c1_static_style=4;
if(x>=708&&x<816&&y>=452&&y<469)c1_static_style=1;
if(x>=864&&x<927&&y>=492&&y<502)c1_static_style=1;
if(x>=1056&&x<1136&&y>=170&&y<189)c1_static_style=1;
if(x>=1056&&x<1110&&y>=388&&y<405)c1_static_style=1;
end endfunction
localparam C1_MASK_DEPTH=4096;
