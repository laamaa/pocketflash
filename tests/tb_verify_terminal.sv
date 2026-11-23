`timescale 1ns / 1ps
module tb_verify_terminal;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset_n = 0;
    reg [15 : 0] keys = 0;
    wire file_request, read_request;
    wire [24 : 0] read_address;
    wire [15 : 0] ram_offset;
    wire [7 : 0] status, error_code;
    reg file_done = 0, read_done = 0;
    reg [15 : 0] read_q = 0;
    pocketflash_app #(.VERIFY_ONLY(1),
                      .ROM_BYTES(65536),
                      .INPUT_SLOT(4))
        dut(.clk(clk),
            .reset_n(reset_n),
            .in_menu(1'b0),
            .cart_powered(1'b1),
            .keys(keys),
            .input_size(32'd65536),
            .input_changed(1'b0),
            .status(status),
            .error_code(error_code),
            .file_request(file_request),
            .file_ready(1'b1),
            .file_done(file_done),
            .file_result(16'b0),
            .ram_offset(ram_offset),
            .ram_q(ram_offset >> 1),
            .read_request(read_request),
            .read_address(read_address),
            .read_ready(1'b1),
            .read_done(read_done),
            .read_error(1'b0),
            .read_q(read_q),
            .completion_ready(1'b1),
            .completion_error(1'b0),
            .source_failed(1'b0));
    always @(posedge clk) begin
        file_done <= file_request;
        read_done <= read_request;
        if (read_request)
            read_q <= read_address >> 1;
    end
    initial begin
        repeat (3) @(negedge clk)
            ;
        reset_n = 1;
        repeat (3) @(negedge clk)
            ;
        keys = 16'h10;
        @(negedge clk);
        keys = 0;
        wait(dut.state == 17 && read_address == 65534);
        @(negedge clk);
        keys = 16'h20;
        wait(status == 5 || status == 255);
        if (status != 255 || error_code != 6)
            $fatal(1, "last comparison cancellation reported success");
        $display("PASS verify_terminal: B on final NEXT_COMPARE wins success");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "timeout");
    end
endmodule
