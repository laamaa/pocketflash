// S29GL256S-family operations. Command addresses below are BYTE offsets.
// Query determines command-bit encoding; ROM payload is never bit-swapped.
// Persistent operations require BOTH a compiled writer and a successful probe.
`timescale 1ns / 1ps
`default_nettype none
module flash_ops
    #(parameter ALLOW_QUERY = 0,
      parameter ALLOW_PROGRAM = 0,
      // Validated target board: GPIO can overlay ROM at C4/C6/C8 after
      // payload writes. Disable its read overlay only after known array mode.
      parameter CLEAR_GPIO = 0,
      parameter [24 : 0] WRITE_BEGIN = 25'h1FE0000, WRITE_END = 25'h1FFFFFF,
      parameter ERASE_TIMEOUT = 742500000,
      parameter PROGRAM_TIMEOUT = 7425000)
    (input wire clk, reset_n, request,
     input wire [1 : 0] operation,
     // 0=query, 1=erase sector, 2=program 512-byte buffer
     input wire [24 : 0] address,
     output wire ready,
     output reg done, error,
     output reg identified,
     output reg completion_known, read_mode, poisoned,
     output reg [15 : 0] raw_status,
     output reg swapped,
     output reg [15 : 0] manufacturer, device,
     output reg [7 : 0] stage,
     output reg bus_request, bus_write,
     output reg [24 : 0] bus_address,
     output reg [15 : 0] bus_data,
     input wire bus_ready, bus_done, bus_error,
     input wire [15 : 0] bus_q,
     output wire [15 : 0] buffer_offset,
     input wire [15 : 0] buffer_q);
    localparam IDLE = 0, ISSUE = 1, WAIT_BUS = 2, STEP = 3, FINISH = 4, GPIO_ISSUE = 5,
               GPIO_WAIT = 6;
    reg [2 : 0] state;
    reg [1 : 0] op;
    reg [24 : 0] base;
    reg [8 : 0] index;
    reg [31 : 0] elapsed;
    reg clearing;
    reg recovering;
    reg [1 : 0] recovery_index;
    wire [31 : 0] deadline = op == 2 ? PROGRAM_TIMEOUT : ERASE_TIMEOUT;
    reg [7 : 0] cfi[0 : 8];
    reg [7 : 0] signature[0 : 2];
    reg [15 : 0] normalized;
    assign ready = state == IDLE;
    // Compiled mutation fence. Command unlock addresses are not payload targets.
    // Extended end calculations prevent wraparound and partial-sector erasure.
    wire [25 : 0] program_end = {1'b0, address} + 26'd511;
    wire [25 : 0] erase_end = {1'b0, address} + 26'd131071;
    wire target_allowed =
             address >= WRITE_BEGIN &&
             ((operation == 1 && address[16 : 0] == 0 && erase_end <= {1'b0, WRITE_END}) ||
              (operation == 2 && address[8 : 0] == 0 && program_end <= {1'b0, WRITE_END}));
    wire [8 : 0] payload_index = index - 9'd4;
    assign buffer_offset = {7'b0, payload_index[7 : 0], 1'b0};
    function [15 : 0] encode;
        input [15 : 0] value;
        begin
            encode = swapped ? {value[15 : 2], value[0], value[1]} : value;
        end
    endfunction
    function [24 : 0] query_address;
        input [8 : 0] n;
        begin
            case (n)
                2:
                    query_address = 25'h20;
                3:
                    query_address = 25'h22;
                4:
                    query_address = 25'h24;
                5:
                    query_address = 25'h26; // primary command set low byte
                6:
                    query_address = 25'h28; // primary command set high byte
                7:
                    query_address = 25'h4E; // device size exponent
                8:
                    query_address = 25'h54; // maximum buffer size exponent low
                9:
                    query_address = 25'h56; // maximum buffer size exponent high
                10:
                    query_address = 25'h58; // erase region count
                11:
                    query_address = 25'h5A;
                12:
                    query_address = 25'h5C;
                13:
                    query_address = 25'h5E;
                14:
                    query_address = 25'h60;
                default:
                    query_address = 0;
            endcase
        end
    endfunction
    always @* begin
        bus_write = 0;
        bus_address = base;
        bus_data = 0;
        if (op == 0) begin
            bus_address = query_address(index);
            case (index)
                0, 15, 21: begin
                    bus_write = 1;
                    bus_address = 0;
                    bus_data = 16'hF0;
                end
                1: begin
                    bus_write = 1;
                    bus_address = 25'hAA;
                    bus_data = 16'h98;
                end
                16: begin
                    bus_write = 1;
                    bus_address = 25'hAAA;
                    bus_data = encode(16'hAA);
                end
                17: begin
                    bus_write = 1;
                    bus_address = 25'h554;
                    bus_data = encode(16'h55);
                end
                18: begin
                    bus_write = 1;
                    bus_address = 25'hAAA;
                    bus_data = encode(16'h90);
                end
                19:
                    bus_address = 0;
                20:
                    bus_address = 2;
            endcase
        end else if (op == 1) begin
            bus_write = index != 7;
            case (index)
                0, 3: begin
                    bus_address = 25'hAAA;
                    bus_data = encode(16'hAA);
                end
                1, 4: begin
                    bus_address = 25'h554;
                    bus_data = encode(16'h55);
                end
                2: begin
                    bus_address = 25'hAAA;
                    bus_data = encode(16'h80);
                end
                5:
                    bus_data = encode(16'h30);
                6: begin
                    bus_address = 25'hAAA;
                    bus_data = encode(16'h70);
                end
                8: begin
                    bus_address = 0;
                    bus_data = 16'hF0;
                end
            endcase
        end else begin
            bus_write = index != 262;
            case (index)
                0: begin
                    bus_address = 25'hAAA;
                    bus_data = encode(16'hAA);
                end
                1: begin
                    bus_address = 25'h554;
                    bus_data = encode(16'h55);
                end
                2: begin
                    bus_address = {base[24 : 17], 17'b0};
                    bus_data = encode(16'h25);
                end
                3: begin
                    bus_address = {base[24 : 17], 17'b0};
                    bus_data = encode(16'hFF);
                end
                260: begin
                    bus_address = {base[24 : 17], 17'b0};
                    bus_data = encode(16'h29);
                end
                261: begin
                    bus_address = 25'hAAA;
                    bus_data = encode(16'h70);
                end
                263: begin
                    bus_address = 0;
                    bus_data = 16'hF0;
                end
                default: begin
                    if (index < 260) begin
                        bus_address = base + ((index - 4) << 1);
                        bus_data = buffer_q;
                    end else
                        bus_address = base + 510;
                end
            endcase
        end
        // Infineon 001-98285 Rev. *U, section 5.6: 71 clears embedded
        // errors including write-buffer abort. Re-read ready/error/suspend bits
        // before F0 and handing the array back. No cleanup after unknown status.
        if (recovering) begin
            bus_address = 25'hAAA;
            bus_write = 1;
            bus_data = encode(16'h71);
            case (recovery_index)
                1:
                    bus_data = encode(16'h70);
                2: begin
                    bus_address = base;
                    bus_write = 0;
                end
                3: begin
                    bus_address = 0;
                    bus_data = 16'hF0;
                end
            endcase
        end
        if (clearing) begin
            bus_write = 1;
            bus_address = 25'hAAA;
            bus_data = encode(16'h71);
        end
        if (state == GPIO_ISSUE || state == GPIO_WAIT) begin
            bus_write = 1;
            bus_address = 25'hC8;
            bus_data = 16'h0000;
        end
    end
    // STEP advances the payload index; ISSUE registers the request on the next
    // edge. The bus captures it one edge later, after the synchronous cache
    // output has settled. Indices 4..259 select byte offsets 0..510.
    always @(posedge clk) begin
        done <= 0;
        bus_request <= 0;
        if (!reset_n) begin
            state <= IDLE;
            error <= 0;
            identified <= 0;
            swapped <= 0;
            manufacturer <= 0;
            device <= 0;
            index <= 0;
            stage <= 0;
            elapsed <= 0;
            op <= 0;
            base <= 0;
            clearing <= 0;
            recovering <= 0;
            recovery_index <= 0;
            completion_known <= 0;
            read_mode <= 0;
            poisoned <= 0;
            raw_status <= 0;
        end else begin
            if (state != IDLE)
                elapsed <= elapsed + 1;
            case (state)
                IDLE:
                    if (request) begin
                        op <= operation;
                        base <= address;
                        index <= 0;
                        elapsed <= 0;
                        error <= 0;
                        stage <= 0;
                        if (!poisoned && ((operation == 0 && ALLOW_QUERY) ||
                                          (ALLOW_PROGRAM && identified && target_allowed))) begin
                            completion_known <= 0;
                            read_mode <= 0;
                            raw_status <= 0;
                            clearing <= operation != 0;
                            recovering <= 0;
                            recovery_index <= 0;
                            if (operation == 0) begin
                                identified <= 0;
                                swapped <= 0;
                            end
                            state <= ISSUE;
                        end else begin
                            error <= 1;
                            done <= 1;
                        end
                    end
                ISSUE: begin
                    stage <= index[7 : 0];
                    if (bus_ready) begin
                        bus_request <= 1;
                        state <= WAIT_BUS;
                    end
                end
                WAIT_BUS:
                    if (bus_done) begin
                        if (bus_error) begin
                            error <= 1;
                            poisoned <= 1;
                            completion_known <= 0;
                            read_mode <= 0;
                            state <= FINISH;
                        end else if (recovering) begin
                            if (recovery_index == 2 && ((encode(bus_q) & 16'h00FE) !== 16'h0080))
                            begin
                                poisoned <= 1;
                                completion_known <= 0;
                                read_mode <= 0;
                                state <= FINISH;
                            end else if (recovery_index == 3) begin
                                read_mode <= !CLEAR_GPIO;
                                state <= CLEAR_GPIO ? GPIO_ISSUE : FINISH;
                            end else begin
                                recovery_index <= recovery_index + 1'b1;
                                state <= ISSUE;
                            end
                        end else if (clearing) begin
                            clearing <= 0;
                            state <= ISSUE;
                        end else begin
                            normalized = encode(bus_q);
                            if (op == 0) begin
                                if (index >= 2 && index <= 4)
                                    signature[index - 2] <= bus_q[7 : 0];
                                if (index == 4) begin
                                    if (signature[0] == 8'h51 && signature[1] == 8'h52 &&
                                        bus_q[7 : 0] == 8'h59)
                                        swapped <= 0;
                                    else if (signature[0] == 8'h52 && signature[1] == 8'h51 &&
                                             bus_q[7 : 0] == 8'h5A)
                                        swapped <= 1;
                                    else
                                        error <= 1;
                                end
                                if (index >= 5 && index <= 13)
                                    cfi[index - 5] <= normalized[7 : 0];
                                if (index == 14 &&
                                    {cfi[0], cfi[1], cfi[2], cfi[3], cfi[4], cfi[5], cfi[6], cfi[7],
                                     cfi[8], normalized[7 : 0]} !== 80'h020019090001FF000002)
                                    error <= 1;
                                if (index == 19)
                                    manufacturer <= normalized;
                                if (index == 20)
                                    device <= normalized;
                                if (index == 21) begin
                                    completion_known <= 1;
                                    read_mode <= !CLEAR_GPIO;
                                    identified <=
                                        !error && manufacturer === 16'h0001 && device === 16'h227E;
                                    if (manufacturer !== 16'h0001 || device !== 16'h227E)
                                        error <= 1;
                                end
                            end
                            if ((op == 1 && index == 7) || (op == 2 && index == 262)) begin
                                raw_status <= normalized;
                                if ((^(normalized & 16'h00FE)) === 1'bx) begin
                                    error <= 1;
                                    poisoned <= 1;
                                    completion_known <= 0;
                                    read_mode <= 0;
                                    state <= FINISH;
                                end else if (normalized[7]) begin
                                    if ((normalized & 16'h0044) != 0) begin
                                        error <= 1;
                                        poisoned <= 1;
                                        completion_known <= 0;
                                        state <= FINISH;
                                    end else begin
                                        completion_known <= 1;
                                        if ((normalized & 16'h003A) != 0) begin
                                            error <= 1;
                                            recovering <= 1;
                                            recovery_index <= 0;
                                            elapsed <= 0;
                                            state <= ISSUE;
                                        end else
                                            state <= STEP;
                                    end
                                end else if (elapsed >= deadline) begin
                                    error <= 1;
                                    poisoned <= 1;
                                    completion_known <= 0;
                                    state <= FINISH;
                                end else begin
                                    index <= index - 1;
                                    state <= ISSUE;
                                end
                            end else
                                state <= STEP;
                        end
                    end
                STEP: begin
                    if ((op == 0 && index == 21) || (op == 1 && index == 8) ||
                        (op == 2 && index == 263)) begin
                        read_mode <= !CLEAR_GPIO;
                        state <= CLEAR_GPIO ? GPIO_ISSUE : FINISH;
                    end else begin
                        index <= index + 1;
                        state <= ISSUE;
                    end
                end
                GPIO_ISSUE:
                    if (bus_ready) begin
                        bus_request <= 1;
                        state <= GPIO_WAIT;
                    end
                GPIO_WAIT:
                    if (bus_done) begin
                        if (bus_error) begin
                            error <= 1;
                            poisoned <= 1;
                            completion_known <= 0;
                            read_mode <= 0;
                        end else
                            read_mode <= 1;
                        state <= FINISH;
                    end
                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                    if (error)
                        identified <= 0;
                end
                default:
                    state <= IDLE;
            endcase
            // Bound the whole request, including a bus that never acknowledges.
            // Guard after the state machine so a late response cannot win a timeout.
            if (state != IDLE && state != FINISH && elapsed >= deadline) begin
                error <= 1;
                poisoned <= 1;
                completion_known <= 0;
                read_mode <= 0;
                bus_request <= 0;
                state <= FINISH;
            end
        end
    end
endmodule
