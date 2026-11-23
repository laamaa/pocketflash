// Two independent ports: APF transfers 32-bit big-endian words; the engine
// accesses 16-bit little-endian cartridge words. Four byte lanes infer BRAM.
// APF presents the address before bridge_rd. Hold its response until the next
// read strobe: the serial peripheral sends the previous response first.
`timescale 1ns / 1ps
`default_nettype none
module transfer_ram
    (input wire clk,
     input wire bridge_wr, bridge_rd,
     input wire [15 : 0] bridge_offset,
     input wire [31 : 0] bridge_data,
     output reg [31 : 0] bridge_q,
     input wire engine_wr,
     input wire [15 : 0] engine_offset,
     input wire [15 : 0] engine_data,
     output wire [15 : 0] engine_q);
    wire [13 : 0] ba = bridge_offset[15 : 2], ea = engine_offset[15 : 2];
    wire [31 : 0] engine_lanes, bridge_lanes;
    always @(posedge clk)
        if (bridge_rd)
            bridge_q <= bridge_lanes;
    reg engine_half;
    always @(posedge clk)
        engine_half <= engine_offset[1];
    assign engine_q = engine_half ? engine_lanes[15 : 0] : engine_lanes[31 : 16];
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : lanes
            wire [7 : 0] data_byte = (lane % 2) == 0 ? engine_data[7 : 0] : engine_data[15 : 8];
            wire [7 : 0] engine_byte;
            transfer_ram_lane memory(.clk(clk),
                                     .a_addr(ba),
                                     .a_wr(bridge_wr),
                                     .a_data(bridge_data[31 - lane * 8 -: 8]),
                                     .a_q(bridge_lanes[31 - lane * 8 -: 8]),
                                     .b_addr(ea),
                                     .b_wr(engine_wr && engine_offset[1] == (lane / 2)),
                                     .b_data(data_byte),
                                     .b_q(engine_byte));
            // Assemble cartridge halfwords from the registered byte-lane outputs.
            if (lane == 0)
                assign engine_lanes[23 : 16] = engine_byte;
            if (lane == 1)
                assign engine_lanes[31 : 24] = engine_byte;
            if (lane == 2)
                assign engine_lanes[7 : 0] = engine_byte;
            if (lane == 3)
                assign engine_lanes[15 : 8] = engine_byte;
        end
    endgenerate
endmodule

// Use unconditional, write-through output registers on both ports, following
// Quartus's true dual-port RAM template. Byte/halfword muxes stay outside RAM.
// APF and the engine must never write the same location concurrently.
module transfer_ram_lane
    (input wire clk,
     input wire [13 : 0] a_addr, b_addr,
     input wire a_wr, b_wr,
     input wire [7 : 0] a_data, b_data,
     output reg [7 : 0] a_q, b_q);
    reg [7 : 0] memory[0 : 16383];
    always @(posedge clk) begin
        if (a_wr) begin
            memory[a_addr] <= a_data;
            a_q <= a_data;
        end else
            a_q <= memory[a_addr];
    end
    always @(posedge clk) begin
        if (b_wr) begin
            memory[b_addr] <= b_data;
            b_q <= b_data;
        end else
            b_q <= memory[b_addr];
    end
endmodule
