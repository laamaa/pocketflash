`include "tests/tb_pocketflash_app.sv"
`timescale 1ns/1ps
module tb_backup_strong;tb_pocketflash_app #(.STRONG(1)) test();endmodule
