`timescale 1ns/1ps
module tb_utility_alloc_reset;
reg clk=0;always #5 clk=~clk;
reg core_reset_n=0,app_reset_n=0;
reg [15:0] keys=0;
wire busy,file_request;
reg file_done=0;
pocketflash_utility dut(.clk(clk),.core_reset_n(core_reset_n),.app_reset_n(app_reset_n),
 .in_menu(1'b0),.cart_powered(1'b1),.keys(keys),.target_size(32'd192),.target_changed(1'b0),
 .file_poisoned(1'b0),.file_ready(1'b1),.file_done(file_done),.file_result(16'd3),
 .ram_q(16'b0),.ad_in(16'hFFFF),.save_data_in(8'hFF),.busy(busy),.file_request(file_request));
always @(posedge clk) file_done<=file_request;
initial begin
 repeat(3) @(negedge clk);core_reset_n=1;app_reset_n=1;repeat(3) @(negedge clk);
 keys=2;@(negedge clk);keys=0;@(negedge clk);keys=16'h10;@(negedge clk);keys=0;
 wait(dut.alloc_done);@(negedge clk);app_reset_n=0;
 repeat(100) @(negedge clk);
 if(busy || dut.save_busy || dut.state!=0) $fatal(1,"allocation-to-save reset stranded owner");
 $display("PASS utility_alloc_reset: reset at allocation completion cannot strand save startup");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
