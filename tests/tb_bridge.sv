`timescale 1ns / 1ps
module tb_bridge;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg ss = 0, sending = 1, host_clock = 0, host_mosi = 0, host_miso = 0;
    tri spi_clock, spi_mosi, spi_miso;
    assign spi_clock = sending ? host_clock : 1'bz;
    assign spi_mosi = sending ? host_mosi : 1'bz;
    assign spi_miso = sending ? host_miso : 1'bz;
    wire [31 : 0] address, write_data, read_data;
    wire rd, wr, endian_little;
    reg [31 : 0] keys = 0;
    io_bridge_peripheral bridge(.clk(clk),
                                .reset_n(1'b1),
                                .endian_little(endian_little),
                                .pmp_addr(address),
                                .pmp_addr_valid(),
                                .pmp_rd(rd),
                                .pmp_rd_data(read_data),
                                .pmp_wr(wr),
                                .pmp_wr_data(write_data),
                                .phy_spimosi(spi_mosi),
                                .phy_spimiso(spi_miso),
                                .phy_spiclk(spi_clock),
                                .phy_spiss(ss));
    core_top dut(.clk_74a(clk),
                 .clk_74b(clk),
                 .bridge_endian_little(endian_little),
                 .bridge_addr(address),
                 .bridge_rd(rd),
                 .bridge_wr(wr),
                 .bridge_wr_data(write_data),
                 .bridge_rd_data(read_data),
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

    task send_byte
        (input [7 : 0] data);
        integer bit_index;
        begin
            for (bit_index = 6; bit_index >= 0; bit_index = bit_index - 2) begin
                host_clock = 0;
                host_mosi = data[bit_index + 1];
                host_miso = data[bit_index];
                #40;
                host_clock = 1;
                #40;
            end
        end
    endtask
    task begin_access
        (input [31 : 0] addr);
        begin
            sending = 1;
            host_clock = 0;
            ss = 0;
            send_byte(addr[31 : 24]);
            send_byte(addr[23 : 16]);
            send_byte(addr[15 : 8]);
            send_byte(addr[7 : 0]);
        end
    endtask
    task end_access;
        begin
            ss = 1;
            sending = 1;
            host_clock = 0;
            repeat (12) @(negedge clk)
                ;
        end
    endtask
    task write_word
        (input [31 : 0] addr,
         input [31 : 0] data);
        begin
            begin_access(addr | 1);
            send_byte(data[31 : 24]);
            send_byte(data[23 : 16]);
            send_byte(data[15 : 8]);
            send_byte(data[7 : 0]);
            repeat (12) @(negedge clk)
                ;
            end_access();
        end
    endtask
    task read_word
        (input [31 : 0] addr,
         output [31 : 0] data);
        integer pair;
        begin
            begin_access(addr);
            sending = 0;
            wait(bridge.spis == bridge.ST_SEND_0);
            for (pair = 15; pair >= 0; pair = pair - 1) begin
                @(posedge spi_clock);
                #1;
                data[pair * 2 +: 2] = {spi_mosi, spi_miso};
            end
            end_access();
        end
    endtask
    task read_expect
        (input [31 : 0] addr,
         input [31 : 0] expected);
        reg [31 : 0] data;
        begin
            read_word(addr, data);
            if (data !== expected)
                $fatal(1, "buffered bridge read at %h: got %h expected prior response %h", addr,
                       data, expected);
        end
    endtask
    task press
        (input integer bit_index);
        begin
            @(negedge clk);
            keys = 1 << bit_index;
            repeat (3) @(negedge clk)
                ;
            keys = 0;
            repeat (3) @(negedge clk)
                ;
        end
    endtask
    reg [31 : 0] ignored;
    initial begin
        #1;
        ss = 1;
        repeat (20) @(negedge clk)
            ;
        write_word(32'hF8002000, 1);
        write_word(32'hF8002004, 32'h02000000);
        write_word(32'hF8002008, 2);
        write_word(32'hF800200C, 16);
        write_word(32'h10000000, 32'h12345678);
        write_word(32'h10000004, 32'hABCDEF01);
        if (dut.commands.slot_table[0] !== 1 || dut.commands.slot_table[1] !== 32'h02000000)
            $fatal(1, "serial table write failed: %h %h", dut.commands.slot_table[0],
                   dut.commands.slot_table[1]);
        // Each serial read returns the PREVIOUS bridge read, per the APF contract.
        read_word(32'hF8001000, ignored);
        read_expect(32'hF8002000, 32'h636D0140);
        read_expect(32'hF8002004, 1);
        read_expect(32'hF8002008, 32'h02000000);
        read_expect(32'hF800200C, 2);
        read_expect(32'h10000000, 16);
        read_expect(32'h10000004, 32'h12345678);
        read_expect(32'h10010000, 32'hABCDEF01);
        read_expect(32'h10010100, 32'h2F536176); // /Sav
        read_expect(32'hF8001000, 0);            // open_flags
        write_word(32'hF8001000, 32'h6F6B0000);
        wait(dut.file_ready);
        write_word(32'hF8000020, 32'h00010000);
        write_word(32'hF8000000, 32'h434D00B1);
        write_word(32'hF8000000, 32'h434D0011); // release app reset
        press(1);
        press(4); // Backup Saves in the public interface
        wait(dut.commands.target_busy && dut.commands.target_status[15 : 0] == 16'h0192);
        if (dut.commands.target_param[0] !== 5)
            $fatal(1, "public save allocation must probe slot5");
        read_word(32'h10010000, ignored);
        read_expect(32'h1001001C, 32'h2F536176); // /Sav
        read_expect(32'h10010020, 32'h76653030); // ve00
        read_expect(32'h10010024, 32'h30312E73); // 01.s
        read_expect(32'hF8001000, 32'h61760000); // av, NUL termination
        $display({"PASS bridge: serial peripheral, table/RAM/struct response holds and public ",
                  "save path"});
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule
