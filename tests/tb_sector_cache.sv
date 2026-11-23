`timescale 1ns/1ps
module tb_sector_cache;
reg clk=0;always #5 clk=~clk;
reg write_enable=0;
reg [15:0] write_word=0,write_data=0,read_word=0;
wire [15:0] read_data;
sector_cache dut(.*);
integer i;
initial begin
    for(i=0;i<65536;i=i+1) begin
        @(negedge clk);write_enable=1;write_word=i;write_data=i^16'hA55A;
    end
    @(negedge clk);write_enable=0;
    for(i=0;i<65536;i=i+1) begin
        @(negedge clk);read_word=i;
        @(posedge clk);#1;
        if(read_data!==(i^16'hA55A)) $fatal(1,"cache data at %h",i);
    end
    @(negedge clk);read_word=0;write_enable=1;write_word=16'hFFFF;write_data=16'hBEEF;
    @(posedge clk);#1;if(read_data!==16'hA55A) $fatal(1,"independent cache ports");
    @(negedge clk);write_enable=0;read_word=16'hFFFF;
    #1;if(read_data!==16'hA55A) $fatal(1,"cache read must be synchronous");
    @(posedge clk);#1;if(read_data!==16'hBEEF) $fatal(1,"last word update");
    $display("PASS sector_cache: full-sector persistence, synchronous latency, independent ports");$finish;
end
endmodule
