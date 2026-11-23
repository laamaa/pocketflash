`timescale 1ns/1ps
module tb_flash_ops #(parameter ALLOW_WRITE=1, FULL_RANGE=0);
reg clk=0;always #5 clk=~clk;
reg reset_n=0,request=0;
reg [1:0] operation=0;
reg [24:0] address=25'h1FE0000;
wire ready,done,error,identified,swapped,completion_known,read_mode,poisoned;
wire [15:0] raw_status;
wire [15:0] manufacturer,device;
wire [7:0] stage;
wire bus_request,bus_write;
wire [24:0] bus_address;
wire [15:0] bus_data,buffer_offset;
reg [15:0] buffer_q=0;
reg bus_done=0,bus_error=0;
reg [15:0] bus_q=0;
reg pending=0;
wire bus_ready=!pending;
reg status_seen_error=0;
reg unknown_geometry=0,unknown_status=0;
reg model_swap=0,bad_geometry=0,busy_forever=0,status_error=0;
integer model_mode=0,unlock=0,write_phase=0,payload_count=0,total_writes=0;
flash_ops #(.ALLOW_QUERY(1),.ALLOW_PROGRAM(ALLOW_WRITE),.WRITE_BEGIN(FULL_RANGE ? 25'h0 : 25'h1FE0000),.WRITE_END(25'h1FFFFFF),.ERASE_TIMEOUT(3000),.PROGRAM_TIMEOUT(30000)) dut(.*);
function [15:0] enc(input [15:0] x);
    enc=model_swap ? {x[15:2],x[0],x[1]} : x;
endfunction
function [15:0] cfi(input [24:0] a);
begin
case(a)
25'h20:cfi=16'h51;25'h22:cfi=16'h52;25'h24:cfi=16'h59;
25'h26:cfi=unknown_geometry ? 16'hxxxx : 2;25'h28:cfi=0;25'h4E:cfi=bad_geometry ? 24 : 25;
25'h54:cfi=9;25'h56:cfi=0;25'h58:cfi=1;
25'h5A:cfi=255;25'h5C:cfi=0;25'h5E:cfi=0;25'h60:cfi=2;
default:cfi=0;
endcase
end endfunction
always @(posedge clk) begin
    // A synchronous RAM supplying payload words, exercising address latency.
    buffer_q<=buffer_offset ^ 16'hA55A;
    bus_done<=0;
    if(pending) begin pending<=0;bus_done<=1;end
    if(bus_request && bus_ready) begin
        pending<=1;
        if(bus_write) begin
            total_writes=total_writes+1;
            if(write_phase==2) begin
                if(bus_address!==address+payload_count*2 || bus_data!==((payload_count*2)^16'hA55A))
                    $fatal(1,"payload address/data altered at word %0d: %h %h",payload_count,bus_address,bus_data);
                payload_count=payload_count+1;
                if(payload_count==256) write_phase=3;
            end else if(write_phase==1) begin
                if(bus_data!==enc(16'hFF)) $fatal(1,"buffer count encoding");
                write_phase=2;payload_count=0;
            end else if(write_phase==3) begin
                if(bus_data!==enc(16'h29) || bus_address!=={address[24:17],17'b0}) $fatal(1,"buffer confirm");
                write_phase=0;
            end else if(bus_data==16'hF0) begin model_mode=0;unlock=0;end
            else if(bus_address==25'hAA && bus_data==16'h98) model_mode=1;
            else if(bus_address==25'hAAA && bus_data==enc(16'hAA)) unlock=1;
            else if(bus_address==25'h554 && bus_data==enc(16'h55) && unlock==1) unlock=2;
            else if(bus_address==25'hAAA && bus_data==enc(16'h90) && unlock==2) model_mode=2;
            else if(bus_data==enc(16'h25) && unlock==2) write_phase=1;
            else if(bus_address==25'hAAA && bus_data==enc(16'h70)) model_mode=3;
            else if(bus_address==25'hAAA && bus_data==enc(16'h71) && status_seen_error) begin
                status_error=0;status_seen_error=0;
            end
        end else case(model_mode)
            1:bus_q<=enc(cfi(bus_address));
            2:bus_q<=enc(bus_address==0 ? 16'h0001 : 16'h227E);
            3:begin
                bus_q<=enc(busy_forever ? 16'h0000 : status_error ? 16'h0090 : unknown_status ? 16'h008x : 16'h0080);
                if(status_error) status_seen_error=1;
            end
            default:bus_q<=16'hFFFF;
        endcase
    end
end
task op(input [1:0] kind,input bit expect_error);
begin
    wait(ready);@(negedge clk);operation=kind;request=1;
    @(negedge clk);request=0;wait(done);#1;
    if(error!==expect_error) $fatal(1,"op %0d error=%b expected=%b",kind,error,expect_error);
    @(negedge clk);
end endtask
task rejected(input [1:0] kind,input [24:0] target);
integer before_count;
begin
    address=target;before_count=total_writes;
    op(kind,1);
    if(total_writes!=before_count) $fatal(1,"rejected target caused bus writes: %h",target);
end endtask
integer writes_before;
initial begin
    repeat(3) @(negedge clk);reset_n=1;
    op(2,1);if(total_writes!=0) $fatal(1,"unidentified chip received writes");
    op(0,0);if(!identified || swapped) $fatal(1,"standard CFI/ID");
    if(!ALLOW_WRITE) begin
        rejected(1,25'h1FE0000);rejected(2,25'h1FE0000);
        $display("PASS flash_disabled: successful probe cannot enable compiled-out programming");$finish;
    end
    if(FULL_RANGE) begin
        address=0;op(1,0);op(2,0);
        address=25'h20000;op(1,0);op(2,0);
        address=25'h1FE0000;op(1,0);address=25'h1FFFE00;op(2,0);
        rejected(1,25'h20002);rejected(2,25'h1FFFFFF);rejected(3,0);
        $display("PASS flash_full_range: first/middle/last sectors, last buffer, alignment and operation bounds");$finish;
    end
    rejected(1,25'h0000000);rejected(1,25'h1FC0000);
    rejected(1,25'h1FE0002);rejected(2,25'h1FDFE00);
    rejected(2,25'h1FE0002);rejected(2,25'h1FFFFFF);rejected(3,25'h1FE0000);
    address=25'h1FE0000;
    op(1,0);op(2,0);
    address=25'h1FFFE00;op(2,0);address=25'h1FE0000;if(payload_count!=256) $fatal(1,"incomplete buffer");
    status_error=1;op(1,1);status_error=0;
    op(0,0);busy_forever=1;op(1,1);busy_forever=0;
    writes_before=total_writes;op(0,1);
    if(total_writes!=writes_before) $fatal(1,"query bypassed unknown completion");
    @(negedge clk);reset_n=0;@(negedge clk);reset_n=1;model_swap=1;model_mode=0;unlock=0;
    op(0,0);if(!identified || !swapped) $fatal(1,"swapped CFI/ID");
    rejected(1,25'h1FC0000);rejected(2,25'h1FDFE00);address=25'h1FE0000;
    op(2,0);
    unknown_geometry=1;op(0,1);if(identified) $fatal(1,"unknown geometry accepted");unknown_geometry=0;
    op(0,0);unknown_status=1;op(1,1);
    if(!poisoned || completion_known) $fatal(1,"unknown status accepted as known completion");
    unknown_status=0;
    @(negedge clk);reset_n=0;@(negedge clk);reset_n=1;
    bad_geometry=1;op(0,1);if(identified) $fatal(1,"bad geometry accepted");
    writes_before=total_writes;op(1,1);
    if(total_writes!=writes_before) $fatal(1,"failed probe permitted erase");
    $display("PASS flash_ops: query mapping, geometry, payload, buffer limits, gating, status errors/timeouts");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
