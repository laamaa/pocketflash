`timescale 1ns/1ps
module tb_binary_decimal;
reg clk=0;always #5 clk=~clk;
reg [31:0] value=0;
wire [39:0] digits;
binary_decimal dut(.*);
task check(input [31:0] v,input [39:0] expected);
begin @(negedge clk);value=v;repeat(70) @(negedge clk);if(digits!==expected) $fatal(1,"decimal %d got %h",v,digits);end endtask
initial begin
 check(0,0);check(33554432,40'h0033554432);check(9999,40'h0000009999);check(4294967295,40'h4294967295);
 $display("PASS binary_decimal: zero, ROM size, filenames, maximum uint32");$finish;
end
endmodule
