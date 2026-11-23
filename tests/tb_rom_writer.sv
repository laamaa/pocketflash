`timescale 1ns / 1ps
module tb_rom_writer
    #(parameter COUNT_TEST = 0);
    localparam BYTES = COUNT_TEST ? 131072 : 1536;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset_n = 0, start_write = 0, confirm = 0, cancel = 0, in_menu = 0, cart_powered = 1;
    reg input_changed = 0;
    reg [31 : 0] target_size = COUNT_TEST ? BYTES : 700;
    wire busy, armed, mutation_lock, restore_required, done;
    wire [7 : 0] error_code, phase;
    wire [31 : 0] progress, image_crc, programmed_buffers;
    wire [8 : 0] erased_sectors;
    wire header_valid;
    wire [24 : 0] error_address;
    wire [15 : 0] expected, observed;
    wire file_request;
    wire [15 : 0] file_command, file_slot, ram_offset;
    wire [31 : 0] file_offset, file_address, file_length;
    reg file_ready = 1, file_done = 0, file_poisoned = 0;
    reg [15 : 0] file_result = 0, ram_q = 0;
    wire read_request;
    wire [24 : 0] read_address;
    reg read_ready = 1, read_done = 0, read_error = 0;
    reg [15 : 0] read_q = 0;
    wire flash_request;
    wire [1 : 0] flash_operation;
    wire [24 : 0] flash_address;
    reg flash_ready = 1, flash_done = 0, flash_error = 0, flash_poisoned = 0;
    reg [15 : 0] buffer_offset = 0;
    wire [15 : 0] buffer_q;
    rom_writer #(.ROM_BYTES(BYTES),
                 .SECTOR_BYTES(512))
        dut(.*);
    reg [15 : 0] transfer[0 : 32767], cart[0 : BYTES / 2 - 1];
    reg unknown_target = 0;
    reg corrupt_target = 0, sd_error = 0, fail_erase = 0, bad_blank = 0, bad_program = 0,
        programming = 0;
    integer i, j, mutations = 0, index = 0, base = 0, before_count;
    function [15 : 0] original
        (input integer n);
        original = 16'h1234 ^ n;
    endfunction
    function [15 : 0] target
        (input integer n);
        target = COUNT_TEST || n < 350 ? 16'hA55A ^ (n * 3) : 16'hFFFF;
    endfunction
    always @(posedge clk) begin
        ram_q <= transfer[ram_offset >> 1];
        file_done <= 0;
        read_done <= 0;
        flash_done <= 0;
        if (file_request) begin
            if (file_slot != 4)
                $fatal(1, "public mode requested legacy source");
            if (mutation_lock)
                $fatal(1, "SD access during mutation");
            if (file_command != 16'h180 || file_length == 0 || file_length > 65536)
                $fatal(1, "bad source read");
            for (j = 0; j < file_length / 2; j = j + 1)
                transfer[j] <= unknown_target && file_offset == 0 && j == 5 ? 16'hxxxx
                               : corrupt_target                             ? 16'h0
                                                : target(file_offset / 2 + j);
            file_result <= sd_error ? 16'd2 : 0;
            file_done <= 1;
        end
        if (read_request) begin
            read_q <= cart[read_address >> 1];
            read_done <= 1;
        end
        if (flash_request) begin
            if (flash_operation == 0) begin
                flash_error <= 0;
                flash_done <= 1;
            end else begin
                if (!mutation_lock)
                    $fatal(1, "write without mutation lock");
                mutations <= mutations + 1;
                if (flash_operation == 1) begin
                    if (flash_address % 512 || flash_address >= BYTES)
                        $fatal(1, "erase bounds");
                    if (!fail_erase)
                        for (j = 0; j < 256; j = j + 1)
                            cart[flash_address / 2 + j] <= 16'hFFFF;
                    if (bad_blank)
                        cart[flash_address / 2 + 7] <= 16'hBAD0;
                    flash_error <= fail_erase;
                    flash_done <= 1;
                end else begin
                    programming <= 1;
                    base <= flash_address / 2;
                    index <= 0;
                    buffer_offset <= 0;
                    flash_ready <= 0;
                    flash_error <= 0;
                end
            end
        end
        if (programming) begin
            index <= index + 1;
            if (index % 3 == 2) begin
                if ((cart[base + index / 3] & buffer_q) !== buffer_q)
                    $fatal(1, "program without erase");
                cart[base + index / 3] <= buffer_q;
                buffer_offset <= buffer_offset + 2;
                if (index == 767) begin
                    if (bad_program)
                        cart[base + 255] <= 16'h0000;
                    programming <= 0;
                    flash_ready <= 1;
                    flash_done <= 1;
                end
            end
        end
    end
    task start;
        begin
            @(negedge clk);
            start_write = 1;
            @(negedge clk);
            start_write = 0;
        end
    endtask
    task arm;
        begin
            wait(armed || done);
            if (!armed)
                $fatal(1, "unexpected preflight failure %d phase%d", error_code, phase);
        end
    endtask
    task approve;
        begin
            @(negedge clk);
            confirm = 1;
            @(negedge clk);
            confirm = 0;
        end
    endtask
    task recover;
        begin
            start();
            arm();
            approve();
            wait(done);
            #1;
            if (error_code || restore_required || erased_sectors != BYTES / 512)
                $fatal(1, "recovery failed %d", error_code);
            for (i = 0; i < BYTES / 2; i = i + 1)
                if (cart[i] !== target(i))
                    $fatal(1, "recovered data %d", i);
        end
    endtask
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            dut.cache.memory[i] = i ^ 16'hBEEF;
        for (i = 0; i < 256; i = i + 1)
            dut.digests[i] = 32'hDEADBEEF;
        for (i = 0; i < BYTES / 2; i = i + 1)
            cart[i] = original(i);
        repeat (3) @(negedge clk)
            ;
        reset_n = 1;
        if (COUNT_TEST) begin
            recover();
            if (erased_sectors != 256 || programmed_buffers != 256 || progress != BYTES)
                $fatal(1, "256-sector counter/write completion");
            cart[1000] = 16'h0012;
            recover();
            $display(
                {"PASS rom_writer_count: all 256 sectors, no counter wrap, complete ", "recovery"});
            $finish;
        end
        unknown_target = 1;
        start();
        wait(armed || done);
        #1;
        if (armed || error_code != 13 || mutations)
            $fatal(1, "unknown source armed or erased");
        unknown_target = 0;
        file_ready = 0;
        start();
        wait(dut.state == 1);
        @(negedge clk);
        file_poisoned = 1;
        repeat (4) @(negedge clk)
            ;
        if (busy || error_code != 16 || mutations)
            $fatal(1, "late APF poison left preflight waiting");
        file_poisoned = 0;
        file_ready = 1;
        target_size = 699;
        start();
        wait(done);
        if (error_code != 2 || mutations)
            $fatal(1, "alignment gate");
        target_size = 700;
        start();
        arm();
        if (image_crc !== 32'hB5BB7B5B || dut.digests[0] !== 32'h5034D0C7 ||
            dut.digests[1] !== 32'h1FD8CDF9 || dut.digests[2] !== 32'hBD7BC39F)
            $fatal(1, "padded image/sector CRCs differ from independent zlib fixture");
        @(negedge clk);
        cancel = 1;
        @(negedge clk);
        cancel = 0;
        wait(done);
        // Corruption after word readback must fail the independent full-cache CRC.
        start();
        arm();
        before_count = mutations;
        approve();
        wait(dut.state == 6 && dut.pass == 3);
        @(negedge clk);
        dut.cache.memory[0] = 16'hBAD0;
        wait(done);
        if (error_code != 13 || mutations != before_count)
            $fatal(1, "cache sweep missed stale word");
        start();
        arm();
        before_count = mutations;
        approve();
        wait(dut.state == 13);
        @(negedge clk);
        force dut.cache_q = 16'hxxxx;
        @(negedge clk);
        release dut.cache_q;
        wait(done);
        if (error_code != 13 || mutations != before_count)
            $fatal(1, "X cache word accepted");
        start();
        arm();
        before_count = mutations;
        dut.digests[0] = 32'h12345678;
        approve();
        wait(done);
        if (error_code != 13 || mutations != before_count)
            $fatal(1, "changed digest accepted");
        for (i = 0; i < BYTES / 2; i = i + 1)
            cart[i] = 16'hFFFF;
        start();
        arm();
        if (mutations || image_crc !== 32'hB5BB7B5B)
            $fatal(1, "public preflight/base gate");
        approve();
        wait(done);
        #1;
        if (error_code || restore_required || erased_sectors != 3 || programmed_buffers != 2)
            $fatal(1, "public write failed %d", error_code);
        for (i = 0; i < BYTES / 2; i = i + 1)
            if (cart[i] !== target(i))
                $fatal(1, "public target mismatch");
        start();
        arm();
        approve();
        wait(flash_request && flash_operation == 1);
        @(negedge clk);
        cancel = 1;
        @(negedge clk);
        cancel = 0;
        wait(done);
        if (error_code != 6 || !restore_required || erased_sectors != 1)
            $fatal(1, "public cancellation");
        cart[300] = 16'h0012;
        @(negedge clk);
        reset_n = 0;
        @(negedge clk);
        reset_n = 1;
        start();
        arm();
        approve();
        wait(done);
        #1;
        if (error_code || restore_required)
            $fatal(1, "public recovery of partial cart");
        start();
        arm();
        @(negedge clk);
        input_changed = 1;
        @(negedge clk);
        input_changed = 0;
        wait(done);
        if (error_code != 7)
            $fatal(1, "public target change not detected");
        unknown_target = 1;
        start();
        wait(done || armed);
        #1;
        if (armed || error_code != 13)
            $fatal(1, "public unknown target armed");
        unknown_target = 0;
        start();
        arm();
        approve();
        wait(dut.final_pass && dut.position == BYTES - 2 && dut.state == 20 && read_done);
        @(negedge clk);
        cancel = 1;
        @(negedge clk);
        cancel = 0;
        wait(done);
        if (error_code != 6 || !restore_required)
            $fatal(1, "public final cancellation reported verified");

        recover();
        start();
        arm();
        before_count = mutations;
        approve();
        wait(programming);
        @(negedge clk);
        dut.cache.memory[255] = 16'hBAD0;
        wait(done);
        if (error_code != 13 || erased_sectors != 1)
            $fatal(1, "program cache corruption escaped digest");
        recover();
        start();
        arm();
        corrupt_target = 1;
        before_count = mutations;
        approve();
        wait(done);
        if (error_code != 13 || mutations != before_count)
            $fatal(1, "changed target erased sector");
        corrupt_target = 0;
        fail_erase = 1;
        start();
        arm();
        approve();
        wait(done);
        if (error_code != 14 || !restore_required)
            $fatal(1, "erase error");
        fail_erase = 0;
        recover();
        // The command reports success, but physical array verification must still fail.
        bad_blank = 1;
        start();
        arm();
        approve();
        wait(done);
        #1;
        if (error_code != 8 || !restore_required || error_address != 14 || expected !== 16'hFFFF ||
            observed !== 16'hBAD0)
            $fatal(1, "nonblank array accepted after successful erase: %d", error_code);
        bad_blank = 0;
        recover();
        bad_program = 1;
        start();
        arm();
        approve();
        wait(done);
        #1;
        if (error_code != 8 || !restore_required || error_address != 510 ||
            expected !== target(255) || observed !== 16'h0000)
            $fatal(1, "corrupt array accepted after successful program: %d", error_code);
        bad_program = 0;
        recover();
        sd_error = 1;
        start();
        wait(done);
        if (error_code != 5)
            $fatal(1, "SD error");
        sd_error = 0;
        file_poisoned = 1;
        start();
        wait(done);
        if (error_code != 16)
            $fatal(1, "SD poison");
        file_poisoned = 0;
        flash_poisoned = 1;
        start();
        wait(done);
        if (error_code != 17)
            $fatal(1, "flash poison");
        flash_poisoned = 0;
        $display({"PASS rom_writer: padded target, partial-cart recovery, safe cancellation, ",
                  "cache/source corruption and transport/error gates"});
        $finish;
    end
    initial begin
        #50000000;
        $fatal(1, "writer timeout phase=%d error=%d", phase, error_code);
    end
endmodule
