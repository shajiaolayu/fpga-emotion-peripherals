`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100000000,
    parameter BAUD     = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);

    localparam integer DIV = CLK_FREQ / BAUD;

    reg [15:0] div_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  shifter;

    // The busy flag can become a RAM read enable in the debug packet logic.
    // Keep assertion and release synchronous to avoid asynchronous RAM control.
    always @(posedge clk) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            busy    <= 1'b0;
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            shifter <= 10'h3FF;
        end else if (!busy) begin
            tx      <= 1'b1;
            div_cnt <= 16'd0;
            bit_idx <= 4'd0;
            if (start) begin
                shifter <= {1'b1, data, 1'b0};
                busy    <= 1'b1;
            end
        end else begin
            tx <= shifter[0];
            if (div_cnt == DIV - 1) begin
                div_cnt <= 16'd0;
                shifter <= {1'b1, shifter[9:1]};
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end

endmodule

