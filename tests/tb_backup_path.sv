`timescale 1ns/1ps
module tb_backup_path;
reg is_save=0,report_path=0;
reg [15:0] digits=16'h0001;
reg [7:0] index=0;
wire [7:0] value;
backup_path dut(.*);
reg [319:0] expected;
integer i;
task check;
begin for(i=0;i<40;i=i+1) begin index=i;#1;if(value!==expected[(39-i)*8+:8]) $fatal(1,"path byte %d got %h",i,value);end end
endtask
initial begin
 index=255;#1;
 expected={"/Saves/pocketflash/common/rom0001.gba",24'b0};check();
 is_save=1;report_path=1;digits=16'h9999;
 expected={"/Saves/pocketflash/common/save9999.pfs",16'b0};check();
 $display("PASS backup_path: decimal filenames and zero termination");$finish;
end
endmodule
