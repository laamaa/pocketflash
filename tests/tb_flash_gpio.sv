`timescale 1ns/1ps
module tb_flash_gpio;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,request=0;
reg [1:0] operation=0;
reg [24:0] address=0;
wire ready,done,error,identified,swapped,completion_known,read_mode,poisoned;
wire [15:0] manufacturer,device,raw_status,buffer_offset;
wire [7:0] stage;
wire bus_request,bus_write,bus_ready,bus_done,bus_error;
wire model_error;
reg [1:0] fail_cleanup=0;
wire [24:0] bus_address;
wire [15:0] bus_data,bus_q;
assign bus_error=model_error || (fail_cleanup==1 && bus_address==25'hC8 && bus_write && bus_data==0);
reg [15:0] buffer_q;
reg inspecting=0,inspect_request=0;
reg [24:0] inspect_address=0;
wire [31:0] mutations;
flash_ops #(.ALLOW_QUERY(1),.ALLOW_PROGRAM(1),.CLEAR_GPIO(1),.WRITE_BEGIN(0),.WRITE_END(25'h1FFFFFF),.ERASE_TIMEOUT(4000),.PROGRAM_TIMEOUT(12000)) dut(.*);
nor_model #(.ARRAY_BASE(0),.SECTORS(1),.GPIO_OVERLAY(1)) model(
 .clk(clk),.reset_n(reset_n),.request(inspecting ? inspect_request : bus_request),
 .write(!inspecting && bus_write),.address(inspecting ? inspect_address : bus_address),
 .data(bus_data),.ready(bus_ready),.done(bus_done),.error(model_error),.q(bus_q),
 .fault_status(16'b0),.busy_forever(1'b0),
 .stall_bus(fail_cleanup==2 && bus_address==25'hC8 && bus_write && bus_data==0),.mutations(mutations));
always @(posedge clk) buffer_q<=buffer_offset^16'h5AA5;
task op(input [1:0] kind);
begin
 wait(ready);@(negedge clk);operation=kind;request=1;
 @(negedge clk);request=0;wait(done);#1;
 if(error || poisoned || !read_mode) $fatal(1,"operation failed %d",kind);
 @(negedge clk);
end endtask
task check_word(input [24:0] a,input [15:0] expected);
begin
 wait(bus_ready);@(negedge clk);inspecting=1;inspect_address=a;inspect_request=1;
 @(negedge clk);inspect_request=0;wait(bus_done);#1;
 if(bus_q!==expected) $fatal(1,"GPIO masked ROM at %h: expected %h read %h",a,expected,bus_q);
 @(negedge clk);
end endtask
initial begin
 repeat(3) @(negedge clk);reset_n=1;
 op(0);op(1);op(2);
 if(model.memory[98]!==16'h5A61 || model.memory[99]!==16'h5A63 || model.memory[100]!==16'h5A6D)
  $fatal(1,"underlying diagnostic payload incorrect");
 check_word(25'hC4,16'h5A61);check_word(25'hC6,16'h5A63);check_word(25'hC8,16'h5A6D);
 if(mutations!=2) $fatal(1,"GPIO cleanup mutated NOR");
 // A failed overlay cleanup cannot claim usable ROM reads or permit retries.
 inspecting=0;fail_cleanup=1;
 wait(ready);@(negedge clk);operation=0;request=1;
 @(negedge clk);request=0;wait(done);#1;
 if(!error || !poisoned || read_mode || completion_known) $fatal(1,"GPIO cleanup failure did not fence reads");
 @(negedge clk);fail_cleanup=0;request=1;operation=2;
 @(negedge clk);request=0;wait(done);#1;
 if(!error || mutations!=2) $fatal(1,"GPIO cleanup poison permitted another program");
 @(negedge clk);reset_n=0;repeat(3) @(negedge clk);reset_n=1;fail_cleanup=2;
 @(negedge clk);operation=0;request=1;
 @(negedge clk);request=0;wait(done);#1;
 if(!error || !poisoned || read_mode || completion_known || mutations!=2)
  $fatal(1,"GPIO cleanup acknowledgement timeout did not fence reads");
 $display("PASS flash_gpio: strict live GPIO-address reads equal programmed NOR without power cycle");$finish;
end
initial begin #1000000;$fatal(1,"GPIO test timeout");end
endmodule
