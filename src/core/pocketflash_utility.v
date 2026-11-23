// Public utility owns file channel, transfer RAM and cartridge pins exclusively.
`timescale 1ns / 1ps
`default_nettype none
module pocketflash_utility
    #(parameter ROM_BYTES = 33554432, SECTOR_BYTES = 131072, CLOCK_HZ = 74250000,
      parameter BUS_TICKS = 75, HOLD_TICKS = 148500000)
    (input wire clk, core_reset_n, app_reset_n, in_menu, cart_powered,
     input wire [15 : 0] keys,
     input wire [31 : 0] target_size,
     input wire target_changed, file_poisoned, file_ready, file_done,
     input wire [15 : 0] file_result, ram_q, ad_in,
     input wire [7 : 0] save_data_in,
     output wire busy, mutation_lock, poisoned,
     output wire file_request,
     output wire [15 : 0] file_command, file_slot, ram_offset, ram_data, ad_out,
     output wire [31 : 0] file_offset, file_address, file_length, open_flags, open_size,
     output wire ram_wr, ad_drive, high_drive, cs_n, rd_n, wr_n, cs2_n,
     output wire [7 : 0] high_out,
     output wire [2 : 0] selection,
     output wire acknowledge, help, details, header_warning,
     output reg [7 : 0] status, error_code,
     output wire [31 : 0] progress, image_crc, programmed_buffers,
     output reg [31 : 0] seconds,
     output wire [8 : 0] erased_sectors,
     output wire [24 : 0] error_address,
     output wire [15 : 0] expected, observed,
     output wire [13 : 0] output_number,
     output wire [15 : 0] output_digits,
     output reg [1 : 0] rom_state,
     output wire error_is_flash,
     output wire [15 : 0] rom_manufacturer, rom_device, raw_flash_status,
     output wire completion_known, read_mode,
     output wire output_save, report_path,
     output wire [7 : 0] phase,
     output wire [15 : 0] save_identity);
    localparam DASH = 0, ALLOC = 1, SAVE_OPEN = 2, START_APP = 3, RUN = 4, CLEAN = 5, RESULT = 6;
    reg [2 : 0] state, operation;
    reg allocator_start, save_start, save_close, writer_start;
    reg [15 : 0] app_keys;
    reg stop_pending, result_ok, save_finalizing, rom_poisoned, target_stale;
    reg [31 : 0] selected_size;
    // Also selects normal flash counters in the renderer; this operation tag
    // stays valid with no error present and through the result screen.
    assign error_is_flash = operation == 2;
    wire rom_abort = rom_poisoned || cart_powered !== 1'b1;
    reg [31 : 0] ticker;
    wire control_start, control_confirm, control_cancel;
    wire writer_busy, writer_armed, writer_done, writer_uncertain;
    wire [7 : 0] writer_error, writer_phase;
    wire [31 : 0] writer_progress, writer_crc;
    wire [24 : 0] writer_error_address;
    wire [15 : 0] writer_expected, writer_observed;
    wire writer_header_valid;
    assign header_warning = operation == 2 && writer_armed && !writer_header_valid;
    wire flash_ready, flash_done, flash_error, flash_poisoned;
    wire rom_ready, rom_done, rom_error;
    wire [15 : 0] rom_q;
    wire save_busy, save_ready, save_done, save_error, save_poisoned, save_word_done,
         save_word_error;
    wire [15 : 0] save_q;
    wire alloc_done, alloc_error, alloc_report, alloc_request;
    wire [7 : 0] alloc_error_code;
    wire [15 : 0] alloc_slot;
    wire save_owner = operation == 1 &&
                      (state == SAVE_OPEN || state == START_APP || state == RUN || state == CLEAN);
    wire stop = stop_pending || control_cancel || keys[5] || !app_reset_n || in_menu;
    wire invalid_target = target_stale || target_changed || target_size != selected_size;
    assign busy = state != DASH && state != RESULT;
    assign poisoned = file_poisoned || flash_poisoned || save_poisoned || rom_poisoned;
    assign output_save = operation == 1;
    utility_controls #(.HOLD_TICKS(HOLD_TICKS))
        controls(.clk(clk),
                 .reset_n(core_reset_n && app_reset_n),
                 .in_menu(in_menu),
                 .idle_allowed(state == DASH && file_ready && rom_ready && flash_ready &&
                               !save_busy),
                 .busy(busy),
                 .armed(writer_armed && operation == 2),
                 .poisoned(poisoned),
                 .keys(keys),
                 .selection(selection),
                 .acknowledge(acknowledge),
                 .help(help),
                 .details(details),
                 .start(control_start),
                 .confirm(control_confirm),
                 .cancel(control_cancel));
    backup_allocator allocator(.clk(clk),
                               .reset_n(core_reset_n),
                               .start(allocator_start),
                               .is_save(operation == 1),
                               .cancel(stop),
                               .busy(),
                               .done(alloc_done),
                               .error(alloc_error),
                               .error_code(alloc_error_code),
                               .number(output_number),
                               .digits(output_digits),
                               .report_path(alloc_report),
                               .file_request(alloc_request),
                               .file_slot(alloc_slot),
                               .file_ready(file_ready && state == ALLOC),
                               .file_done(file_done && state == ALLOC),
                               .file_result(file_result));
    wire [1 : 0] app_index = operation == 3 ? 2 : operation[1 : 0];
    wire [2 : 0] a_busy, a_report, a_ram_wr, a_file_request, a_read_request, a_completion_wait;
    wire [7 : 0] a_status[0 : 2], a_error[0 : 2];
    wire [31 : 0] a_progress[0 : 2], a_crc[0 : 2], a_open_flags[0 : 2], a_open_size[0 : 2];
    wire [24 : 0] a_error_address[0 : 2], a_read_address[0 : 2];
    wire [15 : 0] a_expected[0 : 2], a_observed[0 : 2], a_command[0 : 2], a_slot[0 : 2],
                  a_ram_offset[0 : 2], a_ram_data[0 : 2];
    wire [31 : 0] a_offset[0 : 2], a_address[0 : 2], a_length[0 : 2];
    assign progress = operation == 2 ? writer_progress : a_progress[app_index];
    assign image_crc = operation == 2 ? writer_crc : ~a_crc[app_index];
    assign phase = operation == 2 ? writer_phase : {2'b0, state, 3'b0};
    assign error_address = operation == 2 ? writer_error_address : a_error_address[app_index];
    assign expected = operation == 2 ? writer_expected : a_expected[app_index];
    assign observed = operation == 2 ? writer_observed : a_observed[app_index];
    genvar n;
    generate
        for (n = 0; n < 3; n = n + 1) begin : apps
            pocketflash_app #(.VERIFY_ONLY(n == 2),
                              .INPUT_SLOT(4),
                              .ROM_BYTES(n == 1 ? 131072 : ROM_BYTES),
                              .CLOCK_HZ(CLOCK_HZ),
                              .BACKUP_SLOT(n == 1 ? 5 : 1),
                              .RECORD_SLOT(n == 1 ? 6 : 2),
                              .RECORD_MAGIC(n == 1 ? 32'h31534650 : 32'h31524650),
                              .WAIT_COMPLETION(n == 1))
                app(.clk(clk),
                    .reset_n(
                        core_reset_n && app_index == n &&
                        (state == START_APP || state == RUN || state == CLEAN || state == RESULT)),
                    .in_menu(1'b0),
                    .cart_powered(cart_powered),
                    .keys(state == RUN && stop ? 16'h20 : app_keys),
                    .input_size(target_size),
                    .input_changed(target_changed),
                    .busy(a_busy[n]),

                    .status(a_status[n]),
                    .error_code(a_error[n]),
                    .progress(a_progress[n]),
                    .seconds(),
                    .error_address(a_error_address[n]),
                    .expected(a_expected[n]),
                    .observed(a_observed[n]),

                    .crc(a_crc[n]),
                    .sd_crc(),
                    .open_flags(a_open_flags[n]),
                    .open_size(a_open_size[n]),
                    .report_path(a_report[n]),

                    .file_request(a_file_request[n]),
                    .file_command(a_command[n]),
                    .file_slot(a_slot[n]),
                    .file_offset(a_offset[n]),
                    .file_address(a_address[n]),
                    .file_length(a_length[n]),
                    .file_ready(file_ready && state == RUN),
                    .file_done(file_done && state == RUN),
                    .file_result(file_result),
                    .ram_wr(a_ram_wr[n]),
                    .ram_offset(a_ram_offset[n]),
                    .ram_data(a_ram_data[n]),
                    .ram_q(ram_q),
                    .read_request(a_read_request[n]),
                    .read_address(a_read_address[n]),
                    .read_ready(n == 1 ? save_ready : rom_ready && flash_ready),
                    .read_done(n == 1 ? save_word_done : rom_done || rom_abort),
                    .read_error(n == 1 ? save_word_error : rom_error || rom_abort),
                    .read_q(n == 1 ? save_q : rom_q),

                    .completion_wait(a_completion_wait[n]),
                    .completion_ready(n != 1 || (save_finalizing && !save_busy)),
                    .completion_error(n == 1 && (save_error || save_poisoned)),
                    .source_failed(n == 1 && (save_poisoned || save_error ||
                                              (!save_busy && !save_finalizing))));
        end
    endgenerate
    wire writer_file_request, writer_read_request, writer_flash_request;
    wire [15 : 0] writer_command, writer_slot, writer_ram_offset, buffer_offset, buffer_q;
    wire [31 : 0] writer_offset, writer_address, writer_length;
    wire [24 : 0] writer_read_address, writer_flash_address;
    wire [1 : 0] writer_flash_operation;
    rom_writer #(.ROM_BYTES(ROM_BYTES),
                 .SECTOR_BYTES(SECTOR_BYTES))
        writer(.clk(clk),
               .reset_n(core_reset_n),
               .in_menu(in_menu),
               .cart_powered(cart_powered),
               .start_write(writer_start),
               .confirm(control_confirm),
               .cancel(stop),
               .input_changed(target_changed),
               .target_size(target_size),
               .busy(writer_busy),
               .armed(writer_armed),
               .mutation_lock(mutation_lock),
               .restore_required(writer_uncertain),
               .done(writer_done),
               .error_code(writer_error),
               .phase(writer_phase),
               .progress(writer_progress),
               .image_crc(writer_crc),
               .programmed_buffers(programmed_buffers),
               .erased_sectors(erased_sectors),
               .header_valid(writer_header_valid),
               .error_address(writer_error_address),
               .expected(writer_expected),
               .observed(writer_observed),
               .file_request(writer_file_request),
               .file_command(writer_command),
               .file_slot(writer_slot),
               .file_offset(writer_offset),
               .file_address(writer_address),
               .file_length(writer_length),
               .file_ready(file_ready && state == RUN && operation == 2),
               .file_done(file_done && state == RUN && operation == 2),
               .file_result(file_result),
               .file_poisoned(file_poisoned),
               .ram_offset(writer_ram_offset),
               .ram_q(ram_q),
               .read_request(writer_read_request),
               .read_address(writer_read_address),
               .read_ready(rom_ready && flash_ready),
               .read_done((rom_done || rom_abort) && flash_ready),
               .read_error(rom_error || rom_abort),
               .read_q(rom_q),
               .flash_request(writer_flash_request),
               .flash_operation(writer_flash_operation),
               .flash_address(writer_flash_address),
               .flash_ready(flash_ready),
               .flash_done(flash_done),
               .flash_error(flash_error),
               .flash_poisoned(flash_poisoned),
               .buffer_offset(buffer_offset),
               .buffer_q(buffer_q));
    wire flash_bus_request, flash_bus_write;
    wire [24 : 0] flash_bus_address;
    wire [15 : 0] flash_bus_data;
    // On power loss the pin request is fenced below. Synthetic ready/done/error
    // let an outstanding operation terminate without another physical bus beat.
    // rom_poisoned still blocks every subsequent cartridge operation.
    flash_ops #(.ALLOW_QUERY(1),
                .ALLOW_PROGRAM(1),
                .CLEAR_GPIO(1),
                .WRITE_BEGIN(0),
                .WRITE_END(25'h1FFFFFF))
        flash(.clk(clk),
              .reset_n(core_reset_n),
              .request(writer_flash_request && operation == 2 && state == RUN),
              .operation(writer_flash_operation),
              .address(writer_flash_address),
              .ready(flash_ready),
              .done(flash_done),
              .error(flash_error),
              .poisoned(flash_poisoned),
              .identified(),
              .swapped(),
              .manufacturer(rom_manufacturer),
              .device(rom_device),
              .stage(),
              .raw_status(raw_flash_status),
              .completion_known(completion_known),
              .read_mode(read_mode),
              .bus_request(flash_bus_request),
              .bus_write(flash_bus_write),
              .bus_address(flash_bus_address),
              .bus_data(flash_bus_data),
              .bus_ready(rom_ready || rom_abort),
              .bus_done(rom_done || rom_abort),
              .bus_error(rom_error || rom_abort),
              .bus_q(rom_q),
              .buffer_offset(buffer_offset),
              .buffer_q(buffer_q));
    wire [15 : 0] rom_ad;
    wire rom_drive, rom_cs, rom_rd, rom_wr;
    wire [7 : 0] rom_high;
    gba_bus #(.ALLOW_WRITES(1),
              .TICKS(BUS_TICKS))
        rom_bus(.clk(clk),
                .reset_n(core_reset_n && !rom_abort),
                .request(!rom_abort && !save_owner &&
                         (flash_ready
                              ? (operation == 2 ? writer_read_request : a_read_request[app_index])
                              : flash_bus_request)),
                .write(!flash_ready && flash_bus_write),
                .address(flash_ready
                             ? (operation == 2 ? writer_read_address : a_read_address[app_index])
                             : flash_bus_address),
                .write_data(flash_bus_data),
                .ready(rom_ready),
                .done(rom_done),
                .error(rom_error),
                .read_data(rom_q),
                .ad_in(ad_in),
                .ad_out(rom_ad),
                .ad_drive(rom_drive),
                .a_high(rom_high),
                .cs_n(rom_cs),
                .rd_n(rom_rd),
                .wr_n(rom_wr));
    wire save_bus_request, save_bus_ready, save_bus_done, save_bus_error, save_bus_poisoned;
    wire [1 : 0] save_operation;
    wire [15 : 0] save_address, save_bus_q, save_address_out;
    wire save_bank, save_drive, save_cs, save_rd, save_wr;
    wire [7 : 0] save_out;
    save_reader save_session(.clk(clk),
                             .core_reset_n(core_reset_n),
                             .app_reset_n(app_reset_n),
                             .cart_powered(cart_powered),
                             .start(save_start),
                             .close(save_close),
                             .word_request(a_read_request[1] && save_owner),
                             .address(a_read_address[1][16 : 0]),
                             .word_ready(save_ready),
                             .busy(save_busy),
                             .word_done(save_word_done),
                             .word_error(save_word_error),
                             .done(save_done),
                             .error(save_error),
                             .poisoned(save_poisoned),
                             .word_q(save_q),
                             .identity(save_identity),
                             .bus_request(save_bus_request),
                             .bus_operation(save_operation),
                             .bus_address(save_address),
                             .bus_bank(save_bank),
                             .bus_ready(save_bus_ready),
                             .bus_done(save_bus_done),
                             .bus_error(save_bus_error),
                             .bus_poisoned(save_bus_poisoned),
                             .bus_q(save_bus_q));
    save_bus #(.TICKS(BUS_TICKS))
        save_interface(.clk(clk),
                       .reset_n(core_reset_n),
                       .cart_powered(cart_powered),
                       .request(save_bus_request),
                       .operation(save_operation),
                       .address(save_address),
                       .bank(save_bank),
                       .ready(save_bus_ready),
                       .done(save_bus_done),
                       .error(save_bus_error),
                       .poisoned(save_bus_poisoned),
                       .q(save_bus_q),
                       .address_out(save_address_out),
                       .data_out(save_out),
                       .data_in(save_data_in),
                       .data_drive(save_drive),
                       .cs2_n(save_cs),
                       .rd_n(save_rd),
                       .wr_n(save_wr));
    assign ad_out = save_owner ? save_address_out : rom_ad;
    assign ad_drive = cart_powered !== 1'b1 || rom_poisoned ? 1'b0 : save_owner ? 1'b1 : rom_drive;
    assign high_out = save_owner ? save_out : rom_high;
    assign high_drive = cart_powered !== 1'b1 || rom_poisoned ? 1'b0
                        : save_owner                          ? save_drive
                                                              : 1'b1;
    assign cs_n = cart_powered !== 1'b1 || rom_poisoned ? 1'b1 : save_owner ? 1'b1 : rom_cs;
    assign cs2_n = cart_powered !== 1'b1 || rom_poisoned ? 1'b1 : save_owner ? save_cs : 1'b1;
    assign rd_n = cart_powered !== 1'b1 || rom_poisoned ? 1'b1 : save_owner ? save_rd : rom_rd;
    assign wr_n = cart_powered !== 1'b1 || rom_poisoned ? 1'b1 : save_owner ? save_wr : rom_wr;
    assign file_request = state == ALLOC ? alloc_request
                          : state == RUN
                              ? (operation == 2 ? writer_file_request : a_file_request[app_index])
                              : 1'b0;
    assign file_command = state == ALLOC   ? 16'h0192
                          : operation == 2 ? writer_command
                                           : a_command[app_index];
    assign file_slot = state == ALLOC   ? alloc_slot
                       : operation == 2 ? writer_slot
                                        : a_slot[app_index];
    assign file_offset = state == ALLOC   ? 32'h10010000
                         : operation == 2 ? writer_offset
                                          : a_offset[app_index];
    assign file_address = state == ALLOC   ? 0
                          : operation == 2 ? writer_address
                                           : a_address[app_index];
    assign file_length = state == ALLOC ? 0 : operation == 2 ? writer_length : a_length[app_index];
    assign open_flags = state == ALLOC ? 0 : a_open_flags[app_index];
    assign open_size = state == ALLOC ? 0 : a_open_size[app_index];
    assign report_path = state == ALLOC ? alloc_report : a_report[app_index];
    assign ram_offset = operation == 2 ? writer_ram_offset : a_ram_offset[app_index];
    assign ram_wr = state == RUN && operation != 2 && a_ram_wr[app_index];
    assign ram_data = a_ram_data[app_index];
    always @(posedge clk) begin
        allocator_start <= 0;
        save_start <= 0;
        save_close <= 0;
        writer_start <= 0;
        app_keys <= 0;
        if (!core_reset_n) begin
            state <= DASH;
            operation <= 0;
            rom_state <= 0;
            rom_poisoned <= 0;
            save_finalizing <= 0;
            selected_size <= 0;
            target_stale <= 0;
            status <= 0;
            error_code <= 0;
            stop_pending <= 0;
            result_ok <= 0;
            seconds <= 0;
            ticker <= 0;
        end else begin
            if (target_changed && rom_state == 2)
                rom_state <= 0;
            if (state == RUN && operation == 2 && writer_flash_request &&
                writer_flash_operation != 0)
                rom_state <= 1;
            if (busy && !save_owner && cart_powered !== 1'b1)
                rom_poisoned <= 1;
            if (busy && operation >= 2 && (target_changed || target_size != selected_size))
                target_stale <= 1;
            if (busy) begin
                if (ticker == CLOCK_HZ - 1) begin
                    ticker <= 0;
                    seconds <= seconds + 1'b1;
                end else
                    ticker <= ticker + 1'b1;
                if (keys[5] || control_cancel || !app_reset_n || in_menu)
                    stop_pending <= 1;
            end
            case (state)
                DASH:
                    if (control_start && !poisoned) begin
                        operation <= selection;
                        selected_size <= target_size;
                        target_stale <= 0;
                        save_finalizing <= 0;
                        error_code <= 0;
                        stop_pending <= 0;
                        seconds <= 0;
                        ticker <= 0;
                        result_ok <= 0;
                        if (cart_powered !== 1'b1) begin
                            error_code <= 1;
                            status <= 255;
                            state <= RESULT;
                        end else if (selection < 2) begin
                            allocator_start <= 1;
                            state <= ALLOC;
                            status <= 1;
                        end else if (selection == 2) begin
                            writer_start <= 1;
                            state <= RUN;
                            status <= 3;
                        end else begin
                            state <= START_APP;
                            status <= 6;
                        end
                    end
                ALLOC:
                    if (alloc_done) begin
                        if (alloc_error || stop || cart_powered !== 1'b1) begin
                            error_code <= alloc_error ? alloc_error_code : 6;
                            status <= 255;
                            state <= RESULT;
                        end else if (operation == 1) begin
                            save_start <= 1;
                            state <= SAVE_OPEN;
                            status <= 2;
                        end else begin
                            state <= START_APP;
                            status <= 2;
                        end
                    end
                SAVE_OPEN:
                    if (stop) begin
                        save_close <= 1;
                        error_code <= 6;
                        state <= CLEAN;
                    end else if (save_ready)
                        state <= START_APP;
                    else if (save_done) begin
                        error_code <= 17;
                        status <= 255;
                        state <= RESULT;
                    end
                START_APP: begin
                    app_keys <= 16'h10;
                    state <= RUN;
                end
                RUN: begin
                    if (stop)
                        app_keys <= 16'h20;
                    if (operation == 2) begin
                        status <= writer_armed                                 ? 4
                                  : mutation_lock                              ? 5
                                  : erased_sectors == ROM_BYTES / SECTOR_BYTES ? 6
                                                                               : 3;
                        if (writer_done) begin
                            result_ok <=
                                writer_error == 0 && !stop && !invalid_target && !rom_abort;
                            error_code <= invalid_target ? 7
                                          : stop         ? 6
                                          : rom_abort    ? 17
                                                         : writer_error;
                            state <= CLEAN;
                        end
                    end else begin
                        if (operation == 1 && a_completion_wait[1] && !save_finalizing) begin
                            save_close <= 1;
                            save_finalizing <= 1;
                        end
                        if (a_status[app_index] == 7)
                            status <= 6;
                        if (!a_busy[app_index] &&
                            (a_status[app_index] == 5 || a_status[app_index] == 255)) begin
                            result_ok <=
                                a_status[app_index] == 5 &&
                                (operation < 2 || (!stop && !invalid_target && !rom_abort));
                            if (operation == 3 && a_error[app_index] == 8 && rom_state == 2)
                                rom_state <= 0;
                            error_code <= operation >= 2 && invalid_target ? 7
                                          : operation >= 2 && stop         ? 6
                                                                           : a_error[app_index];
                            state <= CLEAN;
                            if (operation == 1)
                                save_close <= 1;
                        end
                    end
                end
                CLEAN: begin
                    status <= 7;
                    if (operation == 1 && save_busy && !save_finalizing)
                        save_close <= 1;
                    if (operation == 1 ? !save_busy
                                       : rom_ready && flash_ready && (file_ready || file_poisoned))
                    begin
                        status <=
                            result_ok &&
                                    (operation < 2 || (!stop && !invalid_target && !rom_abort)) &&
                                    (operation != 1 || !save_error) && !poisoned
                                ? (operation < 2 ? 8 : 9)
                                : 255;
                        if (operation >= 2 && (stop || invalid_target))
                            error_code <= invalid_target ? 7 : 6;
                        if (save_poisoned || rom_poisoned)
                            error_code <= 17;
                        if (operation >= 2 && result_ok && !stop && !invalid_target && !rom_abort &&
                            !poisoned)
                            rom_state <= 2;
                        state <= RESULT;
                    end
                end
                RESULT:
                    if (!keys[4] && (keys[5] || !app_reset_n)) begin
                        state <= DASH;
                        status <= 0;
                    end
                default: begin
                    status <= 255;
                    error_code <= 10;
                    state <= RESULT;
                end
            endcase
        end
    end
endmodule
