`timescale 1ns / 1ps
module tb_pocketflash_app
    #(parameter STRONG = 0);
    wire busy;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset_n = 0, in_menu = 0, cart_powered = 1, input_changed = 0;
    reg [15 : 0] keys = 0;
    reg [31 : 0] input_size = 0;
    wire [7 : 0] status, error_code;
    wire [31 : 0] progress, seconds, crc, sd_crc, open_flags, open_size;
    wire [24 : 0] error_address;
    wire [15 : 0] expected, observed;
    wire report_path, file_request;
    wire [15 : 0] file_command, file_slot;
    wire [31 : 0] file_offset, file_address, file_length;
    wire file_ready = 1;
    reg file_done = 0;
    reg [15 : 0] file_result = 0;
    wire ram_wr;
    wire [15 : 0] ram_offset, ram_data, ram_q;
    wire read_request;
    wire [24 : 0] read_address;
    wire read_ready = 1;
    reg read_done = 0, read_error = 0;
    reg [15 : 0] read_q = 0;
    wire completion_ready = 1, completion_error = 0, source_failed = 0;
    wire completion_wait;
    pocketflash_app #(.ROM_BYTES(131072),
                      .CLOCK_HZ(1000),
                      .BACKUP_SLOT(STRONG ? 5 : 1),
                      .RECORD_SLOT(STRONG ? 6 : 2),
                      .RECORD_MAGIC(STRONG ? 32'h31534650 : 32'h31524650))
        dut(.*);
    reg bridge_wr = 0, bridge_rd = 0;
    reg [15 : 0] bridge_offset = 0;
    reg [31 : 0] bridge_data = 0;
    wire [31 : 0] bridge_q;
    transfer_ram memory(.clk(clk),
                        .bridge_wr(bridge_wr),
                        .bridge_rd(bridge_rd),
                        .bridge_offset(bridge_offset),
                        .bridge_data(bridge_data),
                        .bridge_q(bridge_q),
                        .engine_wr(ram_wr),
                        .engine_offset(ram_offset),
                        .engine_data(ram_data),
                        .engine_q(ram_q));
    reg backup_exists = 0, marker_exists = 0, fail_write = 0, corrupt_rom = 0, corrupt_marker = 0;
    reg [15 : 0] probe_error = 0, reopen_error = 0, read_result = 0;
    reg [31 : 0] rom_file[0 : 32767], marker_file[0 : 3];
    integer reports = 0, phase = 0, offset = 0, write_length = 0, slot = 0, reads = 0, base = 0,
            verified_bytes = 0;
    function [31 : 0] expected_word
        (input integer off);
        reg [15 : 0] lo, hi;
        begin
            lo = off / 2;
            hi = lo + 1;
            expected_word = {lo[7 : 0], lo[15 : 8], hi[7 : 0], hi[15 : 8]};
        end
    endfunction
    always @(posedge clk) begin
        read_done <= read_request;
        file_done <= 0;
        bridge_rd <= 0;
        bridge_wr <= 0;
        if (read_request) begin
            read_q <=
                (read_address >> 1) ^
                ((STRONG && corrupt_rom && status == 7 && read_address == 131070) ? 16'h0100 : 0);
            reads <= reads + 1;
        end
        if (file_request) begin
            file_result <= 0;
            if (file_command == 16'h0192) begin
                if (open_flags == 0) begin
                    file_result <= probe_error
                                       ? probe_error
                                       : ((report_path ? marker_exists : backup_exists) ? 0 : 3);
                    if (backup_exists && !report_path && reopen_error)
                        file_result <= reopen_error;
                end else begin
                    if (file_slot == (STRONG ? 5 : 1))
                        backup_exists <= 1;
                    if (file_slot == (STRONG ? 6 : 2)) begin
                        if (verified_bytes != 131072)
                            $fatal(1, "completion marker created before full ROM readback");
                        marker_exists <= 1;
                    end
                    file_result <= 1;
                end
                file_done <= 1;
            end else if (file_command == 16'h0184) begin
                if (fail_write) begin
                    file_result <= 2;
                    file_done <= 1;
                end else begin
                    offset = 0;
                    write_length = file_length;
                    slot = file_slot;
                    base = file_offset;
                    phase = 1;
                end
            end else if (file_command == 16'h0180) begin
                if (read_result) begin
                    file_result <= read_result;
                    file_done <= 1;
                end else begin
                    offset = 0;
                    write_length = file_length;
                    slot = file_slot;
                    base = file_offset;
                    if (file_slot == (STRONG ? 5 : 1) && file_offset != verified_bytes)
                        $fatal(1, "missing/repeated ROM readback chunk");
                    phase = 5;
                end
            end else if (file_command == 16'h0188)
                $fatal(1, "unacknowledged flush opcode reused");
            else
                $fatal(1, "unexpected file command");
        end
        if (phase == 1) begin
            bridge_offset <= offset;
            phase = 2;
        end else if (phase == 2) begin
            bridge_rd <= 1;
            phase = 3;
        end else if (phase == 3)
            phase = 4;
        else if (phase == 4) begin
            if (slot == (STRONG ? 5 : 1)) begin
                if (bridge_q !== expected_word(base + offset))
                    $fatal(1, "dump data endian/order at %h: %h", base + offset, bridge_q);
                rom_file[(base + offset) / 4] <= bridge_q;
            end
            if (slot == (STRONG ? 6 : 2))
                case (offset)
                    0:
                        if (bridge_q !== (STRONG ? 32'h50465331 : 32'h50465231))
                            $fatal(1, "marker magic");
                    4:
                        if (bridge_q !== 32'h00000200)
                            $fatal(1, "marker size");
                    // Independent zlib fixture: little-endian halfwords 0..65535.
                    8:
                        if (bridge_q !== 32'h09CFB811)
                            $fatal(1, "marker CRC or byte order");
                    12:
                        if (bridge_q !== 32'h03000000)
                            $fatal(1, "marker readback flag");
                endcase
            if (slot == (STRONG ? 6 : 2))
                marker_file[offset / 4] <= bridge_q;
            if (offset + 4 == write_length) begin
                phase = 0;
                file_done <= 1;
                if (slot == (STRONG ? 6 : 2))
                    reports <= reports + 1;
            end else begin
                offset = offset + 4;
                phase = 1;
            end
        end else if (phase == 5) begin
            bridge_offset <= offset;
            bridge_wr <= 1;
            if (slot == (STRONG ? 5 : 1))
                bridge_data <=
                    rom_file[(base + offset) / 4] ^
                    ((!STRONG && corrupt_rom && base + offset == 131068) ? 32'b1 : 32'b0);
            else
                bridge_data <=
                    marker_file[offset / 4] ^ ((corrupt_marker && offset == 4) ? 32'b1 : 32'b0);
            if (offset + 4 == write_length)
                phase = 6;
            else
                offset = offset + 4;
        end else if (phase == 6) begin
            phase = 0;
            file_done <= 1;
            if (slot == (STRONG ? 5 : 1))
                verified_bytes <= verified_bytes + write_length;
        end
    end
    task press
        (input integer bit_index);
        begin
            @(negedge clk);
            keys = 1 << bit_index;
            @(negedge clk);
            keys = 0;
            @(negedge clk);
        end
    endtask
    task restart;
        begin
            @(negedge clk);
            reset_n = 0;
            keys = 0;
            repeat (3) @(negedge clk)
                ;
            reset_n = 1;
            repeat (3) @(negedge clk)
                ;
            backup_exists = 0;
            marker_exists = 0;
            reports = 0;
            reads = 0;
            verified_bytes = 0;
            probe_error = 0;
            reopen_error = 0;
            read_result = 0;
            fail_write = 0;
            corrupt_rom = 0;
            corrupt_marker = 0;
            cart_powered = 1;
        end
    endtask
    initial begin
        restart();
        press(4);
        wait(status == 5);
        @(negedge clk);
        if (reports != 1 || progress != 131072 || verified_bytes != 131072 ||
            ~crc !== 32'h11B8CF09 || sd_crc !== crc)
            $fatal(1, "multi-chunk backup/readback did not complete");
        press(4);
        wait(status == 255);
        if (error_code != 4 || reports != 1)
            $fatal(1, "existing backup overwritten");
        restart();
        marker_exists = 1;
        press(4);
        wait(status == 255);
        if (error_code != 4 || backup_exists || reads != 0 || reports != 0)
            $fatal(1, "orphan marker was reused");
        restart();
        probe_error = 16'hFFFF;
        press(4);
        wait(status == 255);
        if (error_code != 5 || expected != 16'h0192 || observed != 16'hFFFF || backup_exists ||
            reads != 0)
            $fatal(1, "backup probe diagnostics lost");
        restart();
        press(4);
        wait(reads > 20);
        press(5);
        wait(status == 255);
        if (error_code != 6 || reports != 0)
            $fatal(1, "cancelled dump marked complete");
        restart();
        fail_write = 1;
        press(4);
        wait(status == 255);
        if (error_code != 5 || reports != 0)
            $fatal(1, "failed dump marked complete");
        restart();
        reopen_error = 16'hFFFF;
        press(4);
        wait(status == 255);
        if (error_code != 5 || expected != 16'h0192 || observed != 16'hFFFF || reports != 0)
            $fatal(1, "reopen timeout marked complete or lost diagnostics");
        restart();
        reopen_error = 1;
        press(4);
        wait(status == 255);
        if (error_code != 5 || reports != 0)
            $fatal(1, "reopen unexpectedly creating a file was accepted");
        restart();
        press(4);
        wait(status == 7);
        press(5);
        wait(status == 255);
        if (error_code != 6 || reports != 0)
            $fatal(1, "cancelled SD readback marked complete");
        restart();
        corrupt_rom = 1;
        press(4);
        wait(status == 255);
        if (error_code != 8 || reports != 0 || verified_bytes != 131072)
            $fatal(1, "corrupt second chunk accepted: code=%d reports=%d bytes=%d", error_code,
                   reports, verified_bytes);
        restart();
        corrupt_marker = 1;
        press(4);
        wait(status == 255);
        if (error_code != 12 || reports != 1)
            $fatal(1, "corrupt completion record accepted");
        if (STRONG) begin
            restart();
            press(4);
            wait(reads > 20);
            @(negedge clk);
            cart_powered = 0;
            wait(status == 255 || status == 5);
            if (status != 255 || reports != 0)
                $fatal(1, "power loss certified a backup");
        end
        $display({"PASS app: multi-chunk backup/readback, marker verification, corruption/errors, ",
                  "cancellation and source power loss"});
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "timeout");
    end
endmodule
