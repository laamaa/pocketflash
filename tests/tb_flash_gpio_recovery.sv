`include "tests/tb_flash_recovery.sv"
`timescale 1ns/1ps
module tb_flash_gpio_recovery;
tb_flash_recovery #(.CLEAR_GPIO(1)) test();
endmodule
