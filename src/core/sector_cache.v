// One 128 KiB sector cache, independent of the APF transfer buffer.
// Addresses are halfword indices. A write/read collision returns OLD_DATA;
// callers must wait for a subsequent read edge before checking the written word.
// The array is not reset, preserving block-RAM inference. Callers must fill and
// validate a sector before using it as a programming source.
`timescale 1ns / 1ps
`default_nettype none
module sector_cache
    (input wire clk, write_enable,
     input wire [15 : 0] write_word, write_data, read_word,
     output reg [15 : 0] read_data);
    reg [15 : 0] memory[0 : 65535];
    always @(posedge clk) begin
        if (write_enable)
            memory[write_word] <= write_data;
        read_data <= memory[read_word];
    end
endmodule
