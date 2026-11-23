// Double dabble: bounded short combinational stages instead of chained divisions.
// Captures a value every 33 clocks and publishes complete digits after 32 shifts.
// Display-only: callers allow conversion to finish before drawing the counters.
`timescale 1ns / 1ps
`default_nettype none
module binary_decimal
    (input wire clk,
     input wire [31 : 0] value,
     output reg [39 : 0] digits = 0);
    reg [31 : 0] binary = 0;
    reg [39 : 0] bcd = 0, adjusted;
    reg [5 : 0] step = 0;
    integer n;
    always @* begin
        adjusted = bcd;
        for (n = 0; n < 10; n = n + 1)
            if (bcd[n * 4 +: 4] >= 5)
                adjusted[n * 4 +: 4] = bcd[n * 4 +: 4] + 3;
    end
    always @(posedge clk) begin
        if (step == 0) begin
            binary <= value;
            bcd <= 0;
            step <= 1;
        end else begin
            binary <= binary << 1;
            bcd <= {adjusted[38 : 0], binary[31]};
            if (step == 32) begin
                digits <= {adjusted[38 : 0], binary[31]};
                step <= 0;
            end else
                step <= step + 1'b1;
        end
    end
endmodule
