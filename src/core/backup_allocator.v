// Allocate an unused payload/record pair. Never creates or overwrites files.
`timescale 1ns / 1ps
`default_nettype none
module backup_allocator
    #(parameter LAST_NUMBER = 9999)
    (input wire clk, reset_n, start, is_save, cancel,
     output wire busy,
     output reg done, error, report_path, file_request,
     output reg [7 : 0] error_code,
     output reg [13 : 0] number,
     output reg [15 : 0] digits,
     output wire [15 : 0] file_slot,
     input wire file_ready, file_done,
     input wire [15 : 0] file_result);
    localparam IDLE = 0, ISSUE = 1, WAIT = 2, RESULT = 3;
    reg [1 : 0] state;
    reg save_mode, cancelled;
    assign busy = state != IDLE;
    assign file_slot = save_mode ? (report_path ? 6 : 5) : (report_path ? 2 : 1);
    task finish
        (input [7 : 0] code);
        begin
            error <= code != 0;
            error_code <= code;
            done <= 1;
            state <= IDLE;
        end
    endtask
    always @(posedge clk) begin
        done <= 0;
        file_request <= 0;
        if (!reset_n) begin
            state <= IDLE;
            error <= 0;
            error_code <= 0;
            number <= 1;
            digits <= 16'h0001;
            report_path <= 0;
            save_mode <= 0;
            cancelled <= 0;
        end else begin
            if (busy && cancel)
                cancelled <= 1;
            case (state)
                IDLE:
                    if (start) begin
                        number <= 1;
                        digits <= 16'h0001;
                        report_path <= 0;
                        save_mode <= is_save;
                        cancelled <= 0;
                        error <= 0;
                        error_code <= 0;
                        state <= ISSUE;
                    end
                ISSUE:
                    if (cancel || cancelled)
                        finish(6);
                    else if (file_ready) begin
                        file_request <= 1;
                        state <= WAIT;
                    end
                WAIT:
                    if (file_done) begin
                        if (cancel || cancelled)
                            finish(6);
                        else if (file_result == 3) begin
                            if (report_path)
                                finish(0);
                            else begin
                                report_path <= 1;
                                state <= ISSUE;
                            end
                        end else if (file_result == 0) begin
                            if (number == LAST_NUMBER)
                                finish(14);
                            else begin
                                number <= number + 1'b1;
                                report_path <= 0;
                                state <= ISSUE;
                                if (digits[3 : 0] != 9)
                                    digits[3 : 0] <= digits[3 : 0] + 1'b1;
                                else begin
                                    digits[3 : 0] <= 0;
                                    if (digits[7 : 4] != 9)
                                        digits[7 : 4] <= digits[7 : 4] + 1'b1;
                                    else begin
                                        digits[7 : 4] <= 0;
                                        if (digits[11 : 8] != 9)
                                            digits[11 : 8] <= digits[11 : 8] + 1'b1;
                                        else begin
                                            digits[11 : 8] <= 0;
                                            digits[15 : 12] <= digits[15 : 12] + 1'b1;
                                        end
                                    end
                                end
                            end
                        end else
                            finish(5);
                    end
                default:
                    finish(10);
            endcase
        end
    end
endmodule
