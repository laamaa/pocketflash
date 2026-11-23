// A save capture session. App reset requests cleanup; core reset alone clears
// poison. Bus commands are closed operations from save_bus, not raw writes.
`timescale 1ns / 1ps
`default_nettype none
module save_reader
    (input wire clk, core_reset_n, app_reset_n, cart_powered, start, close, word_request,
     input wire [16 : 0] address,
     output wire word_ready, busy,
     output reg word_done, word_error, done, error, poisoned,
     output reg [15 : 0] word_q, identity,
     output reg bus_request,
     output reg [1 : 0] bus_operation,
     output reg [15 : 0] bus_address,
     output reg bus_bank,
     input wire bus_ready, bus_done, bus_error, bus_poisoned,
     input wire [15 : 0] bus_q);
    localparam IDLE = 0, REQUEST = 1, WAIT = 2, ACTIVE = 3, FINISH = 4;
    localparam IDENTIFY = 0, SETUP = 1, BANK = 2, LOW = 3, HIGH = 4, CLEAN_BANK = 5,
               CLEAN_RESET = 6;
    reg [2 : 0] state, action;
    reg closing, current_bank;
    reg [16 : 0] saved_address;
    reg [7 : 0] low_byte;
    assign busy = state != IDLE;
    assign word_ready =
               state == ACTIVE && !closing && app_reset_n && !close && !poisoned && cart_powered;
    task command
        (input [1 : 0] op,
         input [15 : 0] addr,
         input bank,
         input [2 : 0] next_action);
        begin
            bus_operation <= op;
            bus_address <= addr;
            bus_bank <= bank;
            action <= next_action;
            state <= REQUEST;
        end
    endtask
    task failed;
        begin
            error <= 1;
            poisoned <= 1;
            word_done <= 1;
            word_error <= 1;
            state <= FINISH;
        end
    endtask
    always @(posedge clk) begin
        bus_request <= 0;
        word_done <= 0;
        done <= 0;
        if (!core_reset_n) begin
            state <= IDLE;
            action <= IDENTIFY;
            closing <= 0;
            current_bank <= 0;
            saved_address <= 0;
            low_byte <= 0;
            word_error <= 0;
            error <= 0;
            poisoned <= 0;
            word_q <= 0;
            identity <= 0;
            bus_operation <= 0;
            bus_address <= 0;
            bus_bank <= 0;
        end else begin
            if (busy && (close || !app_reset_n))
                closing <= 1;
            case (state)
                IDLE:
                    if (start && app_reset_n && !poisoned) begin
                        closing <= 0;
                        error <= 0;
                        word_error <= 0;
                        identity <= 0;
                        if (cart_powered !== 1'b1 || bus_poisoned)
                            failed();
                        else
                            command(2, 0, 0, IDENTIFY);
                    end
                REQUEST:
                    if (cart_powered !== 1'b1 || bus_poisoned)
                        failed();
                    else if (bus_ready) begin
                        bus_request <= 1;
                        state <= WAIT;
                    end
                WAIT:
                    if (bus_done) begin
                        if (bus_error || bus_poisoned || cart_powered !== 1'b1)
                            failed();
                        else if (action == IDENTIFY && bus_q !== 16'hBFD5 && bus_q !== 16'hC209)
                        begin
                            identity <= bus_q;
                            failed();
                        end else if ((closing || close || !app_reset_n) && action != CLEAN_BANK &&
                                     action != CLEAN_RESET) begin
                            word_done <= action == LOW || action == HIGH || action == BANK;
                            word_error <= 1;
                            command(3, 0, 0, CLEAN_BANK);
                        end else
                            case (action)
                                IDENTIFY: begin
                                    identity <= bus_q;
                                    // WAIT rejected unsupported IDs before the cancellation
                                    // branch too, so neither path bank-switches an unknown
                                    // device. C209 is a CPLD logical ID, not the chip vendor.
                                    command(3, 0, 0, SETUP);
                                end
                                SETUP: begin
                                    current_bank <= 0;
                                    state <= ACTIVE;
                                end
                                BANK: begin
                                    current_bank <= saved_address[16];
                                    command(0, saved_address[15 : 0], 0, LOW);
                                end
                                LOW: begin
                                    low_byte <= bus_q[7 : 0];
                                    command(0, saved_address[15 : 0] + 16'd1, 0, HIGH);
                                end
                                HIGH: begin
                                    word_q <= {bus_q[7 : 0], low_byte};
                                    word_done <= 1;
                                    word_error <= 0;
                                    state <= ACTIVE;
                                end
                                CLEAN_BANK: begin
                                    current_bank <= 0;
                                    command(1, 0, 0, CLEAN_RESET);
                                end
                                CLEAN_RESET:
                                    state <= FINISH;
                                default:
                                    failed();
                            endcase
                    end
                ACTIVE:
                    if (closing || close || !app_reset_n)
                        command(3, 0, 0, CLEAN_BANK);
                    else if (word_request) begin
                        saved_address <= address;
                        if (address[0] || (^address) === 1'bx) begin
                            error <= 1;
                            word_done <= 1;
                            word_error <= 1;
                            closing <= 1;
                            command(3, 0, 0, CLEAN_BANK);
                        end else if (address[16] != current_bank)
                            command(3, 0, address[16], BANK);
                        else
                            command(0, address[15 : 0], 0, LOW);
                    end
                FINISH:
                    if (bus_ready || bus_poisoned) begin
                        done <= 1;
                        state <= IDLE;
                    end
                default:
                    failed();
            endcase
            if (busy && cart_powered !== 1'b1 && state != WAIT && state != FINISH)
                failed();
        end
    end
endmodule
