`timescale 1ns/1ps
module tb_backup_allocator;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,start=0,is_save=0,cancel=0;
wire busy,done,error,report_path,file_request;
wire [7:0] error_code;
wire [13:0] number;
wire [15:0] digits;
wire [15:0] file_slot;
reg file_ready=1,file_done=0;
reg [15:0] file_result=0;
integer scenario=0,requests=0,delay=0;
backup_allocator #(.LAST_NUMBER(3)) dut(.*);
always @(posedge clk) begin
 file_done<=0;
 if(file_request) begin
  requests<=requests+1;delay<=4;
  case(scenario)
   0:file_result<=number==1 || (number==2 && report_path) ? 0 : 3;
   1:file_result<=16'hFFFF;
   2:file_result<=0;
   3:file_result<=3;
  endcase
  if(file_slot!==(is_save ? (report_path ? 6 : 5) : (report_path ? 2 : 1))) $fatal(1,"output slot");
 end
 if(delay>0) begin delay<=delay-1;if(delay==1) file_done<=1;end
end
task run(input integer mode);
begin
 @(negedge clk);reset_n=0;cancel=0;scenario=mode;requests=0;
 repeat(2) @(negedge clk);reset_n=1;
 @(negedge clk);start=1;@(negedge clk);start=0;
end endtask
initial begin
 run(0);wait(done);#1;if(error || number!=3 || requests!=5) $fatal(1,"partial pairs not skipped");
 is_save=1;run(1);wait(done);#1;if(!error || error_code!=5 || number!=1 || requests!=1) $fatal(1,"SD error treated as free");
 run(2);wait(done);#1;if(!error || error_code!=14 || requests!=3) $fatal(1,"exhaustion");
 run(3);wait(file_request);@(negedge clk);cancel=1;wait(done);#1;
 if(!error || error_code!=6 || requests!=1 || delay!=0) $fatal(1,"cancel did not drain late reply");
 $display("PASS backup_allocator: partial pairs, slots, errors, exhaustion, cancellation drains reply");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
