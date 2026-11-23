`timescale 1ns/1ps
module tb_utility_controls;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,in_menu=0,idle_allowed=1,busy=0,armed=0,poisoned=0;
reg [15:0] keys=0;
wire [2:0] selection;
wire acknowledge,help,details,start,confirm,cancel;
utility_controls #(.HOLD_TICKS(4)) dut(.*);
task press(input integer bitno);
begin @(negedge clk);keys=1<<bitno;@(negedge clk);keys=0;@(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);reset_n=1;repeat(3) @(negedge clk);
 press(1);
 @(negedge clk);keys=16'h12;@(negedge clk);keys=0;
 if(start || acknowledge) $fatal(1,"Down+A action identity race bypasses flash acknowledgement");
 press(1);
 @(negedge clk);keys=16'h11;@(negedge clk);keys=0;
 if(start || acknowledge) $fatal(1,"Up+A action identity race bypasses flash acknowledgement");
 press(4);if(!acknowledge || start) $fatal(1,"write bypassed acknowledgement");
 @(negedge clk);keys=16'h10;#1;@(negedge clk);if(!start) $fatal(1,"acknowledgement did not start preflight");
 busy=1;armed=1;repeat(8) @(negedge clk);if(confirm) $fatal(1,"held A auto-confirmed");
 keys=0;repeat(2) @(negedge clk);keys=16'h10;
 repeat(4) @(negedge clk);if(!confirm) $fatal(1,"hold not confirmed");
 keys=0;armed=0;busy=0;poisoned=1;press(4);if(start || acknowledge) $fatal(1,"poison ignored");
 $display("PASS utility_controls: explicit acknowledgement, release/hold confirmation, poison");$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
