// End-to-end controls/APF/RAM/controller/flash_ops/NOR test. Only the pin-level
// GBA transport is replaced by its transaction interface (tested separately).
// One physical-size sector starting at zero exercises the public write path.
`define POCKETFLASH_UTILITY 1
`timescale 1ns / 1ps
module tb_utility_system
    #(parameter FAIL_CLEANUP = 0, ABORT_OPEN = 0, CHECK_RESULT = 0, FAIL_FINALIZE = 0,
                ROM_POWER = 0, VERIFY_CANCEL = 0, GPIO_OVERLAY = 0, MULTI_SECTOR = 0);
    localparam IMAGE_BYTES = MULTI_SECTOR ? 393216 : 131072;
    localparam TARGET_BYTES = MULTI_SECTOR ? 131080 : (GPIO_OVERLAY ? 131072 : 512);
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg [31 : 0] address = 0, data = 0, keys = 0;
    reg wr = 0, rd = 0;
    wire [31 : 0] q;
    core_top dut(.clk_74a(clk),
                 .clk_74b(clk),
                 .bridge_addr(address),
                 .bridge_wr(wr),
                 .bridge_rd(rd),
                 .bridge_wr_data(data),
                 .bridge_rd_data(q),
                 .cont1_key(keys),
                 .cont2_key(32'b0),
                 .cont3_key(32'b0),
                 .cont4_key(32'b0),
                 .cont1_joy(32'b0),
                 .cont2_joy(32'b0),
                 .cont3_joy(32'b0),
                 .cont4_joy(32'b0),
                 .cont1_trig(16'b0),
                 .cont2_trig(16'b0),
                 .cont3_trig(16'b0),
                 .cont4_trig(16'b0),
                 .port_ir_rx(1'b0),
                 .cram0_wait(1'b0),
                 .cram1_wait(1'b0),
                 .vblank(1'b0),
                 .dbg_rx(1'b0),
                 .user2(1'b0),
                 .audio_adc(1'b0));
    defparam dut.public_mode.utility.ROM_BYTES = IMAGE_BYTES;
    defparam dut.public_mode.utility.SECTOR_BYTES = 131072;
    defparam dut.public_mode.utility.BUS_TICKS = 1;
    defparam dut.public_mode.utility.controls.HOLD_TICKS = 4;
    wire [7 : 0] save_value;
    assign dut.cart_tran_bank1 = !dut.cart_tran_bank1_dir ? save_value : 8'hzz;
    save_model saves(.clk(clk),
                     .cs2_n(dut.cart_tran_pin30),
                     .rd_n(dut.cart_tran_bank0[5]),
                     .wr_n(dut.cart_tran_bank0[6]),
                     .data_drive(dut.cart_tran_bank1_dir),
                     .address({dut.cart_tran_bank2, dut.cart_tran_bank3}),
                     .data_out(dut.cart_tran_bank1),
                     .data_in(save_value));
    always @(posedge clk)
        if (dut.public_mode.utility.save_owner && !dut.cart_tran_bank0[4])
            $fatal(1, "ROM selected during save operation");
    always @(posedge clk)
        if (!dut.public_mode.utility.save_owner && dut.cart_tran_pin30 === 1'b0)
            $fatal(1, "save selected during ROM operation");
    wire model_ready, model_done, model_error;
    wire [15 : 0] model_q;
    wire [31 : 0] mutations;
    wire [24 : 0] mapped_address = dut.public_mode.utility.rom_bus.address;

    nor_model #(.ARRAY_BASE(0),
                .SECTORS(MULTI_SECTOR ? 3 : 1),
                .ACK_DELAY(4),
                .STALL_PATTERN(1))
        model(.clk(clk),
              .reset_n(dut.reset_n),
              .request(dut.public_mode.utility.rom_bus.request),
              .write(dut.public_mode.utility.rom_bus.write),
              .address(mapped_address),
              .data(dut.public_mode.utility.rom_bus.write_data),
              .ready(model_ready),
              .done(model_done),
              .error(model_error),
              .q(model_q),
              .fault_status(16'b0),
              .busy_forever(1'b0),
              .stall_bus(1'b0),
              .mutations(mutations));
    defparam model.GPIO_OVERLAY = GPIO_OVERLAY;
    initial begin
        // Raster timing has its own benches. Freeze pixels to keep this long NOR
        // transaction simulation focused on the 74 MHz controller/bridge domain.
        force dut.pixel_clk = 0;
        force dut.pixel_clk90 = 0;
        force dut.public_mode.utility.rom_ready = model_ready;
        force dut.public_mode.utility.rom_done = model_done;
        force dut.public_mode.utility.rom_error = model_error;
        force dut.public_mode.utility.rom_q = model_q;
    end
    reg service_enabled = 0, servicing = 0, fail_export = 0;
    reg [31 : 0] exported[0 : IMAGE_BYTES / 4 - 1], saved[0 : 32767];
    reg [31 : 0] exported_record[0 : 3], save_record[0 : 3];
    reg [2 : 0] rom_exists = 0, record_exists = 0, save_exists = 0, save_record_exists = 0;
    integer slot, off, len, result, k;
    reg[31 : 0] sample;
    function [15 : 0] target
        (input integer word_index);
        begin
            if (GPIO_OVERLAY)
                target = word_index < 256 || word_index >= 65280
                             ? ((word_index * 2) ^ ((word_index * 2) >> 16) ^ 16'h5AA5)
                             : 16'hFFFF;
            else
                target = word_index < TARGET_BYTES / 2 ? (16'hA55A ^ (word_index * 3)) : 16'hFFFF;
        end
    endfunction
    function [31 : 0] bridge_words
        (input [15 : 0] a, b);
        bridge_words = {a[7 : 0], a[15 : 8], b[7 : 0], b[15 : 8]};
    endfunction
    task write_word
        (input [31 : 0] a,
         input [31 : 0] d);
        begin
            @(negedge clk);
            address = a;
            data = d;
            wr = 1;
            @(negedge clk);
            wr = 0;
            repeat (2) @(negedge clk)
                ;
        end
    endtask
    task read_word
        (input [31 : 0] a,
         output [31 : 0] value);
        begin
            @(negedge clk);
            address = a;
            rd = 0;
            @(negedge clk);
            rd = 1;
            @(negedge clk);
            rd = 0;
            value = q;
        end
    endtask
    task press
        (input integer bit_index);
        begin
            @(negedge clk);
            while (!dut.public_mode.utility.rom_ready || !dut.public_mode.utility.flash_ready)
                @(negedge clk)
                ;
            keys = 1 << bit_index;
            repeat (3) @(negedge clk)
                ;
            keys = 0;
            repeat (3) @(negedge clk)
                ;
        end
    endtask
    task approve;
        begin
            wait(dut.public_mode.utility.writer_armed);
            repeat (3) @(negedge clk)
                ;
            keys = 16'h10;
            repeat (5) @(negedge clk)
                ;
            keys = 0;
        end
    endtask
    // Emulate the APF host against actual bridge registers and actual transfer RAM.
    initial
        forever begin
            @(negedge clk);
            if (service_enabled && dut.commands.target_busy &&
                dut.commands.target_status[31 : 16] == 16'h636D) begin
                servicing = 1;
                slot = dut.commands.target_param[0];
                off = dut.commands.target_param[1];
                len = dut.commands.target_param[3];
                result = 0;
                case (dut.commands.target_status[15 : 0])
                    16'h0180:
                        for (k = 0; k < len / 4; k = k + 1) begin
                            case (slot)
                                4:
                                    sample = bridge_words(target(off / 2 + k * 2),
                                                          target(off / 2 + k * 2 + 1));
                                1:
                                    sample = exported[off / 4 + k];
                                2:
                                    sample = exported_record[k];
                                5:
                                    sample = saved[off / 4 + k];
                                6:
                                    sample = save_record[k];
                                default:
                                    $fatal(1, "legacy/unexpected input slot %d", slot);
                            endcase
                            write_word(32'h10000000 + k * 4, sample);
                        end
                    16'h0184: begin
                        if (MULTI_SECTOR && fail_export) begin
                            result = 2;
                            fail_export = 0;
                        end else
                            for (k = 0; k < len / 4; k = k + 1) begin
                                read_word(32'h10000000 + k * 4, sample);
                                case (slot)
                                    1:
                                        exported[off / 4 + k] = sample;
                                    2:
                                        exported_record[k] = sample;
                                    5:
                                        saved[off / 4 + k] = sample;
                                    6:
                                        save_record[k] = sample;
                                    default:
                                        $fatal(1, "unexpected output slot");
                                endcase
                            end
                    end
                    16'h0192: begin
                        if (ABORT_OPEN && slot == 5 && dut.utility_open_flags == 3) begin
                            if (ABORT_OPEN == 1)
                                write_word(32'hF8000000, 32'h434D0010);
                            else begin
                                write_word(32'hF8000020, 0);
                                write_word(32'hF8000000, 32'h434D00B1);
                            end
                        end
                        if (fail_export && !MULTI_SECTOR) begin
                            result = 2;
                            fail_export = 0;
                        end else if (dut.utility_open_flags == 0) begin
                            case (slot)
                                1:
                                    result = rom_exists[dut.utility_number - 1] ? 0 : 3;
                                2:
                                    result = record_exists[dut.utility_number - 1] ? 0 : 3;
                                5:
                                    result = save_exists[dut.utility_number - 1] ? 0 : 3;
                                6:
                                    result = save_record_exists[dut.utility_number - 1] ? 0 : 3;
                                default:
                                    $fatal(1, "unexpected probe slot");
                            endcase
                        end else
                            case (slot)
                                1:
                                    rom_exists[dut.utility_number - 1] = 1;
                                2:
                                    record_exists[dut.utility_number - 1] = 1;
                                5:
                                    save_exists[dut.utility_number - 1] = 1;
                                6: begin
                                    if (saves.bank || saves.id_mode ||
                                        dut.public_mode.utility.save_busy)
                                        $fatal(1, "save record created before bank-zero release");
                                    save_record_exists[dut.utility_number - 1] = 1;
                                end
                                default:
                                    $fatal(1, "unexpected create slot");
                            endcase
                    end
                    default:
                        $fatal(1, "unexpected APF operation");
                endcase
                write_word(32'hF8001000, 32'h6F6B0000 | result);
                servicing = 0;
            end
        end
    integer i;
    integer multi_stage = 0;
    function [7 : 0] save_byte
        (input integer a);
        save_byte = (a ^ (a >> 8) ^ ((a >> 16) * 8'hA5)) & 255;
    endfunction
    initial begin
        #1;
        for (i = 0; i < IMAGE_BYTES / 2; i = i + 1)
            model.memory[i] = 16'hDEAD;
        repeat (10) @(negedge clk)
            ;
        write_word(32'hF8001000, 32'h6F6B0000);
        wait(dut.file_ready);
        write_word(32'hF8000000, 32'h434D0011);
        write_word(32'hF8000020, 32'h00010000);
        write_word(32'hF8000000, 32'h434D00B1);
        write_word(32'hF8002000, 4);
        write_word(32'hF8002004, TARGET_BYTES);
        service_enabled = 1;
        if (MULTI_SECTOR) begin
            // Fail a real chunk write after creating its output; its marker must
            // remain absent, and retry must allocate a fresh filename.
            multi_stage = 1;
            fail_export = 1;
            press(4);
            wait(dut.utility_status == 255);
            if (record_exists || !rom_exists[0] || mutations)
                $fatal(1, "failed backup certified/mutated ROM");
            press(5);
            press(4);
            wait(dut.utility_status == 8 || dut.utility_status == 255);
            if (dut.utility_error || !record_exists[1] || dut.utility_number != 2)
                $fatal(1, "ROM backup retry did not skip partial file");
            press(5);
            press(1);
            press(1);
            press(4);
            press(4);
            approve();
            multi_stage = 2;
            wait(dut.utility_erases == 1);
            press(5);
            wait(dut.utility_status == 255);
            if (dut.utility_error != 6 || dut.utility_erases != 1 || dut.utility_rom_state != 1)
                $fatal(1, "partial ROM cancellation did not stop at verified sector");
            for (i = 0; i < 65536; i = i + 1)
                if (model.memory[i] !== target(i))
                    $fatal(1, "cancel left unfinished sector");
            for (i = 65536; i < IMAGE_BYTES / 2; i = i + 1)
                if (model.memory[i] !== 16'hDEAD)
                    $fatal(1, "cancel touched later sector");
            multi_stage = 3;
            model.memory[70000] = 16'h0012;
            write_word(32'hF8000000, 32'h434D0010);
            write_word(32'hF8000000, 32'h434D0011);
            // App reset returns the dashboard selection to Backup ROM.
            press(5);
            press(1);
            press(1);
            press(4);
            press(4);
            approve();
            wait(dut.utility_status == 9 || dut.utility_status == 255);
            multi_stage = 4;
            if (dut.utility_error || dut.utility_erases != 3 || dut.utility_buffers != 257 ||
                dut.utility_rom_state != 2)
                $fatal(1, "multi-sector recovery counters/state");
            for (i = 0; i < IMAGE_BYTES / 2; i = i + 1)
                if (model.memory[i] !== target(i))
                    $fatal(1, "recovery/padding mismatch %d", i);
            for (i = 0; i < 131072; i = i + 1)
                if (saves.memory[i] !== save_byte(i))
                    $fatal(1, "recovery touched save");
            press(5);
            press(0);
            press(0);
            press(4);
            wait(dut.utility_status == 8 || dut.utility_status == 255);
            if (dut.utility_error)
                $fatal(1, "recovered ROM export");
            for (i = 0; i < IMAGE_BYTES / 4; i = i + 1)
                if (exported[i] !== bridge_words(target(i * 2), target(i * 2 + 1)))
                    $fatal(1, "recovered export mismatch %d", i);
            $display({"PASS utility_multi: three sectors, partial-cart recovery after reset, 257 ",
                      "buffers, full export, file failure, unchanged saves"});
            $finish;
        end
        if (!ROM_POWER && !VERIFY_CANCEL && !GPIO_OVERLAY) begin
            press(1);
            press(4);
            if (FAIL_FINALIZE) begin
                wait(dut.public_mode.utility.a_completion_wait[1]);
                wait(dut.public_mode.utility.save_session.action == 5 &&
                     dut.public_mode.utility.save_bus_request);
                force dut.public_mode.utility.save_bus_error = 1;
                wait(dut.utility_status == 255);
                release dut.public_mode.utility.save_bus_error;
                if (save_record_exists || !dut.utility_poison)
                    $fatal(1, "failed final cleanup certified save");
                $display("PASS utility_save_finalize: no record before successful cleanup");
                $finish;
            end
            if (ABORT_OPEN) begin
                repeat (10000) @(negedge clk)
                    ;
                if (dut.utility_busy || dut.utility_status == 8 || dut.utility_status == 9 ||
                    !dut.utility_error || save_record_exists)
                    $fatal(1, "save abort during OPEN stranded owner: state=%d",
                           dut.public_mode.utility.state);
                if (ABORT_OPEN == 1 && (saves.bank || saves.id_mode))
                    $fatal(1, "reset did not clean save bank");
                $display({"PASS utility_save_abort: reset/power loss during pending OPEN ",
                          "terminates without marker"});
                $finish;
            end
            if (FAIL_CLEANUP) begin
                wait(dut.public_mode.utility.save_session.current_bank);
                press(5);
                wait(dut.public_mode.utility.save_session.action == 5 &&
                     dut.public_mode.utility.save_bus_request);
                force dut.public_mode.utility.save_bus_error = 1;
                wait(dut.utility_status == 255);
                release dut.public_mode.utility.save_bus_error;
                if (!dut.utility_poison || dut.utility_error != 17)
                    $fatal(1, "cleanup poison lost");
                press(5);
                press(1);
                press(4);
                if (dut.utility_ack || mutations || dut.utility_busy)
                    $fatal(1, "poison did not block ROM access");
                write_word(32'hF8000000, 32'h434D0010);
                write_word(32'hF8000000, 32'h434D0011);
                if (!dut.utility_poison)
                    $fatal(1, "app reset cleared cleanup poison");
                $display({"PASS utility_cleanup: failed save cleanup blocks ROM owner across app ",
                          "reset"});
                $finish;
            end
            wait(dut.utility_status == 8 || dut.utility_status == 255);
            if (dut.utility_error || dut.utility_status != 8 || saves.bank || saves.id_mode)
                $fatal(1, "save capture/cleanup %d", dut.utility_error);
            for (i = 0; i < 32768; i = i + 1)
                if (saved[i] !== {save_byte(i * 4), save_byte(i * 4 + 1), save_byte(i * 4 + 2),
                                  save_byte(i * 4 + 3)})
                    $fatal(1, "save byte order/address %d", i);
            if (save_record[0] !== 32'h50465331 || save_record[1] !== 32'h00000200 ||
                save_record[3] !== 32'h03000000)
                $fatal(1, "save record");
            repeat (3) @(negedge clk)
                ;
            if (dut.utility_progress != 131072 ||
                dut.utility_crc !== {save_record[2][7 : 0], save_record[2][15 : 8],
                                     save_record[2][23 : 16], save_record[2][31 : 24]})
                $fatal(1, "terminal backup evidence lost");
            if (CHECK_RESULT) begin
                $display("PASS utility_result: terminal backup progress/CRC retained");
                $finish;
            end
            $display("utility save backup passed");
            $fflush();
            press(5);
            press(0);
            press(4);
            wait(dut.utility_status == 8 || dut.utility_status == 255);
            if (dut.utility_error || dut.utility_status != 8)
                $fatal(1, "ROM backup");
        end
        press(5);
        press(1);
        press(1);
        press(4);
        if (!dut.utility_ack || mutations)
            $fatal(1, "acknowledgement bypassed");
        press(4);
        approve();
        wait(dut.utility_lock);
        if (ROM_POWER) begin
            wait(dut.public_mode.utility.flash.op == 2 &&
                 dut.public_mode.utility.flash.index == 100);
            write_word(32'hF8000020, 0);
            write_word(32'hF8000000, 32'h434D00B1);
            repeat (5) @(negedge clk)
                ;
            if (dut.cart_tran_bank0[6 : 4] !== 3'b111 || !dut.utility_poison)
                $fatal(1, "ROM power loss did not fence transport");
            write_word(32'hF8000020, 32'h10000);
            write_word(32'hF8000000, 32'h434D00B1);
            repeat (1000) begin
                @(negedge clk);
                if (dut.public_mode.utility.rom_bus.request ||
                    dut.cart_tran_bank0[6 : 4] !== 3'b111)
                    $fatal(1, "ROM writes continued after power returned");
            end
            wait(dut.utility_status == 255);
            write_word(32'hF8000000, 32'h434D0010);
            write_word(32'hF8000000, 32'h434D0011);
            if (!dut.utility_poison || dut.utility_rom_state != 1)
                $fatal(1, "ROM power poison/recovery state lost on app reset");
            $display({"PASS utility_rom_power: buffer interrupted before commit, pins fenced ",
                      "across power return/reset"});
            $finish;
        end
        write_word(32'hF8000000, 32'h434D0010);
        if (!dut.reset_n)
            $fatal(1, "reset interrupted mutation");
        wait(dut.utility_status == 9 || dut.utility_status == 255);
        if (dut.utility_error || dut.utility_status != 9 ||
            dut.public_mode.utility.writer_uncertain || dut.utility_rom_state != 2)
            $fatal(1, "public flash %d", dut.utility_error);
        if (mutations != (GPIO_OVERLAY ? 3 : 2) || dut.utility_buffers != (GPIO_OVERLAY ? 2 : 1) ||
            dut.utility_erases != 1)
            $fatal(1, "buffer count");
        for (i = 0; i < IMAGE_BYTES / 2; i = i + 1)
            if (model.memory[i] !== target(i))
                $fatal(1, "target mismatch %d", i);
        for (i = 0; i < 131072; i = i + 1)
            if (saves.memory[i] !== save_byte(i))
                $fatal(1, "save changed during ROM flash");
        if (GPIO_OVERLAY) begin
            $display({"PASS utility_gpio: sparse first/last buffers, strict sector/final ",
                      "verification, unchanged saves"});
            $finish;
        end
        $display("utility source-only flash passed");
        $fflush();
        press(5);
        press(1);
        press(4);
        if (VERIFY_CANCEL) begin
            wait(dut.public_mode.utility.apps[2].app.state == 16 &&
                 dut.public_mode.utility.apps[2].app.read_address == 131070 &&
                 dut.public_mode.utility.rom_done);
            @(negedge clk);
            keys = 16'h20;
            @(negedge clk);
            keys = 0;
        end
        wait(dut.utility_status == 9 || dut.utility_status == 255);
        if (VERIFY_CANCEL) begin
            if (dut.utility_status != 255 || dut.utility_error != 6)
                $fatal(1, "final-cycle cancel reported verified");
            $display("PASS utility_verify_cancel: physical B wins last comparison cycle");
            $finish;
        end
        if (dut.utility_error || dut.utility_status != 9)
            $fatal(1, "ROM verify %d", dut.utility_error);
        press(5);
        press(0);
        press(0);
        press(4);
        wait(dut.public_mode.utility.save_session.current_bank);
        press(5);
        wait(dut.utility_status == 255);
        if (dut.utility_error != 6 || saves.bank || saves.id_mode || save_record_exists[1])
            $fatal(1, "save cancel/marker cleanup");
        for (i = 0; i < 131072; i = i + 1)
            if (saves.memory[i] !== save_byte(i))
                $fatal(1, "save changed");
        $display({"PASS utility_system: actual APF/RAM/flash/cache/save pins, backups, ",
                  "source-only flash, verify, cancel and unchanged saves"});
        $finish;
    end
    initial begin
        #900000000;
        $fatal(1, "utility timeout stage=%d selection=%d state=%d op=%d status=%d appstate=%d",
               multi_stage, dut.utility_selection, dut.public_mode.utility.state,
               dut.public_mode.utility.operation, dut.utility_status,
               dut.public_mode.utility.apps[1].app.state);
    end
endmodule
