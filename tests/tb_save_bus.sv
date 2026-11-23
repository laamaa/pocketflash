`timescale 1ns/1ps
module tb_save_bus;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,cart_powered=1,request=0,bank=0;
reg [1:0] operation=0;
reg [15:0] address=0;
wire ready,done,error,poisoned,cs2_n,rd_n,wr_n,data_drive;
wire [15:0] q,address_out;
wire [7:0] data_out,data_in;
save_bus #(.TICKS(2),.DEADLINE(1000)) dut(.*);
save_model model(.clk(clk),.cs2_n(cs2_n),.rd_n(rd_n),.wr_n(wr_n),
 .data_drive(data_drive),.address(address_out),.data_out(data_out),.data_in(data_in));
task op(input [1:0] kind,input [15:0] addr,input bit b);
begin wait(ready);@(negedge clk);operation=kind;address=addr;bank=b;request=1;
@(negedge clk);request=0;address=16'hFFFF;bank=!b;
wait(done);#1;if(error) $fatal(1,"save op failed %d",kind);@(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);reset_n=1;
 op(2,0,0);if(q!==16'hC209 || model.id_mode) $fatal(1,"save identification/reset");
 op(3,0,0);op(0,16'h1234,0);if(q!==16'h0026) $fatal(1,"bank0/data order %h",q);
 op(3,0,1);op(0,16'h1234,0);if(q!==16'h0083) $fatal(1,"bank1/data order %h",q);
 op(3,0,0);op(1,0,0);
 if(model.bank || model.phase || model.id_mode) $fatal(1,"save cleanup");
 @(negedge clk);operation=2;request=1;@(negedge clk);request=0;
 repeat(4) @(negedge clk);cart_powered=0;wait(done);#1;
 if(!error || !poisoned || !cs2_n || !rd_n || !wr_n || data_drive) $fatal(1,"save power loss did not quiesce/poison");
 cart_powered=1;repeat(4) @(negedge clk);if(ready) $fatal(1,"save poison cleared without core reset");
 $display("PASS save_bus: pin timing, ordered nonpersistent commands, identification, banks, power-loss fencing");$finish;
end
initial begin #100000;$fatal(1,"save bus timeout");end
endmodule
