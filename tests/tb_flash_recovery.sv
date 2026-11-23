`timescale 1ns/1ps
module tb_flash_recovery #(parameter CLEAR_GPIO=0);
reg clk=0;always #5 clk=~clk;
reg reset_n=0,request=0;
reg [1:0] operation=0;
reg [24:0] address=25'h1FE0000;
wire ready,done,error,identified,swapped,completion_known,read_mode,poisoned;
wire [15:0] manufacturer,device,raw_status,buffer_offset;
wire [7:0] stage;
wire bus_request,bus_write,bus_ready,bus_done,bus_error;
wire model_error;
reg inject_bus_error=0;
assign bus_error=model_error | inject_bus_error;
wire [24:0] bus_address;
wire [15:0] bus_data,bus_q;
reg [15:0] buffer_q;
reg [15:0] fault_status=0;
reg busy_forever=0,stall_bus=0;
wire [31:0] mutations;
flash_ops #(.ALLOW_QUERY(1),.ALLOW_PROGRAM(1),.CLEAR_GPIO(CLEAR_GPIO),.ERASE_TIMEOUT(4000),.PROGRAM_TIMEOUT(12000)) dut(.*);
nor_model model(.clk(clk),.reset_n(reset_n),.request(bus_request),.write(bus_write),
.address(bus_address),.data(bus_data),.ready(bus_ready),.done(bus_done),.error(model_error),.q(bus_q),
.fault_status(fault_status),.busy_forever(busy_forever),.stall_bus(stall_bus),.mutations(mutations));
always @(posedge clk) buffer_q<=buffer_offset^16'hA55A;
task op(input [1:0] kind,input bit bad);
begin
    wait(ready);@(negedge clk);operation=kind;request=1;
    @(negedge clk);request=0;wait(done);#1;
    if(error!==bad) $fatal(1,"operation %d failed expectation",kind);
    @(negedge clk);
end endtask
task restart;
begin
    @(negedge clk);reset_n=0;repeat(3) @(negedge clk);reset_n=1;
end endtask
integer i,before_count;
initial begin
    restart();op(0,0);op(1,0);
    for(i=65536;i<131072;i=i+1) if(model.memory[i]!==16'hFFFF) $fatal(1,"erase missed word");
    for(i=0;i<65536;i=i+1) if(model.memory[i]!==16'h1234) $fatal(1,"erase touched prefix");
    op(2,0);
    for(i=0;i<256;i=i+1) if(model.memory[65536+i]!==((i*2)^16'hA55A)) $fatal(1,"program data");
    if(!completion_known || !read_mode || poisoned) $fatal(1,"success outcomes");
    restart();if(model.memory[65536]!==16'hA55A) $fatal(1,"reset lost flash");
    op(0,0);fault_status=16'h98;op(2,1);
    if(!completion_known || !read_mode || poisoned || raw_status!=16'h98) $fatal(1,"abort cleanup outcomes");
    if(model.status!=16'h80 || model.mode!=0) $fatal(1,"abort not cleared");
    fault_status=0;op(0,0);fault_status=16'hA0;op(1,1);
    if(!completion_known || !read_mode || poisoned) $fatal(1,"erase error cleanup");
    fault_status=0;op(0,0);busy_forever=1;op(1,1);busy_forever=0;
    if(completion_known || read_mode || !poisoned) $fatal(1,"unknown completion allowed reads");
    before_count=mutations;op(0,1);op(1,1);op(2,1);
    if(mutations!=before_count) $fatal(1,"poison accepted mutation");
    restart();op(0,0);stall_bus=1;op(1,1);stall_bus=0;
    if(!poisoned || completion_known || read_mode) $fatal(1,"bus stall did not poison");
    restart();op(0,0);inject_bus_error=1;op(2,1);inject_bus_error=0;
    if(!poisoned || completion_known || read_mode) $fatal(1,"bus error did not poison");
    restart();op(0,0);fault_status=16'hC0;op(1,1);fault_status=0;
    if(!poisoned || completion_known || read_mode) $fatal(1,"suspended status accepted");
    $display("PASS flash_recovery: persistent NOR, prefix, abort/erase cleanup, timeout/transport lockout");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
