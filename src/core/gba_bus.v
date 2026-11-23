// One nonsequential GBA ROM halfword transaction. All addresses are BYTE offsets.
// PHI is held low; save CS2 stays high outside this module.
`timescale 1ns / 1ps
`default_nettype none
module gba_bus
    #(parameter ALLOW_WRITES = 0,
      parameter TICKS = 75 // >=1 us per phase at 74.25 MHz; no burst assumptions
    )
    (input wire clk, reset_n,
     input wire request, write,
     input wire [24 : 0] address,
     input wire [15 : 0] write_data,
     output wire ready,
     output reg done, error,
     output reg [15 : 0] read_data,
     input wire [15 : 0] ad_in,
     output reg [15 : 0] ad_out,
     output reg ad_drive,
     output reg [7 : 0] a_high,
     output reg cs_n, rd_n, wr_n);
    localparam IDLE = 0, ADDRESS = 1, LATCH = 2, TURN = 3, ACCESS = 4, HOLD = 5, RELEASE = 6;
    reg [2 : 0] state = IDLE;
    integer timer = 0;
    reg writing;
    reg [15 : 0] payload;
    assign ready = state == IDLE;
    always @(posedge clk) begin
        done <= 0;
        if (!reset_n) begin
            state <= IDLE;
            timer <= 0;
            error <= 0;
            read_data <= 0;
            cs_n <= 1;
            rd_n <= 1;
            wr_n <= 1;
            ad_drive <= 0;
            a_high <= 0;
            ad_out <= 0;
            writing <= 0;
            payload <= 0;
        end else if (state == IDLE) begin
            error <= 0;
            if (request) begin
                if (address[0] || (write && !ALLOW_WRITES)) begin
                    error <= 1;
                    done <= 1;
                end else begin
                    a_high <= address[24 : 17];
                    ad_out <= address[16 : 1];
                    payload <= write_data;
                    writing <= write;
                    ad_drive <= 1;
                    state <= ADDRESS;
                    timer <= TICKS - 1;
                end
            end
        end else if (timer != 0)
            timer <= timer - 1;
        else begin
            timer <= TICKS - 1;
            case (state)
                ADDRESS: begin
                    cs_n <= 0;
                    state <= LATCH;
                end
                LATCH: begin
                    ad_drive <= writing;
                    if (writing)
                        ad_out <= payload;
                    state <= TURN;
                end
                TURN: begin
                    rd_n <= writing;
                    wr_n <= !writing;
                    state <= ACCESS;
                end
                ACCESS: begin
                    if (!writing)
                        read_data <= ad_in;
                    rd_n <= 1;
                    wr_n <= 1;
                    state <= HOLD;
                end
                HOLD: begin
                    cs_n <= 1;
                    state <= RELEASE;
                end
                RELEASE: begin
                    ad_drive <= 0;
                    state <= IDLE;
                    done <= 1;
                end
                default: begin
                    state <= IDLE;
                    cs_n <= 1;
                    rd_n <= 1;
                    wr_n <= 1;
                    ad_drive <= 0;
                end
            endcase
        end
    end
endmodule
