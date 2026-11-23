// Full-ROM programming for the fixed, verified GL-S cartridge profile.
// Digests describe the complete padded image before confirmation; a checked
// sector cache is the only source of payload while the flash is mutating.
`timescale 1ns / 1ps
`default_nettype none
module rom_writer
    #(parameter ROM_BYTES = 33554432, SECTOR_BYTES = 131072)
    (input wire clk, reset_n, start_write, confirm, cancel, in_menu, cart_powered,
     input wire input_changed,
     input wire [31 : 0] target_size,
     output reg busy, armed, mutation_lock, restore_required, done,
     output reg [7 : 0] error_code, phase,
     output reg [31 : 0] progress, image_crc, programmed_buffers,
     output reg [8 : 0] erased_sectors,
     output reg header_valid,
     output reg [24 : 0] error_address,
     output reg [15 : 0] expected, observed,
     output reg file_request,
     output wire [15 : 0] file_command, file_slot,
     output wire [31 : 0] file_offset, file_address, file_length,
     input wire file_ready, file_done, file_poisoned,
     input wire [15 : 0] file_result,
     output wire [15 : 0] ram_offset,
     input wire [15 : 0] ram_q,
     output reg read_request,
     output wire [24 : 0] read_address,
     input wire read_ready, read_done, read_error,
     input wire [15 : 0] read_q,
     output reg flash_request,
     output reg [1 : 0] flash_operation,
     output reg [24 : 0] flash_address,
     input wire flash_ready, flash_done, flash_error, flash_poisoned,
     input wire [15 : 0] buffer_offset,
     output wire [15 : 0] buffer_q);
    localparam SECTORS = ROM_BYTES / SECTOR_BYTES;
    localparam IDLE = 0, FILE_REQ = 1, FILE_WAIT = 2, PREP = 3, SCAN = 4, ADVANCE = 5, SCAN_END = 6,
               PROBE_REQ = 7, PROBE_WAIT = 8, ARM = 9, LOAD = 10, CACHE_WRITE_WAIT = 11,
               CACHE_SETTLE = 12, CACHE_WORD_CHECK = 13, CACHE_PREP = 14, CACHE_SCAN = 15,
               CACHE_END = 16, ERASE_REQ = 17, ERASE_WAIT = 18, READ_REQ = 19, READ_WAIT = 20,
               PROGRAM_REQ = 21, PROGRAM_WAIT = 22, CHUNK_PREP = 23, CHUNK_LENGTH = 24;
    localparam TARGET = 2, SECTOR_LOAD = 3;
    localparam BLANK = 1, VERIFY = 2;
    reg [4 : 0] state;
    reg [1 : 0] pass, read_kind;
    reg stale, cancel_pending, power_lost, final_pass, digests_valid;
    reg [31 : 0] selected_target_size, chunk, crc, sector_crc, cache_crc;
    reg [31 : 0] sector_base, position, program_position, cache_position;
    reg [8 : 0] sector_index;
    reg [15 : 0] word_offset, saved_word;
    reg [7 : 0] header_sum;
    reg header_fixed, header_pending;
    reg [31 : 0] digests[0 : 255];
    reg [31 : 0] digest_q;
    reg [255 : 0] buffer_ff;
    reg cache_write;
    reg [15 : 0] cache_write_word, cache_write_data;
    wire [15 : 0] cache_q;
    wire source_changed = input_changed;
    wire sizes_changed = target_size != selected_target_size;
    wire stopping = stale || source_changed || sizes_changed || cancel_pending || cancel || in_menu;
    wire [7 : 0] stop_code = stale || source_changed || sizes_changed ? 8'd7 : 8'd6;
    wire [31 : 0] absolute_word = chunk + {16'b0, word_offset};
    wire [31 : 0] source_size = selected_target_size;
    wire [31 : 0] scan_end = pass == SECTOR_LOAD ? sector_base + SECTOR_BYTES : ROM_BYTES;
    wire [31 : 0] span_calc = scan_end - chunk > 65536 ? 32'd65536 : scan_end - chunk;
    wire [31 : 0] available = chunk >= source_size ? 0 : source_size - chunk;
    // Break sector-end/subtraction/minimum/zero-test into registered stages.
    // Keep these values stable through the APF request and complete chunk scan.
    reg [31 : 0] span, chunk_available, source_length;
    wire [15 : 0] source_word = absolute_word >= source_size ? 16'hFFFF : ram_q;
    wire [31 : 0] scan_cache_position = absolute_word - sector_base;
    wire [31 : 0] cache_address = state == PROGRAM_REQ || state == PROGRAM_WAIT
                                      ? program_position + buffer_offset
                                  : state == READ_REQ || state == READ_WAIT ? position - sector_base
                                  : state == CACHE_PREP || state == CACHE_SCAN || state == CACHE_END
                                      ? cache_position
                                      : scan_cache_position;
    sector_cache cache(.clk(clk),
                       .write_enable(cache_write),
                       .write_word(cache_write_word),
                       .write_data(cache_write_data),
                       .read_word(cache_address[16 : 1]),
                       .read_data(cache_q));
    always @(posedge clk)
        digest_q <= digests[sector_index[7 : 0]];
    assign buffer_q = cache_q;
    assign ram_offset = word_offset;
    assign file_command = 16'h0180;
    assign file_slot = 16'd4;
    assign file_offset = chunk;
    assign file_address = 32'h10000000;
    assign file_length = source_length;
    assign read_address = position[24 : 0];
    wire [15 : 0] wanted = read_kind == BLANK ? 16'hFFFF : cache_q;
    function [31 : 0] crc_byte
        (input [31 : 0] value,
         input [7 : 0] datum);
        reg [31 : 0] c;
        integer n;
        begin
            c = value ^ {24'b0, datum};
            for (n = 0; n < 8; n = n + 1)
                c = c[0] ? (c >> 1) ^ 32'hEDB88320 : c >> 1;
            crc_byte = c;
        end
    endfunction
    function [31 : 0] crc_word
        (input [31 : 0] value,
         input [15 : 0] datum);
        begin
            crc_word = crc_byte(crc_byte(value, datum[7 : 0]), datum[15 : 8]);
        end
    endfunction
    wire [31 : 0] next_crc = crc_word(crc, source_word);
    wire [31 : 0] next_sector_crc = crc_word(sector_crc, source_word);
    wire [31 : 0] next_read_crc = crc_word(sector_crc, read_q);
    task fail
        (input [7 : 0] code);
        begin
            error_code <= code;
            armed <= 0;
            busy <= 0;
            mutation_lock <= 0;
            done <= 1;
            state <= IDLE;
            // Any failed attempt leaves the ROM unverified, including cancellation
            // on the final cycle. Only a complete verified write clears this flag.
            restore_required <= 1;
        end
    endtask
    task start_scan
        (input [1 : 0] scan_pass);
        begin
            pass <= scan_pass;
            chunk <= 0;
            word_offset <= 0;
            crc <= 32'hFFFFFFFF;
            sector_crc <= 32'hFFFFFFFF;
            progress <= 0;
            state <= CHUNK_PREP;
        end
    endtask
    task next_sector;
        begin
            sector_index <= sector_index + 1'b1;
            sector_base <= sector_base + SECTOR_BYTES;
            state <= LOAD;
        end
    endtask
    always @(posedge clk) begin
        done <= 0;
        file_request <= 0;
        read_request <= 0;
        flash_request <= 0;
        cache_write <= 0;
        if (state != IDLE)
            phase <= {3'b0, state};
        if (!reset_n) begin
            state <= IDLE;
            pass <= TARGET;
            read_kind <= BLANK;
            busy <= 0;
            armed <= 0;
            mutation_lock <= 0;
            restore_required <= 1;
            error_code <= 0;
            phase <= 0;
            header_valid <= 0;
            header_sum <= 0;
            header_fixed <= 0;
            header_pending <= 0;
            progress <= 0;
            image_crc <= 0;
            programmed_buffers <= 0;
            erased_sectors <= 0;

            error_address <= 0;
            expected <= 0;
            observed <= 0;

            stale <= 0;
            cancel_pending <= 0;
            power_lost <= 0;
            final_pass <= 0;
            digests_valid <= 0;
            selected_target_size <= 0;
            chunk <= 0;
            span <= 0;
            chunk_available <= 0;
            source_length <= 0;
            crc <= 32'hFFFFFFFF;
            sector_crc <= 32'hFFFFFFFF;
            cache_crc <= 32'hFFFFFFFF;
            sector_base <= 0;
            position <= 0;
            program_position <= 0;
            cache_position <= 0;
            sector_index <= 0;
            word_offset <= 0;
            saved_word <= 0;

            buffer_ff <= 0;
            cache_write_word <= 0;
            cache_write_data <= 0;
            flash_operation <= 0;
            flash_address <= 0;
        end else begin
            if (header_pending) begin
                header_valid <= header_fixed && header_sum == 8'hE7;
                header_pending <= 0;
            end
            if (busy) begin
                if (source_changed || sizes_changed)
                    stale <= 1;
                if (cancel || in_menu)
                    cancel_pending <= 1;
                if (!cart_powered)
                    power_lost <= 1;
            end
            case (state)
                IDLE:
                    if (start_write) begin
                        busy <= 1;
                        armed <= 0;
                        error_code <= 0;
                        progress <= 0;
                        image_crc <= 0;

                        header_valid <= 0;
                        header_sum <= 0;
                        header_fixed <= 0;
                        header_pending <= 0;
                        expected <= 0;
                        observed <= 0;
                        error_address <= 0;
                        erased_sectors <= 0;
                        programmed_buffers <= 0;

                        selected_target_size <= target_size;
                        stale <= 0;
                        cancel_pending <= 0;
                        power_lost <= 0;
                        final_pass <= 0;
                        digests_valid <= 0;
                        sector_index <= 0;
                        sector_base <= 0;

                        pass <= TARGET;
                        if (!cart_powered || in_menu)
                            fail(1);
                        else if (target_size < 192 || target_size > ROM_BYTES ||
                                 target_size[1 : 0] != 0)
                            fail(2);
                        else if (file_poisoned)
                            fail(16);
                        else if (flash_poisoned)
                            fail(17);
                        else
                            state <= PROBE_REQ;
                    end
                CHUNK_PREP: begin
                    span <= span_calc;
                    chunk_available <= available;
                    state <= CHUNK_LENGTH;
                end
                CHUNK_LENGTH: begin
                    source_length <= chunk_available < span ? chunk_available : span;
                    state <= FILE_REQ;
                end
                FILE_REQ:
                    if (file_poisoned)
                        fail(16);
                    else if (source_length == 0)
                        state <= PREP;
                    else if (file_ready) begin
                        file_request <= 1;
                        state <= FILE_WAIT;
                    end
                FILE_WAIT:
                    if (file_done) begin
                        if (file_result != 0)
                            fail(file_result == 16'hFFFF ? 8'd16 : 8'd5);
                        else
                            state <= PREP;
                    end
                PREP:
                    state <= SCAN;
                SCAN:
                    if ((^source_word) === 1'bx)
                        fail(13);
                    else begin
                        saved_word <= source_word;
                        crc <= next_crc;
                        // Header bytes are inside the minimum 192-byte image. Decode the
                        // first chunk directly and register the checksum before its flag.
                        if (pass == TARGET) begin
                            if (chunk == 0 && word_offset >= 16'hA0 && word_offset <= 16'hBC)
                                header_sum <= header_sum + ram_q[7 : 0] + ram_q[15 : 8];
                            if (chunk == 0 && word_offset == 16'hB2)
                                header_fixed <= ram_q[7 : 0] == 8'h96;
                            if (chunk == 0 && word_offset == 16'hBC)
                                header_pending <= 1;
                        end
                        if (pass != SECTOR_LOAD) begin
                            if ((absolute_word + 2) % SECTOR_BYTES == 0) begin
                                digests[absolute_word / SECTOR_BYTES] <= ~next_sector_crc;
                                sector_crc <= 32'hFFFFFFFF;
                            end else
                                sector_crc <= next_sector_crc;
                        end
                        if (pass == SECTOR_LOAD) begin
                            cache_write <= 1;
                            cache_write_word <= scan_cache_position[16 : 1];
                            cache_write_data <= source_word;
                            state <= CACHE_WRITE_WAIT;
                        end else
                            state <= ADVANCE;
                    end
                // cache_write is registered. Its write edge returns OLD_DATA;
                // keep a non-colliding read edge before checking the cached word.
                // Removing either wait recreates the physical sector-test bug.
                CACHE_WRITE_WAIT:
                    state <= CACHE_SETTLE;
                CACHE_SETTLE:
                    state <= CACHE_WORD_CHECK;
                CACHE_WORD_CHECK:
                    if (cache_q !== saved_word) begin
                        expected <= saved_word;
                        observed <= cache_q;
                        error_address <= absolute_word[24 : 0];
                        fail(13);
                    end else
                        state <= ADVANCE;
                ADVANCE: begin
                    progress <= absolute_word + 2;
                    if (absolute_word + 2 >= scan_end)
                        state <= SCAN_END;
                    else if ({16'b0, word_offset} + 2 >= span) begin
                        chunk <= chunk + span;
                        word_offset <= 0;
                        state <= CHUNK_PREP;
                    end else begin
                        word_offset <= word_offset + 2;
                        state <= PREP;
                    end
                end
                SCAN_END:
                    if (pass == TARGET) begin
                        image_crc <= ~crc;
                        digests_valid <= 1;
                        armed <= 1;
                        state <= ARM;
                    end else if ((^digest_q) === 1'bx || ~crc !== digest_q) begin
                        expected <= digest_q[15 : 0];
                        observed <= ~crc[15 : 0];
                        fail(13);
                    end else begin
                        cache_position <= 0;
                        cache_crc <= 32'hFFFFFFFF;
                        buffer_ff <= {256{1'b1}};
                        state <= CACHE_PREP;
                    end
                PROBE_REQ:
                    if (flash_ready) begin
                        flash_operation <= 0;
                        flash_address <= 0;
                        flash_request <= 1;
                        state <= PROBE_WAIT;
                    end
                PROBE_WAIT:
                    if (flash_done) begin
                        if (flash_error || flash_poisoned)
                            fail(flash_poisoned ? 8'd17 : 8'd9);
                        else
                            start_scan(TARGET);
                    end
                ARM:
                    if (confirm && digests_valid && !stopping) begin
                        armed <= 0;
                        sector_index <= 0;
                        sector_base <= 0;
                        state <= LOAD;
                    end
                LOAD: begin
                    pass <= SECTOR_LOAD;
                    chunk <= sector_base;
                    word_offset <= 0;
                    crc <= 32'hFFFFFFFF;
                    cache_crc <= 32'hFFFFFFFF;
                    state <= CHUNK_PREP;
                end
                // Let a changed cache address reach the synchronous read output
                // before CRC accumulation and all-FF page detection.
                CACHE_PREP:
                    state <= CACHE_SCAN;
                CACHE_SCAN: begin
                    cache_crc <= crc_word(cache_crc, cache_q);
                    if (cache_q !== 16'hFFFF)
                        buffer_ff[cache_position / 512] <= 0;
                    if (cache_position + 2 >= SECTOR_BYTES)
                        state <= CACHE_END;
                    else begin
                        cache_position <= cache_position + 2;
                        state <= CACHE_PREP;
                    end
                end
                CACHE_END:
                    if (!digests_valid || (^digest_q) === 1'bx || ~cache_crc !== digest_q) begin
                        expected <= digest_q[15 : 0];
                        observed <= ~cache_crc[15 : 0];
                        error_address <= sector_base[24 : 0];
                        fail(13);
                    end else if (final_pass) begin
                        position <= sector_base;
                        sector_crc <= 32'hFFFFFFFF;
                        read_kind <= VERIFY;
                        state <= READ_REQ;
                    end else begin
                        mutation_lock <= 1;
                        restore_required <= 1;
                        state <= ERASE_REQ;
                    end
                ERASE_REQ:
                    if (stopping)
                        fail(stop_code);
                    else if (flash_ready) begin
                        flash_operation <= 1;
                        flash_address <= sector_base[24 : 0];
                        flash_request <= 1;
                        state <= ERASE_WAIT;
                    end
                ERASE_WAIT:
                    if (flash_done) begin
                        if (flash_error || flash_poisoned) begin
                            error_address <= flash_address;
                            fail(flash_poisoned ? 8'd17 : 8'd14);
                        end else begin
                            erased_sectors <= erased_sectors + 1'b1;
                            position <= sector_base;
                            read_kind <= BLANK;
                            state <= READ_REQ;
                        end
                    end
                READ_REQ:
                    if (read_ready) begin
                        read_request <= 1;
                        state <= READ_WAIT;
                    end
                READ_WAIT:
                    if (read_done) begin
                        error_address <= read_address;
                        expected <= wanted;
                        observed <= read_q;
                        if (read_error)
                            fail(3);
                        else if (read_q !== wanted)
                            fail(8);
                        else begin
                            if (read_kind == VERIFY)
                                sector_crc <= next_read_crc;
                            if (position + 2 < sector_base + SECTOR_BYTES) begin
                                position <= position + 2;
                                state <= READ_REQ;
                            end else if (read_kind == BLANK) begin
                                program_position <= 0;
                                state <= PROGRAM_REQ;
                            end else if (~next_read_crc !== digest_q)
                                fail(13);
                            else begin
                                mutation_lock <= 0;
                                progress <= sector_base + SECTOR_BYTES;
                                if (stopping)
                                    fail(stop_code);
                                else if (sector_index + 1 < SECTORS)
                                    next_sector();
                                else if (!final_pass) begin
                                    final_pass <= 1;
                                    sector_index <= 0;
                                    sector_base <= 0;
                                    state <= LOAD;
                                end else begin
                                    restore_required <= 0;
                                    busy <= 0;
                                    done <= 1;
                                    state <= IDLE;
                                end
                            end
                        end
                    end
                PROGRAM_REQ:
                    if (program_position >= SECTOR_BYTES) begin
                        position <= sector_base;
                        sector_crc <= 32'hFFFFFFFF;
                        read_kind <= VERIFY;
                        state <= READ_REQ;
                    end else if (buffer_ff[program_position / 512])
                        program_position <= program_position + 512;
                    else if (flash_ready) begin
                        flash_operation <= 2;
                        flash_address <= sector_base + program_position;
                        flash_request <= 1;
                        state <= PROGRAM_WAIT;
                    end
                PROGRAM_WAIT:
                    if (flash_done) begin
                        if (flash_error || flash_poisoned) begin
                            error_address <= flash_address;
                            fail(flash_poisoned ? 8'd17 : 8'd15);
                        end else begin
                            programmed_buffers <= programmed_buffers + 1;
                            program_position <= program_position + 512;
                            state <= PROGRAM_REQ;
                        end
                    end
                default:
                    fail(10);
            endcase
            if (busy && (!cart_powered || power_lost)) begin
                if ((state != ERASE_WAIT && state != PROGRAM_WAIT) || flash_done) begin
                    fail(flash_poisoned ? 8'd17 : 8'd1);
                    flash_request <= 0;
                    read_request <= 0;
                    file_request <= 0;
                end
            end else if (busy && !mutation_lock && stopping && (state != FILE_WAIT || file_done))
            begin
                fail(stop_code);
                flash_request <= 0;
                read_request <= 0;
                file_request <= 0;
            end
        end
    end
endmodule
