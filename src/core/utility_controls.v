`timescale 1ns / 1ps
`default_nettype none
module utility_controls
    #(parameter HOLD_TICKS = 148500000)
    (input wire clk, reset_n, in_menu, idle_allowed, busy, armed, poisoned,
     input wire [15 : 0] keys,
     output reg [2 : 0] selection,
     output reg acknowledge, help, details, start, confirm, cancel);
    reg [15 : 0] previous;
    reg released, armed_previous;
    reg [31 : 0] held;
    wire [15 : 0] pressed = keys & ~previous;
    always @(posedge clk) begin
        previous <= keys;
        armed_previous <= armed;
        start <= 0;
        confirm <= 0;
        cancel <= 0;
        if (!reset_n) begin
            previous <= 16'hFFFF;
            selection <= 0;
            acknowledge <= 0;
            help <= 0;
            details <= 0;
            released <= 0;
            held <= 0;
            armed_previous <= 0;
        end else begin
            if (pressed[6] && !in_menu)
                details <= !details;
            if (in_menu || poisoned)
                acknowledge <= 0;
            if (!in_menu && pressed[5]) begin
                acknowledge <= 0;
                help <= 0;
                cancel <= busy;
            end
            if (!in_menu && idle_allowed && !busy && !poisoned) begin
                if (!acknowledge && !help) begin
                    if (pressed[0] && selection > 0)
                        selection <= selection - 1'b1;
                    if (pressed[1] && selection < 4)
                        selection <= selection + 1'b1;
                end
                if (pressed[4] && !(pressed[0] || pressed[1] || pressed[5])) begin
                    if (selection == 4)
                        help <= !help;
                    else if (selection == 2 && !acknowledge)
                        acknowledge <= 1;
                    else begin
                        start <= 1;
                        acknowledge <= 0;
                    end
                end
            end
            if (!armed || !armed_previous || in_menu || poisoned) begin
                held <= 0;
                released <= 0;
            end else if (!keys[4]) begin
                held <= 0;
                released <= 1;
            end else if (released) begin
                if (held == HOLD_TICKS - 1) begin
                    confirm <= 1;
                    held <= 0;
                    released <= 0;
                end else
                    held <= held + 1'b1;
            end
        end
    end
endmodule
