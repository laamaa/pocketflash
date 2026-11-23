`timescale 1ns / 1ps
// Clock-only PLL model: this bench tests bridge transactions, not video timing.
module altera_pll
    #(parameter fractional_vco_multiplier = "false", reference_clock_frequency = "",
                operation_mode = "",
      parameter number_of_clocks = 2, output_clock_frequency0 = "", phase_shift0 = "",
                duty_cycle0 = 50,
      parameter output_clock_frequency1 = "", phase_shift1 = "", duty_cycle1 = 50, pll_type = "",
                pll_subtype = "")
    (input wire refclk, rst,
     output wire [1 : 0] outclk,
     output wire locked);
    assign outclk = {2{refclk}};
    assign locked = !rst;
endmodule
