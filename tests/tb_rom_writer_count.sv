`include "tests/tb_rom_writer.sv"
`timescale 1ns/1ps
module tb_rom_writer_count;
tb_rom_writer #(.COUNT_TEST(1)) test();
endmodule
