`include "tests/tb_utility_system.sv"
`timescale 1ns/1ps
module tb_utility_save_finalize;tb_utility_system #(.FAIL_FINALIZE(1)) test();endmodule
