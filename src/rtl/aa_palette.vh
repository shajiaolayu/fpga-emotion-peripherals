function [23:0] aa_color(input [3:0]a);begin case(a)
0:aa_color=24'hffffff;
1:aa_color=24'hf0f5fa;
2:aa_color=24'he1eaf5;
3:aa_color=24'hd2e0f1;
4:aa_color=24'hc3d5ec;
5:aa_color=24'hb4cbe7;
6:aa_color=24'ha5c0e2;
7:aa_color=24'h96b6dd;
8:aa_color=24'h88abd9;
9:aa_color=24'h79a1d4;
10:aa_color=24'h6a96cf;
11:aa_color=24'h5b8cca;
12:aa_color=24'h4c81c5;
13:aa_color=24'h3d77c1;
14:aa_color=24'h2e6cbc;
15:aa_color=24'h1f62b7;
default:aa_color=24'hffffff;endcase end endfunction
