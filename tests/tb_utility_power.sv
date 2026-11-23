`timescale 1ns/1ps
module tb_utility_power;
reg clk=0;always #5 clk=~clk;
reg core_reset_n=0,app_reset_n=0,in_menu=0,cart_powered=0;
reg [15:0] keys=0;
wire [7:0] status,error_code;
wire [1:0] rom_state;
reg [31:0] target_size=192;
pocketflash_utility dut(.clk(clk),.core_reset_n(core_reset_n),.app_reset_n(app_reset_n),
 .in_menu(in_menu),.cart_powered(cart_powered),.keys(keys),.target_size(target_size),
 .target_changed(1'b0),.file_poisoned(1'b0),.file_ready(1'b1),.file_done(1'b0),
 .file_result(16'b0),.ram_q(16'b0),.ad_in(16'hFFFF),.save_data_in(8'hFF),
 .status(status),.error_code(error_code),.rom_state(rom_state));
initial begin
 repeat(3) @(negedge clk);core_reset_n=1;app_reset_n=1;
 repeat(3) @(negedge clk);keys=16'h10;@(negedge clk);keys=0;
 repeat(4) @(negedge clk);
 if(status!=255 || error_code!=1) $fatal(1,"unpowered action silently ignored");
 @(negedge clk);keys=16'h20;@(negedge clk);keys=0;cart_powered=1;target_size=0;
 repeat(3) @(negedge clk);
 keys=2;@(negedge clk);keys=0;@(negedge clk);keys=2;@(negedge clk);keys=0;
 @(negedge clk);keys=16'h10;@(negedge clk);keys=0;repeat(2) @(negedge clk);
 keys=16'h10;@(negedge clk);keys=0;
 wait(status==255);
 if(error_code!=2 || rom_state!=0) $fatal(1,"invalid preflight falsely marks ROM incomplete");
 $display("PASS utility_power: actionable error before unpowered cartridge action");$finish;
end
endmodule
