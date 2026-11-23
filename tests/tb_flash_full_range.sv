`include "tests/tb_flash_ops.sv"
`timescale 1ns/1ps
module tb_flash_full_range;
tb_flash_ops #(.FULL_RANGE(1)) test();
endmodule
