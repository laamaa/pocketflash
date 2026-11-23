// Byte-wide GBA save bus. Public commands are entire nonpersistent operations,
// never arbitrary address/data writes. APP reset is not connected to reset_n.
`timescale 1ns / 1ps
`default_nettype none
module save_bus
    #(parameter TICKS = 75, DEADLINE = 7425000)
    (input wire clk, reset_n, cart_powered, request,
     input wire [1 : 0] operation,
     // 0=read byte,1=array reset,2=identify+reset,3=bank select
     input wire [15 : 0] address,
     input wire bank,
     output wire ready,
     output reg done, error, poisoned,
     output reg [15 : 0] q, address_out,
     output reg [7 : 0] data_out,
     input wire [7 : 0] data_in,
     output reg data_drive, cs2_n, rd_n, wr_n);
    localparam IDLE = 0, ADDRESS = 1, SELECT = 2, ACCESS = 3, HOLD = 4, RELEASE = 5, FINISH = 6;
    reg [2 : 0] state = IDLE, beat;
    reg [1 : 0] op;
    reg [15 : 0] saved_address, identity;
    reg saved_bank, writing;
    reg[7 : 0] sample;
    reg [31 : 0] timer, elapsed;
    assign ready = state == IDLE && !poisoned;
    wire [2 : 0] last_beat = op == 2 ? 6 : op == 3 ? 3 : 0;
    // Each next beat is defined by its operation and ordinal; no caller write data.
    task prepare
        (input [2 : 0] step);
        begin
            writing <= op != 0 && !(op == 2 && (step == 4 || step == 5));
            data_drive <= op != 0 && !(op == 2 && (step == 4 || step == 5));
            address_out <= 0;
            data_out <= 8'hF0;
            if (op == 0)
                address_out <= saved_address;
            else if (op == 2)
                case (step)
                    1: begin
                        address_out <= 16'h5555;
                        data_out <= 8'hAA;
                    end
                    2: begin
                        address_out <= 16'h2AAA;
                        data_out <= 8'h55;
                    end
                    3: begin
                        address_out <= 16'h5555;
                        data_out <= 8'h90;
                    end
                    4:
                        address_out <= 0;
                    5:
                        address_out <= 1;
                    default: begin address_out <= 0; data_out <= 8'hF0;
                    end
                endcase
            else if (op == 3)
                case (step)
                    0: begin
                        address_out <= 16'h5555;
                        data_out <= 8'hAA;
                    end
                    1: begin
                        address_out <= 16'h2AAA;
                        data_out <= 8'h55;
                    end
                    2: begin
                        address_out <= 16'h5555;
                        data_out <= 8'hB0;
                    end
                    3: begin
                        address_out <= 0;
                        data_out <= {7'b0, saved_bank};
                    end
                endcase
            timer <= TICKS - 1;
            state <= ADDRESS;
        end
    endtask
    always @(posedge clk) begin
        done <= 0;
        if (!reset_n) begin
            state <= IDLE;
            beat <= 0;
            op <= 0;
            saved_address <= 0;
            identity <= 0;
            saved_bank <= 0;
            writing <= 0;
            sample <= 0;
            timer <= 0;
            elapsed <= 0;
            q <= 0;
            address_out <= 0;
            data_out <= 0;
            data_drive <= 0;
            cs2_n <= 1;
            rd_n <= 1;
            wr_n <= 1;
            error <= 0;
            poisoned <= 0;
        end else begin
            if (state != IDLE && state != FINISH)
                elapsed <= elapsed + 1;
            case (state)
                IDLE:
                    if (request && !poisoned) begin
                        error <= 0;
                        elapsed <= 0;
                        beat <= 0;
                        op <= operation;
                        saved_address <= address;
                        saved_bank <= bank;
                        identity <= 0;
                        state <= RELEASE;
                        timer <= 0;
                        // RELEASE starts beat0 after captured request arguments settle.
                        if (cart_powered !== 1'b1 || (^operation) === 1'bx ||
                            (operation == 0 && (^address) === 1'bx) ||
                            (operation == 3 && (^bank) === 1'bx)) begin
                            error <= 1;
                            state <= FINISH;
                        end
                    end
                ADDRESS, SELECT, ACCESS, HOLD:
                    if (timer != 0)
                        timer <= timer - 1;
                    else begin
                        timer <= TICKS - 1;
                        case (state)
                            ADDRESS: begin
                                cs2_n <= 0;
                                state <= SELECT;
                            end
                            SELECT: begin
                                rd_n <= writing;
                                wr_n <= !writing;
                                state <= ACCESS;
                            end
                            ACCESS: begin
                                if (!writing) begin
                                    sample <= data_in;
                                    if (op == 2 && beat == 4)
                                        identity[15 : 8] <= data_in;
                                    if (op == 2 && beat == 5)
                                        identity[7 : 0] <= data_in;
                                    if ((^data_in) === 1'bx) begin
                                        error <= 1;
                                        poisoned <= 1;
                                    end
                                end
                                rd_n <= 1;
                                wr_n <= 1;
                                state <= HOLD;
                            end
                            HOLD: begin
                                cs2_n <= 1;
                                state <= RELEASE;
                            end
                        endcase
                    end
                RELEASE:
                    if (timer != 0)
                        timer <= timer - 1;
                    else if (error) begin
                        data_drive <= 0;
                        state <= FINISH;
                    end else if (cs2_n && elapsed == 0)
                        prepare(0);
                    else if (beat == last_beat) begin
                        data_drive <= 0;
                        q <= op == 2 ? identity : {8'b0, sample};
                        state <= FINISH;
                    end else begin
                        beat <= beat + 1'b1;
                        prepare(beat + 1'b1);
                    end
                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
                default: begin
                    error <= 1;
                    poisoned <= 1;
                    state <= FINISH;
                end
            endcase
            if (state != IDLE && state != FINISH && (cart_powered !== 1'b1 || elapsed >= DEADLINE))
            begin
                error <= 1;
                poisoned <= 1;
                state <= FINISH;
                cs2_n <= 1;
                rd_n <= 1;
                wr_n <= 1;
                data_drive <= 0;
            end
        end
    end
endmodule
