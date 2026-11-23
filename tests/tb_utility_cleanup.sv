`include "tests/tb_utility_system.sv"
`timescale 1ns/1ps
module tb_utility_cleanup;tb_utility_system #(.FAIL_CLEANUP(1)) test();endmodule
