`timescale 1ns/1ps
module tb_transfer_ram;
reg clk=0;always #5 clk=~clk;
reg bridge_wr=0,bridge_rd=0,engine_wr=0;
reg [15:0] bridge_offset=0,engine_offset=0,engine_data=0;
reg [31:0] bridge_data=0;
wire [31:0] bridge_q;
wire [15:0] engine_q;
transfer_ram dut(.*);
initial begin
    @(negedge clk);bridge_wr=1;bridge_data=32'h12345678;
    @(negedge clk);bridge_wr=0;
    @(negedge clk);if(engine_q!==16'h3412) $fatal(1,"APF->cart lower word endian");
    engine_offset=2;
    @(negedge clk);if(engine_q!==16'h7856) $fatal(1,"APF->cart upper word endian");
    engine_offset=16'hFFFC;engine_data=16'hABCD;engine_wr=1;
    @(negedge clk);engine_offset=16'hFFFE;engine_data=16'h0123;
    @(negedge clk);engine_wr=0;bridge_offset=16'hFFFC;
    @(negedge clk);bridge_rd=1;
    @(negedge clk);if(bridge_q!==32'hCDAB2301) $fatal(1,"cart->APF endian or final addresses");
    $display("PASS transfer_ram: both directions and final halfwords");$finish;
end
endmodule
