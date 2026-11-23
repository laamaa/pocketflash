// Reproduce the physical sparse diagnostic failure at C4/C6/C8. Removing
// board GPIO cleanup must fail strict per-sector verification, even though
// the underlying NOR payload is correct. Both first and last pages are used.
`include "tests/tb_utility_system.sv"
`timescale 1ns/1ps
module tb_utility_gpio;
tb_utility_system #(.GPIO_OVERLAY(1)) test();
endmodule
