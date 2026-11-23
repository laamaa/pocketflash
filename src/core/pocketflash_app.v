// Read-only backup and full-ROM comparison worker.
// Backups reread both the file and physical source before committing a marker.
`timescale 1ns / 1ps
`default_nettype none
module pocketflash_app
    #(parameter VERIFY_ONLY = 0,
      parameter INPUT_SLOT = 4,
      parameter ROM_BYTES = 33554432,
      parameter CLOCK_HZ = 74250000,
      parameter BACKUP_SLOT = 1, RECORD_SLOT = 2,
      parameter RECORD_MAGIC = 32'h31524650,
      parameter WAIT_COMPLETION = 0)
    (input wire clk, reset_n, in_menu, cart_powered,
     input wire [15 : 0] keys,
     input wire [31 : 0] input_size,
     input wire input_changed,
     output wire busy,
     output reg [7 : 0] status, error_code,
     output reg [31 : 0] progress, seconds,
     output reg [24 : 0] error_address,
     output reg [15 : 0] expected, observed,
     output reg [31 : 0] crc, sd_crc,
     output reg [31 : 0] open_flags, open_size,
     output reg report_path,
     output reg file_request,
     output reg [15 : 0] file_command, file_slot,
     output reg [31 : 0] file_offset, file_address, file_length,
     input wire file_ready, file_done,
     input wire [15 : 0] file_result,
     output reg ram_wr,
     output reg [15 : 0] ram_offset, ram_data,
     input wire [15 : 0] ram_q,
     output reg read_request,
     output reg [24 : 0] read_address,
     input wire read_ready, read_done, read_error,
     input wire [15 : 0] read_q,
     output wire completion_wait,
     input wire completion_ready, completion_error, source_failed);
    localparam IDLE = 0, OPEN_CHECK = 3, CREATE = 4, FILL_REQ = 5, FILL_WAIT = 6, WRITE_CHUNK = 7,
               AFTER_WRITE = 8, REOPEN = 9, REPORT_FILL = 10, REPORT_CREATE = 11, REPORT_WRITE = 12,
               REPORT_REOPEN = 13, INPUT_READ = 14, COMPARE_REQ = 15, COMPARE_WAIT = 16,
               NEXT_COMPARE = 17, FILE_ISSUE = 20, FILE_WAIT = 21, AFTER_CHECK = 22, COMPLETE = 23,
               READBACK_BEGIN = 24, READBACK_READ = 25, READBACK_SCAN = 26, READBACK_WAIT = 27,
               READBACK_CHUNK = 28, RECORD_READ = 29, RECORD_SCAN = 30, RECORD_WAIT = 31,
               SOURCE_REQ = 32, SOURCE_WAIT = 33, READBACK_NEXT = 34, CLOSE_SOURCE = 35;
    reg [5 : 0] state, return_state;
    reg [15 : 0] previous_keys, word_offset;
    wire [15 : 0] pressed = keys & ~previous_keys;
    assign completion_wait = state == CLOSE_SOURCE;
    reg cancel_pending;
    wire cancel_now = cancel_pending || (!in_menu && pressed[5] && !(status == 7 && report_path));

    reg input_stale, power_lost, source_failed_pending;
    reg [31 : 0] ticker, selected_size;
    reg [3 : 0] report_word;
    reg [15 : 0] last_file_result;
    assign busy = state != IDLE;
    wire active = state != IDLE;
    wire [31 : 0] dump_length = ROM_BYTES;
    wire [15 : 0] sampled_word = read_q;
    function [31 : 0] crc_byte;
        input [31 : 0] value;
        input [7 : 0] datum;
        reg [31 : 0] c;
        integer n;
        begin
            c = value ^ {24'b0, datum};
            for (n = 0; n < 8; n = n + 1)
                c = c[0] ? (c >> 1) ^ 32'hEDB88320 : c >> 1;
            crc_byte = c;
        end
    endfunction
    function [15 : 0] record_word;
        input [2 : 0] index;
        begin
            case (index)
                0:
                    record_word = RECORD_MAGIC[15 : 0];
                1:
                    record_word = RECORD_MAGIC[31 : 16];
                2:
                    record_word = ROM_BYTES & 65535;
                3:
                    record_word = ROM_BYTES >> 16;
                4:
                    record_word = ~crc[15 : 0];
                5:
                    record_word = ~crc[31 : 16];
                6:
                    record_word = 3;
                7:
                    record_word = 0; // complete + SD readback verified
            endcase
        end
    endfunction
    task transfer;
        input [15 : 0] cmd, slot;
        input [31 : 0] off, address, length;
        input [5 : 0] next;
        begin
            file_command <= cmd;
            file_slot <= slot;
            file_offset <= off;
            file_address <= address;
            file_length <= length;
            return_state <= next;
            state <= FILE_ISSUE;
        end
    endtask
    task fail;
        input [7 : 0] code;
        begin
            status <= 8'hFF;
            error_code <= code;
            state <= IDLE;
        end
    endtask
    always @(posedge clk) begin
        file_request <= 0;
        read_request <= 0;

        ram_wr <= 0;
        previous_keys <= keys;
        if (!reset_n) begin
            state <= IDLE;

            status <= 0;
            error_code <= 0;
            progress <= 0;
            seconds <= 0;
            ticker <= 0;
            cancel_pending <= 0;
            previous_keys <= 16'hFFFF;
            open_flags <= 0;
            open_size <= 0;
            report_path <= 0;

            crc <= 32'hFFFFFFFF;
            sd_crc <= 32'hFFFFFFFF;
            word_offset <= 0;

            input_stale <= 0;
            power_lost <= 0;
            source_failed_pending <= 0;
            error_address <= 0;
            expected <= 0;
            observed <= 0;
            ram_offset <= 0;
            ram_data <= 0;
            file_command <= 0;
            file_slot <= 0;
            file_offset <= 0;
            file_address <= 0;
            file_length <= 0;
            read_address <= 0;
            selected_size <= 0;
            report_word <= 0;
            last_file_result <= 0;
            return_state <= IDLE;
        end else begin
            if (active) begin
                if (source_failed)
                    source_failed_pending <= 1;
                if (cart_powered !== 1'b1)
                    power_lost <= 1;
                if (ticker == CLOCK_HZ - 1) begin
                    ticker <= 0;
                    seconds <= seconds + 1;
                end else
                    ticker <= ticker + 1;
                // Once the verified ROM's marker is being committed, finish that
                // short transaction rather than leave a cancelled, valid marker.
                if (!in_menu && pressed[5] && !(status == 7 && report_path))
                    cancel_pending <= 1;
                if (input_changed && status == 3)
                    input_stale <= 1;
            end
            case (state)
                IDLE:
                    if (!in_menu) begin
                        if (pressed[4]) begin
                            error_code <= 0;
                            progress <= 0;
                            seconds <= 0;
                            ticker <= 0;
                            cancel_pending <= 0;
                            crc <= 32'hFFFFFFFF;
                            sd_crc <= 32'hFFFFFFFF;
                            word_offset <= 0;
                            report_path <= 0;

                            input_stale <= 0;
                            power_lost <= 0;
                            source_failed_pending <= 0;
                            if (!cart_powered)
                                fail(1);
                            else if (VERIFY_ONLY) begin
                                if (input_size < 192 || input_size > ROM_BYTES ||
                                    input_size[1 : 0] != 0)
                                    fail(2);
                                else begin
                                    status <= 3;
                                    selected_size <= input_size;
                                    state <= INPUT_READ;
                                end
                            end else begin
                                status <= 2;
                                open_flags <= 0;
                                open_size <= 0;
                                state <= OPEN_CHECK;
                            end
                        end
                    end
                OPEN_CHECK:
                    transfer(16'h0192, report_path ? RECORD_SLOT : BACKUP_SLOT, 32'h10010000, 0, 0,
                             AFTER_CHECK);
                AFTER_CHECK: begin
                    if (last_file_result == 0)
                        fail(4); // existing backups must never be overwritten
                    else if (last_file_result == 3) begin
                        // Check the marker too: an old marker must never certify a
                        // new partial dump when only its original ROM was removed.
                        if (!report_path) begin
                            report_path <= 1;
                            state <= OPEN_CHECK;
                        end else begin
                            report_path <= 0;
                            open_flags <= 3;
                            open_size <= dump_length;
                            state <= CREATE;
                        end
                    end else begin
                        expected <= file_command;
                        observed <= last_file_result;
                        fail(5);
                    end
                end
                CREATE:
                    transfer(16'h0192, BACKUP_SLOT, 32'h10010000, 0, 0, FILL_REQ);
                FILL_REQ:
                    if (read_ready) begin
                        read_address <= progress + word_offset;
                        read_request <= 1;
                        state <= FILL_WAIT;
                    end
                FILL_WAIT:
                    if (read_done) begin
                        if (read_error || (^read_q) === 1'bx || power_lost || cart_powered !== 1'b1)
                            fail(3);
                        else begin
                            ram_offset <= word_offset;
                            ram_data <= sampled_word;
                            ram_wr <= 1;
                            crc <=
                                crc_byte(crc_byte(crc, sampled_word[7 : 0]), sampled_word[15 : 8]);
                            if (word_offset == 16'hFFFE)
                                state <= WRITE_CHUNK;
                            else begin
                                word_offset <= word_offset + 2;
                                state <= FILL_REQ;
                            end
                        end
                    end
                WRITE_CHUNK:
                    transfer(16'h0184, BACKUP_SLOT, progress, 32'h10000000, 65536, AFTER_WRITE);
                AFTER_WRITE: begin
                    progress <= progress + 65536;
                    word_offset <= 0;
                    if (progress + 65536 == dump_length || cancel_now)
                        state <= REOPEN;
                    else
                        state <= FILL_REQ;
                end
                // PocketOS 2.5 leaves 0188 unacknowledged on the tested device. Reopen
                // without create/resize, then verify the entire file before marking it.
                REOPEN: begin
                    open_flags <= 0;
                    transfer(16'h0192, BACKUP_SLOT, 32'h10010000, 0, 0, READBACK_BEGIN);
                end
                READBACK_BEGIN: begin
                    if (cancel_now)
                        fail(6);
                    else begin
                        progress <= 0;
                        word_offset <= 0;
                        ram_offset <= 0;
                        sd_crc <= 32'hFFFFFFFF;
                        status <= 7;
                        state <= READBACK_READ;
                    end
                end
                READBACK_READ: begin
                    if (cancel_now)
                        fail(6);
                    else
                        transfer(16'h0180, BACKUP_SLOT, progress, 32'h10000000, 65536,
                                 READBACK_SCAN);
                end
                READBACK_SCAN: begin
                    if (cancel_now)
                        fail(6);
                    else
                        state <= SOURCE_REQ;
                end
                SOURCE_REQ:
                    if (cancel_now)
                        fail(6);
                    else if (read_ready) begin
                        read_address <= progress + word_offset;
                        read_request <= 1;
                        state <= SOURCE_WAIT;
                    end
                SOURCE_WAIT:
                    if (read_done) begin
                        if (read_error || (power_lost || cart_powered !== 1'b1))
                            fail(3);
                        else if ((^ram_q) === 1'bx || read_q !== ram_q) begin
                            error_address <= progress + word_offset;
                            expected <= ram_q;
                            observed <= read_q;
                            fail(8);
                        end else begin
                            sd_crc <= crc_byte(crc_byte(sd_crc, ram_q[7 : 0]), ram_q[15 : 8]);
                            state <= READBACK_NEXT;
                        end
                    end
                READBACK_NEXT:
                    if (word_offset == 16'hFFFE)
                        state <= READBACK_CHUNK;
                    else begin
                        word_offset <= word_offset + 2;
                        ram_offset <= word_offset + 2;
                        state <= READBACK_WAIT;
                    end
                READBACK_WAIT:
                    state <= READBACK_SCAN;
                READBACK_CHUNK: begin
                    progress <= progress + 65536;
                    word_offset <= 0;
                    ram_offset <= 0;
                    if (cancel_now)
                        fail(6);
                    else if (progress + 65536 == dump_length) begin
                        if (sd_crc !== crc) begin
                            expected <= ~crc[15 : 0];
                            observed <= ~sd_crc[15 : 0];
                            fail(11);
                        end else
                            state <= WAIT_COMPLETION ? CLOSE_SOURCE : REPORT_FILL;
                    end else
                        state <= READBACK_READ;
                end
                // Save cleanup must restore bank zero and array mode before a
                // completion record can certify the backup. This handshake is
                // distinct from SD readback and cannot be folded into it.
                CLOSE_SOURCE:
                    if (cancel_now)
                        fail(6);
                    else if (completion_error)
                        fail(17);
                    else if (completion_ready)
                        state <= REPORT_FILL;
                REPORT_FILL: begin
                    if (power_lost)
                        fail(1);
                    else if (cancel_now)
                        fail(6);
                    else begin
                        report_path <= 1;
                        open_flags <= 3;
                        open_size <= 16;
                        ram_offset <= {11'b0, report_word, 1'b0};
                        ram_wr <= 1;
                        ram_data <= record_word(report_word[2 : 0]);
                        if (report_word == 7) begin
                            report_word <= 0;
                            state <= REPORT_CREATE;
                        end else
                            report_word <= report_word + 1;
                    end
                end
                REPORT_CREATE:
                    transfer(16'h0192, RECORD_SLOT, 32'h10010000, 0, 0, REPORT_WRITE);
                REPORT_WRITE:
                    transfer(16'h0184, RECORD_SLOT, 0, 32'h10000000, 16, REPORT_REOPEN);
                REPORT_REOPEN: begin
                    open_flags <= 0;
                    ram_offset <= 0;
                    word_offset <= 0;
                    transfer(16'h0192, RECORD_SLOT, 32'h10010000, 0, 0, RECORD_READ);
                end
                RECORD_READ:
                    transfer(16'h0180, RECORD_SLOT, 0, 32'h10000000, 16, RECORD_SCAN);
                RECORD_SCAN: begin
                    if (ram_q !== record_word(word_offset[3 : 1])) begin
                        error_address <= word_offset;
                        expected <= record_word(word_offset[3 : 1]);
                        observed <= ram_q;
                        fail(12);
                    end else if (word_offset == 14)
                        state <= COMPLETE;
                    else begin
                        word_offset <= word_offset + 2;
                        ram_offset <= word_offset + 2;
                        state <= RECORD_WAIT;
                    end
                end
                RECORD_WAIT:
                    state <= RECORD_SCAN;
                INPUT_READ: begin
                    if (cancel_now)
                        fail(6);
                    else if (input_stale || input_size != selected_size)
                        fail(7);
                    else if (progress >= selected_size) begin
                        ram_offset <= 0;
                        word_offset <= 0;
                        state <= COMPARE_REQ;
                    end else begin
                        ram_offset <= 0;
                        word_offset <= 0;
                        transfer(16'h0180, INPUT_SLOT, progress, 32'h10000000,
                                 selected_size - progress >= 65536 ? 65536
                                                                   : selected_size - progress,
                                 COMPARE_REQ);
                    end
                end
                COMPARE_REQ:
                    if (read_ready) begin
                        read_address <= progress + word_offset;
                        read_request <= 1;
                        state <= COMPARE_WAIT;
                    end
                COMPARE_WAIT:
                    if (read_done) begin
                        if (read_error || (power_lost || cart_powered !== 1'b1))
                            fail(3);
                        else if ((^read_q) === 1'bx ||
                                 (progress + word_offset < selected_size && (^ram_q) === 1'bx) ||
                                 read_q !==
                                     (progress + word_offset < selected_size ? ram_q : 16'hFFFF))
                        begin
                            error_address <= progress + word_offset;
                            observed <= read_q;
                            expected <= progress + word_offset < selected_size ? ram_q : 16'hFFFF;
                            fail(8);
                        end else
                            state <= NEXT_COMPARE;
                    end
                NEXT_COMPARE: begin
                    if (cancel_now)
                        fail(6);
                    else if (input_stale || input_changed || input_size != selected_size)
                        fail(7);
                    else if (word_offset == 16'hFFFE) begin
                        progress <= progress + 65536;
                        if (progress + 65536 == ROM_BYTES)
                            state <= COMPLETE;
                        else
                            state <= INPUT_READ;
                    end else begin
                        word_offset <= word_offset + 2;
                        ram_offset <= word_offset + 2;
                        state <= COMPARE_REQ;
                    end
                end
                FILE_ISSUE:
                    if (file_ready) begin
                        file_request <= 1;
                        state <= FILE_WAIT;
                    end
                FILE_WAIT:
                    if (file_done) begin
                        last_file_result <= file_result;
                        if (return_state == AFTER_CHECK || file_result == 0 ||
                            (file_command == 16'h0192 && open_flags[0] && file_result == 1))
                            state <= return_state;
                        else begin
                            error_address <= file_offset[24 : 0];
                            expected <= file_command;
                            observed <= file_result;
                            fail(5);
                        end
                    end
                COMPLETE: begin
                    if (status == 3 &&
                        (input_stale || input_changed || input_size != selected_size))
                        fail(7);
                    else if (status == 3 && (cancel_now || power_lost || (cart_powered !== 1'b1)))
                        fail(cancel_now ? 6 : 1);
                    else begin
                        status <= 5;
                        state <= IDLE;
                    end
                end
                default:
                    fail(10);
            endcase
            // Never abandon an accepted file transaction. Finish its acknowledgement
            // before terminating a source session that closed between word requests.
            if ((source_failed_pending || source_failed) && state != IDLE && state != FILE_ISSUE &&
                (state != FILE_WAIT || file_done) && !(status == 7 && report_path))
                fail(cancel_now ? 6 : 3);
        end
    end
endmodule
