`timescale 1ns / 1ps
module tb_rom_header;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset_n = 0, start_write = 0, cancel = 0;
    wire armed, done, header_valid, file_request, flash_request;
    wire [15 : 0] ram_offset;
    reg [15 : 0] ram_q = 0, memory[0 : 255];
    reg file_done = 0, flash_done = 0;
    rom_writer #(.ROM_BYTES(512),
                 .SECTOR_BYTES(512))
        dut(.clk(clk),
            .reset_n(reset_n),
            .start_write(start_write),
            .confirm(1'b0),
            .cancel(cancel),
            .in_menu(1'b0),
            .cart_powered(1'b1),
            .input_changed(1'b0),
            .target_size(32'd192),
            .armed(armed),
            .done(done),
            .header_valid(header_valid),
            .file_request(file_request),
            .file_ready(1'b1),
            .file_done(file_done),
            .file_result(16'b0),
            .file_poisoned(1'b0),
            .ram_offset(ram_offset),
            .ram_q(ram_q),
            .read_ready(1'b1),
            .read_done(1'b0),
            .read_error(1'b0),
            .read_q(16'hFFFF),
            .flash_request(flash_request),
            .flash_ready(1'b1),
            .flash_done(flash_done),
            .flash_error(1'b0),
            .flash_poisoned(1'b0),
            .buffer_offset(16'b0));
    always @(posedge clk) begin
        file_done <= file_request;
        flash_done <= flash_request;
        ram_q <= memory[ram_offset >> 1];
    end
    integer i;
    task start;
        begin
            @(negedge clk);
            reset_n = 0;
            cancel = 0;
            repeat (3) @(negedge clk)
                ;
            reset_n = 1;
            @(negedge clk);
            start_write = 1;
            @(negedge clk);
            start_write = 0;
            wait(armed);
            #1;
        end
    endtask
    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 0;
        memory[89] = 16'h0096;
        memory[94] = 16'h5100;
        start();
        if (!header_valid)
            $fatal(1, "valid header warning");
        @(negedge clk);
        cancel = 1;
        wait(done);
        memory[94] = 16'h5000;
        start();
        if (header_valid)
            $fatal(1, "invalid header accepted as valid");
        $display({"PASS rom_header: pipelined checksum and invalid-header warning without ",
                  "identity gate"});
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule
