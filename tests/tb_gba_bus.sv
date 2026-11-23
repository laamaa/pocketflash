`timescale 1ns/1ps
module tb_gba_bus;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,request=0,write=0;
reg [24:0] address=0;
reg [15:0] write_data=0;
wire ready,done,error,ad_drive,cs_n,rd_n,wr_n;
wire [15:0] read_data,ad_out;
wire [7:0] a_high;
reg [23:0] latched;
wire [15:0] ad_in=latched[15:0] ^ {8'b0,latched[23:16]} ^ 16'hA55A;
gba_bus #(.TICKS(2),.ALLOW_WRITES(0)) dut(.*);
always @(negedge cs_n) latched={a_high,ad_out};
always @(negedge clk) if(reset_n) begin
    if(wr_n!==1'b1) $fatal(1,"read-only bus issued WR");
    if(!rd_n && (ad_drive || cs_n)) $fatal(1,"read drive contention/select error");
end
task transaction(input bit w,input [24:0] addr,input bit should_error);
begin
    wait(ready);@(negedge clk);address=addr;write=w;request=1;
    @(negedge clk);request=0;
    wait(done);#1;
    if(error!==should_error) $fatal(1,"unexpected transaction result");
    if(!should_error && read_data!==(((addr>>1) ^ (addr>>17) ^ 16'hA55A)&16'hFFFF))
        $fatal(1,"incorrect address/data conversion at %h: %h",addr,read_data);
    @(negedge clk);
end endtask
initial begin
    repeat(3) @(negedge clk);reset_n=1;
    transaction(0,0,0);transaction(0,25'h1FFFFFE,0);
    transaction(0,25'h1000000,0);transaction(0,25'hFFFFFE,0);
    transaction(0,1,1);transaction(1,0,1);
    @(negedge clk);request=1;address=2;
    @(negedge clk);request=0;
    repeat(3) @(negedge clk);reset_n=0;
    @(negedge clk);
    if(!cs_n || !rd_n || !wr_n || ad_drive) $fatal(1,"reset did not release the bus");
    $display("PASS gba_bus: addressing, read-only writes, turnaround, reset");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
