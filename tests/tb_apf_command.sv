`timescale 1ns/1ps
module tb_apf_command;
reg clk=0;always #5 clk=~clk;
reg boot_ready=0;
reg [31:0] bridge_addr=0,bridge_wr_data=0;
reg bridge_wr=0,bridge_rd=0;
wire [31:0] bridge_rd_data,input_size;
wire reset_n,in_menu,cart_powered,input_changed,file_ready,file_done;
reg app_busy=0,mutation_lock=0;
wire file_poisoned;
wire [31:0] record_size,target_size;
wire [2:0] source_changed;
integer changes0=0,changes1=0;
always @(posedge clk) begin
 if(source_changed[0]) changes0=changes0+1;
 if(source_changed[1]) changes1=changes1+1;
end
integer changes_target=0;
always @(posedge clk) if(source_changed[2]) changes_target=changes_target+1;
integer change_before;
reg file_request=0;
reg [15:0] file_command=16'h0188,file_slot=1;
reg [31:0] file_offset=0,file_address=0,file_length=0;
wire [15:0] file_result;
wire [31:0] trace_target,trace_host_param;
wire [15:0] trace_host_command,trace_host_result;
apf_command #(.TIMEOUT_TICKS(100)) dut(.*);
task wr(input [31:0] addr,input [31:0] data);
begin @(negedge clk);bridge_wr=1;bridge_addr=addr;bridge_wr_data=data;
@(negedge clk);bridge_wr=0;end endtask
task rd(input [31:0] addr,input [31:0] expect_word);
begin @(negedge clk);bridge_addr=addr;
@(negedge clk);bridge_rd=1;
@(negedge clk);bridge_rd=0;
if(bridge_rd_data!==expect_word) $fatal(1,"APF register %h: got %h expected %h",addr,bridge_rd_data,expect_word);
end endtask
initial begin
    repeat(3) @(negedge clk);boot_ready=1;
    repeat(2) @(negedge clk);rd(32'hF8001000,32'h636D0140);
    wr(32'hF8001000,32'h6F6B0000);wait(file_ready);
    wr(32'hF8000020,32'h00010000);wr(32'hF8000000,32'h434D00B1);
    repeat(3) @(negedge clk);if(!cart_powered) $fatal(1,"cart power notification");
    wr(32'hF8000000,32'h434D0011);repeat(3) @(negedge clk);
    if(!reset_n) $fatal(1,"reset exit");
    app_busy=1;mutation_lock=1;
    wr(32'hF8000000,32'h434D0010);repeat(3) @(negedge clk);
    if(!reset_n) $fatal(1,"mutation reset was accepted");
    rd(32'hF8000000,32'h4F4B0001);
    wr(32'hF8000000,32'h434D0011);repeat(3) @(negedge clk);
    wr(32'hF8000000,32'h434D0082);repeat(3) @(negedge clk);
    rd(32'hF8000000,32'h4F4B0002);
    app_busy=0;mutation_lock=0;
    wr(32'hF8002018,3);wr(32'hF800201C,16);
    if(record_size!=16) $fatal(1,"deferred record size");
    change_before=changes1;
    wr(32'hF8002024,20);wr(32'hF8002020,3);repeat(2) @(negedge clk);
    if(record_size!=20 || changes1==change_before) $fatal(1,"size-before-ID record remap ignored");
    change_before=changes1;wr(32'hF8002020,2);repeat(2) @(negedge clk);
    if(changes1==change_before) $fatal(1,"record removal ignored");
    wr(32'hF8002024,64);change_before=changes0;wr(32'hF8002020,0);repeat(2) @(negedge clk);
    if(input_size!=64 || changes0==change_before) $fatal(1,"size-before-ID ROM remap ignored");
    change_before=changes0;wr(32'hF8002020,2);repeat(2) @(negedge clk);
    if(changes0==change_before) $fatal(1,"ROM removal ignored");
    change_before=changes_target;
    wr(32'hF800202C,192);wr(32'hF8002028,4);repeat(2) @(negedge clk);
    if(target_size!=192 || changes_target==change_before) $fatal(1,"target size-before-ID ignored");
    change_before=changes_target;wr(32'hF8002028,2);repeat(2) @(negedge clk);
    if(target_size!=0 || changes_target==change_before) $fatal(1,"target removal ignored");
    wr(32'hF8000020,4);wr(32'hF8000024,700);wr(32'hF8000000,32'h434D008A);
    repeat(3) @(negedge clk);if(target_size!=700) $fatal(1,"target host notification ignored");
    wr(32'hF8002000,0);wr(32'hF8002004,4096);
    if(input_size!=4096) $fatal(1,"initial deferred slot size");
    wr(32'hF8002008,1);wr(32'hF800200C,8192);
    if(input_size!=4096) $fatal(1,"another slot changed the input size");
    rd(32'hF8002004,4096);rd(32'hF800200C,8192);
    wr(32'hF8002010,2);wr(32'hF8002004,1234);
    if(input_size!=1234) $fatal(1,"size-only update did not use the stored entry ID");
    rd(32'hF8002004,1234);
    wr(32'hF8000000,32'h434D00A0);repeat(3) @(negedge clk);
    rd(32'hF8000040,0); // save states unsupported
    @(negedge clk);file_request=1;@(negedge clk);file_request=0;
    repeat(2) @(negedge clk);rd(32'hF8001000,32'h636D0188);
    wr(32'hF8001000,32'h62750000);wr(32'hF8001000,32'h6F6B0002);
    wait(file_done);if(file_result!=2) $fatal(1,"target result code");
    wait(file_ready);@(negedge clk);file_request=1;@(negedge clk);file_request=0;
    wr(32'hF8001000,32'h62750000);
    wr(32'hF8000020,1);wr(32'hF8000000,32'h434D0080);
    repeat(3) @(negedge clk);
    if(trace_host_command!=16'h0080 || trace_host_result!=1 || trace_host_param!=1)
        $fatal(1,"flush host-read trace lost");
    wr(32'hF8000000,32'h434D0082);repeat(3) @(negedge clk);
    if(trace_host_command!=16'h0082 || trace_host_result!=2)
        $fatal(1,"flush host-write trace lost");
    wait(file_done);if(file_result!=16'hFFFF || file_ready) $fatal(1,"timeout must poison channel");
    if(trace_target!=32'h62750000) $fatal(1,"timeout target status lost");
    wr(32'hF8001000,32'h6F6B0000);repeat(3) @(negedge clk);
    if(file_ready) $fatal(1,"late completion reused a timed-out channel");
    $display("PASS APF: boot, cartridge power, slots, save-state rejection, target error/timeout");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
