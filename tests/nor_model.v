// Stateful GL-S subset for full-ROM and legacy tests. Byte-addressed x16 bus.
// Array contents survive reset_n; only command state resets.
`timescale 1ns / 1ps
module nor_model
    #(parameter [24 : 0] ARRAY_BASE = 25'h1FC0000,
      parameter SECTORS = 2, ACK_DELAY = 1, STALL_PATTERN = 0, GPIO_OVERLAY = 0)
    (input wire clk, reset_n, request, write,
     input wire [24 : 0] address,
     input wire [15 : 0] data,
     output wire ready,
     output reg done = 0, error = 0,
     output reg [15 : 0] q = 0,
     input wire [15 : 0] fault_status,
     input wire busy_forever, stall_bus,
     output integer mutations = 0);
    reg [15 : 0] memory[0 : SECTORS * 65536 - 1]; // sector window starts at ARRAY_BASE
    reg [15 : 0] payload[0 : 255];
    reg [15 : 0] status = 16'h80;
    reg [24 : 0] buffer_base, command_sector;
    reg [8 : 0] count;
    reg [3 : 0] phase = 0;
    reg [1 : 0] mode = 0; // array/CFI/ID
    reg status_read = 0, pending = 0;
    // Board GPIO registers overlay ROM reads until control bit zero is cleared.
    // Payload writes still reach the NOR buffer, as confirmed by the cold dump.
    reg gpio_enabled = 0;
    integer delay_left = 0, ready_delay = 0;
    integer i;
    initial
        for (i = 0; i < SECTORS * 65536; i = i + 1)
            memory[i] = 16'h1234;
    // Idle ready stays high until the registered request is sampled. Backpressure
    // is applied after completion, never by withdrawing a previously offered slot.
    assign ready = !pending && ready_delay == 0;
    function [15 : 0] cfi
        (input [24 : 0] a);
        begin
            case (a)
                25'h20:
                    cfi = 16'h51;
                25'h22:
                    cfi = 16'h52;
                25'h24:
                    cfi = 16'h59;
                25'h26:
                    cfi = 2;
                25'h28:
                    cfi = 0;
                25'h4E:
                    cfi = 25;
                25'h54:
                    cfi = 9;
                25'h56:
                    cfi = 0;
                25'h58:
                    cfi = 1;
                25'h5A:
                    cfi = 255;
                25'h5C:
                    cfi = 0;
                25'h5E:
                    cfi = 0;
                25'h60:
                    cfi = 2;
                default:
                    cfi = 0;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        done <= 0;
        error <= 0;
        if (!reset_n) begin
            phase <= 0;
            mode <= 0;
            status_read <= 0;
            pending <= 0;
            ready_delay <= 0;
            status <= 16'h80;
            gpio_enabled <= 0;
        end else begin
            if (ready_delay > 0)
                ready_delay <= ready_delay - 1;
            if (pending && !stall_bus) begin
                if (delay_left == 0) begin
                    done <= 1;
                    pending <= 0;
                    ready_delay <= STALL_PATTERN ? 2 : 0;
                end else
                    delay_left <= delay_left - 1;
            end
            if (request && ready) begin
                pending <= 1;
                delay_left <= ACK_DELAY - 1;
                if (write) begin
                    if (GPIO_OVERLAY && address == 25'hC8)
                        gpio_enabled <= data[0];
                    if (phase == 7) begin
                        if (data != 16'hFF || address != command_sector)
                            $fatal(1, "invalid word count");
                        count <= 0;
                        phase <= 8;
                    end else if (phase == 8) begin
                        if (count == 0)
                            buffer_base <= address;
                        else if (address != buffer_base + count * 2)
                            $fatal(1, "nonsequential payload");
                        if (address < ARRAY_BASE || address >= ARRAY_BASE + SECTORS * 131072 ||
                            address[24 : 17] != command_sector[24 : 17] ||
                            address[8 : 0] != (count * 2))
                            $fatal(1, "buffer crossed boundary");
                        payload[count] <= data;
                        if (count == 255)
                            phase <= 9;
                        else
                            count <= count + 1;
                    end else if (phase == 9) begin
                        if (address != command_sector || data != 16'h29)
                            $fatal(1, "invalid confirm");
                        status <= fault_status == 0 ? 16'h80 : fault_status;
                        if (fault_status == 0 && !busy_forever) begin
                            for (i = 0; i < 256; i = i + 1) begin
                                if ((memory[((buffer_base - ARRAY_BASE) >> 1) + i] & payload[i]) !=
                                    payload[i])
                                    $fatal(1, "program needs erase");
                                memory[((buffer_base - ARRAY_BASE) >> 1) + i] <= payload[i];
                            end
                            mutations <= mutations + 1;
                        end
                        phase <= 0;
                    end else if (address == 25'hC8 && data == 0 && phase == 0 && mode == 0) begin
                    end else if (data == 16'h71 && address == 25'hAAA) begin
                        status <= 16'h80;
                        phase <= 0;
                    end else if (data == 16'h70 && address == 25'hAAA)
                        status_read <= 1;
                    else if (data == 16'hF0) begin
                        if (status[3])
                            $fatal(1, "plain F0 cannot clear buffer abort");
                        mode <= 0;
                        phase <= 0;
                    end else if (address == 25'hAA && data == 16'h98)
                        mode <= 1;
                    else
                        case (phase)
                            0:
                                if (address == 25'hAAA && data == 16'hAA)
                                    phase <= 1;
                                else
                                    $fatal(1, "bad unlock 1");
                            1:
                                if (address == 25'h554 && data == 16'h55)
                                    phase <= 2;
                                else
                                    $fatal(1, "bad unlock 2");
                            2: begin
                                if (data == 16'h90 && address == 25'hAAA) begin
                                    mode <= 2;
                                    phase <= 0;
                                end else if (data == 16'h80 && address == 25'hAAA)
                                    phase <= 3;
                                else if (data == 16'h25 && address[16 : 0] == 0 &&
                                         address >= ARRAY_BASE &&
                                         address < ARRAY_BASE + SECTORS * 131072) begin
                                    command_sector <= address;
                                    phase <= 7;
                                end else
                                    $fatal(1, "unexpected opcode");
                            end
                            3:
                                if (data == 16'hAA && address == 25'hAAA)
                                    phase <= 4;
                                else
                                    $fatal(1, "erase unlock 1");
                            4:
                                if (data == 16'h55 && address == 25'h554)
                                    phase <= 5;
                                else
                                    $fatal(1, "erase unlock 2");
                            5: begin
                                if (address[16 : 0] != 0 || address < ARRAY_BASE ||
                                    address >= ARRAY_BASE + SECTORS * 131072 || data != 16'h30)
                                    $fatal(1, "erase outside sector");
                                if (fault_status == 0 && !busy_forever) begin
                                    for (i = 0; i < 65536; i = i + 1)
                                        memory[((address - ARRAY_BASE) >> 1) + i] <= 16'hFFFF;
                                    mutations <= mutations + 1;
                                end
                                status <= fault_status == 0 ? 16'h80 : fault_status;
                                phase <= 0;
                            end
                            default:
                                $fatal(1, "invalid command phase");
                        endcase
                end else if (status_read) begin
                    q <= busy_forever ? 16'h0 : status;
                    status_read <= 0;
                end else if (mode == 1)
                    q <= cfi(address);
                else if (mode == 2)
                    q <= address == 0 ? 16'h1 : 16'h227E;
                else if (GPIO_OVERLAY && gpio_enabled &&
                         (address == 25'hC4 || address == 25'hC6 || address == 25'hC8))
                    q <= 16'h0001;
                else if (address >= ARRAY_BASE && address < ARRAY_BASE + SECTORS * 131072)
                    q <= memory[(address - ARRAY_BASE) >> 1];
                else
                    q <= 16'h1234;
            end
        end
    end
endmodule
