`timescale 1ns/1ps
module tb_save_reader #(parameter UNSUPPORTED=0);
reg clk=0;always #5 clk=~clk;
reg core_reset_n=0,app_reset_n=1,cart_powered=1,start=0,close=0,word_request=0;
reg [16:0] address=0;
wire word_ready,word_done,word_error,busy,done,error,poisoned;
wire [15:0] word_q,identity;
wire bus_request,bus_bank,bus_ready,bus_done,bus_error,bus_poisoned;
wire [1:0] bus_operation;
wire [15:0] bus_address,bus_q,pin_address;
wire [7:0] pin_out,pin_in;
wire pin_drive,cs2_n,rd_n,wr_n;
save_reader dut(.*);
save_bus #(.TICKS(2),.DEADLINE(1000)) transport(.clk(clk),.reset_n(core_reset_n),.cart_powered(cart_powered),
 .request(bus_request),.operation(bus_operation),.address(bus_address),.bank(bus_bank),.ready(bus_ready),
 .done(bus_done),.error(bus_error),.poisoned(bus_poisoned),.q(bus_q),.address_out(pin_address),
 .data_out(pin_out),.data_in(pin_in),.data_drive(pin_drive),.cs2_n(cs2_n),.rd_n(rd_n),.wr_n(wr_n));
save_model #(.ID(UNSUPPORTED ? 16'h1234 : 16'hC209)) model(.clk(clk),.cs2_n(cs2_n),.rd_n(rd_n),.wr_n(wr_n),.data_drive(pin_drive),
 .address(pin_address),.data_out(pin_out),.data_in(pin_in));
task open;
begin @(negedge clk);start=1;@(negedge clk);start=0;wait(word_ready || done);
if(!word_ready || identity!==16'hC209) $fatal(1,"save session open");end endtask
task readword(input [16:0] a,input [15:0] expected);
begin wait(word_ready);@(negedge clk);address=a;word_request=1;@(negedge clk);word_request=0;
wait(word_done);#1;if(word_error || word_q!==expected) $fatal(1,"save read %h: %h",a,word_q);end endtask
initial begin
 repeat(3) @(negedge clk);core_reset_n=1;
 if(UNSUPPORTED) begin
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(bus_request);@(negedge clk);app_reset_n=0;wait(done);#1;
  if(!error || !poisoned || model.writes!=5) $fatal(1,"unsupported ID cleanup emitted bank commands");
  $display("PASS save_unsupported: unknown logical ID blocks bank commands even during app reset");$finish;
 end
 open();readword(17'h0FFFE,16'h0001);readword(17'h10000,16'hA4A5);readword(17'h11234,16'h8283);
 @(negedge clk);close=1;@(negedge clk);close=0;wait(done);#1;
 if(error || poisoned || model.bank || model.phase || model.id_mode) $fatal(1,"save session cleanup");
 open();readword(17'h10000,16'hA4A5);
 @(negedge clk);app_reset_n=0;wait(done);#1;
 if(poisoned || model.bank || model.phase || model.id_mode) $fatal(1,"app reset skipped bank0 cleanup");
 @(negedge clk);app_reset_n=1;
 open();readword(17'h10000,16'hA4A5);
 @(negedge clk);close=1;@(negedge clk);close=0;wait(bus_request && bus_operation==3);
 force bus_error=1;wait(done);#1;release bus_error;
 if(!poisoned || !error || word_ready) $fatal(1,"failed cleanup did not poison");
 @(negedge clk);app_reset_n=0;repeat(3) @(negedge clk);app_reset_n=1;
 if(!poisoned) $fatal(1,"app reset cleared save poison");
 $display("PASS save_reader: full bank addressing, byte order, app-reset cleanup, cleanup poison");$finish;
end
initial begin #200000;$fatal(1,"save reader timeout");end
endmodule
