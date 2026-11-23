`timescale 1ns/1ps
module tb_allocator_digits;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,start=0;
wire done,file_request;
wire [13:0] number;
wire [15:0] digits;
reg file_done=0;
integer expected_digits,requests=0;
backup_allocator dut(.clk(clk),.reset_n(reset_n),.start(start),.is_save(1'b0),.cancel(1'b0),
 .done(done),.file_request(file_request),.number(number),.digits(digits),
 .file_ready(1'b1),.file_done(file_done),.file_result(16'b0));
always @(posedge clk) begin
 file_done<=file_request;
 if(file_request) begin
  expected_digits=((number/1000)%10)*4096+((number/100)%10)*256+((number/10)%10)*16+number%10;
  if(digits!==expected_digits[15:0]) $fatal(1,"BCD mismatch %d %h",number,digits);
  requests<=requests+1;
 end
end
initial begin
 repeat(3) @(negedge clk);reset_n=1;start=1;@(negedge clk);start=0;
 wait(done);#1;if(number!=9999 || digits!==16'h9999 || requests!=9999) $fatal(1,"BCD exhaustive range");
 $display("PASS allocator_digits: all 9999 binary/decimal names including carries");$finish;
end
endmodule
