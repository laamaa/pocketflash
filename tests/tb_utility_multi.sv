`include "tests/tb_utility_system.sv"
`timescale 1ns / 1ps
module tb_utility_multi;
    tb_utility_system #(.MULTI_SECTOR(1))
    test();
endmodule
