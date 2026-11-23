`include "tests/tb_flash_ops.sv"
`timescale 1ns/1ps
module tb_flash_disabled;
tb_flash_ops #(.ALLOW_WRITE(0)) test();
endmodule
