`timescale 1ns / 1ps
`default_nettype none
module video_pll
    (input wire clk,
     output wire pixel_clk, pixel_clk90, locked);
    wire [1 : 0] clocks;
    altera_pll #(.fractional_vco_multiplier("false"),
                 .reference_clock_frequency("74.25 MHz"),
                 .operation_mode("normal"),
                 .number_of_clocks(2),
                 .output_clock_frequency0("7.425 MHz"),
                 .phase_shift0("0 ps"),
                 .duty_cycle0(50),
                 .output_clock_frequency1("7.425 MHz"),
                 .phase_shift1("33670 ps"),
                 .duty_cycle1(50),
                 .pll_type("General"),
                 .pll_subtype("General"))
        pll(.refclk(clk),
            .rst(1'b0),
            .outclk(clocks),
            .locked(locked));
    assign pixel_clk = clocks[0];
    assign pixel_clk90 = clocks[1];
endmodule
