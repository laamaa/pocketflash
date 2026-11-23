// APF host/target registers, dataslot table and bounded target transactions.
// APF control registers use big-endian words regardless of payload file ordering.
`timescale 1ns / 1ps
`default_nettype none
module apf_command
    #(parameter TIMEOUT_TICKS = 742500000 // ten seconds per target request at 74.25 MHz
    )
    (input wire clk, boot_ready, app_busy, mutation_lock,
     input wire [31 : 0] bridge_addr, bridge_wr_data,
     input wire bridge_wr, bridge_rd,
     output wire [31 : 0] bridge_rd_data,
     output reg reset_n = 0,
     output reg in_menu = 0,
     output reg cart_powered = 0,
     output reg [31 : 0] input_size = 0,
     output reg input_changed = 0,
     output reg [31 : 0] record_size = 0,
     output reg [2 : 0] source_changed = 0,
     output reg [31 : 0] target_size = 0,
     input wire file_request,
     input wire [15 : 0] file_command, file_slot,
     input wire [31 : 0] file_offset, file_address, file_length,
     output wire file_ready,
     output reg file_done = 0,
     output wire file_poisoned,
     output reg [15 : 0] file_result = 0,
     output reg [31 : 0] trace_target = 0, trace_host_param = 0,
     output reg [15 : 0] trace_host_command = 0, trace_host_result = 0);
    reg [31 : 0] host_status = 0, host_param[0 : 3], host_response[0 : 3];
    reg [31 : 0] target_status = 0, target_param[0 : 3];
    reg [31 : 0] slot_table[0 : 1023];
    reg [31 : 0] table_q, table_response_q, control_q;
    reg table_selected = 0;
    // Track which of the 32 table entries describe original/record/target slots
    // (IDs 0/3/4). ID and size can arrive in either order. These bitmaps avoid
    // adding an asynchronous second read port to the slot-table RAM.
    reg [31 : 0] input_entries = 0, record_entries = 0, target_entries = 0;
    reg [31 : 0] entry_sizes[0 : 31];
    reg [1 : 0] hstate = 0;
    reg [15 : 0] hcommand;
    reg ready_sent = 0, target_busy = 0, target_is_file = 0;
    reg poisoned = 0;
    reg [31 : 0] timeout_count = 0;
    reg trace_host_pending = 0;
    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            host_param[i] = 0;
            host_response[i] = 0;
            target_param[i] = 0;
        end
        for (i = 0; i < 32; i = i + 1)
            entry_sizes[i] = 0;
        for (i = 0; i < 1024; i = i + 1)
            slot_table[i] = 0;
    end
    assign file_poisoned = poisoned;
    assign file_ready = ready_sent && !target_busy && !poisoned;
    assign bridge_rd_data = table_selected ? table_response_q : control_q;
    // Dedicated synchronous memory port; the small metadata bitmap avoids adding
    // an asynchronous second read of the table.
    always @(posedge clk) begin
        table_q <= slot_table[bridge_addr[11 : 2]];
        if (bridge_wr && bridge_addr[31 : 12] == 20'hF8002)
            slot_table[bridge_addr[11 : 2]] <= bridge_wr_data;
        // The serial peripheral consumes the PREVIOUS read response. The RAM
        // prefetch may follow a new address, but the published response must hold.
        if (bridge_rd) begin
            table_selected <= bridge_addr[31 : 12] == 20'hF8002;
            table_response_q <= table_q;
        end
    end
    always @(posedge clk) begin
        input_changed <= 0;
        source_changed <= 0;
        file_done <= 0;
        if (target_busy)
            trace_target <= target_status;
        if (trace_host_pending) begin
            trace_host_result <= host_status[15 : 0];
            trace_host_pending <= 0;
        end
        if (hstate == 1 && target_busy && hcommand != 0) begin
            trace_host_command <= hcommand;
            trace_host_param <= host_param[0];
            trace_host_pending <= 1;
        end
        if (bridge_rd) begin
            control_q <= 0;
            if (bridge_addr[31 : 24] == 8'hF8) begin
                case (bridge_addr[15 : 0])
                    16'h0000:
                        control_q <= host_status;
                    16'h0004:
                        control_q <= 32'h20;
                    16'h0008:
                        control_q <= 32'h40;
                    16'h0020, 16'h0024, 16'h0028, 16'h002C:
                        control_q <= host_param[bridge_addr[3 : 2]];
                    16'h0040, 16'h0044, 16'h0048, 16'h004C:
                        control_q <= host_response[bridge_addr[3 : 2]];
                    16'h1000:
                        control_q <= target_status;
                    16'h1004:
                        control_q <= 32'h20;
                    16'h1008:
                        control_q <= 32'h40;
                    16'h1020, 16'h1024, 16'h1028, 16'h102C:
                        control_q <= target_param[bridge_addr[3 : 2]];
                endcase
            end
        end
        if (bridge_wr && bridge_addr[31 : 24] == 8'hF8) begin
            if (bridge_addr[23 : 12] == 12'h002) begin
                if (bridge_addr[11 : 8] == 0) begin
                    if (!bridge_addr[2]) begin
                        if (input_entries[bridge_addr[7 : 3]] || bridge_wr_data[15 : 0] == 0) begin
                            source_changed[0] <= 1;
                            input_changed <= 1;
                            input_size <=
                                bridge_wr_data[15 : 0] == 0 ? entry_sizes[bridge_addr[7 : 3]] : 0;
                        end
                        if (record_entries[bridge_addr[7 : 3]] || bridge_wr_data[15 : 0] == 3) begin
                            source_changed[1] <= 1;
                            record_size <=
                                bridge_wr_data[15 : 0] == 3 ? entry_sizes[bridge_addr[7 : 3]] : 0;
                        end
                        if (target_entries[bridge_addr[7 : 3]] || bridge_wr_data[15 : 0] == 4) begin
                            source_changed[2] <= 1;
                            target_size <=
                                bridge_wr_data[15 : 0] == 4 ? entry_sizes[bridge_addr[7 : 3]] : 0;
                        end
                        target_entries[bridge_addr[7 : 3]] <= bridge_wr_data[15 : 0] == 4;
                        input_entries[bridge_addr[7 : 3]] <= bridge_wr_data[15 : 0] == 0;
                        record_entries[bridge_addr[7 : 3]] <= bridge_wr_data[15 : 0] == 3;
                    end else begin
                        entry_sizes[bridge_addr[7 : 3]] <= bridge_wr_data;
                        if (input_entries[bridge_addr[7 : 3]]) begin
                            input_size <= bridge_wr_data;
                            source_changed[0] <= 1;
                            input_changed <= 1;
                        end
                        if (target_entries[bridge_addr[7 : 3]]) begin
                            target_size <= bridge_wr_data;
                            source_changed[2] <= 1;
                        end
                        if (record_entries[bridge_addr[7 : 3]]) begin
                            record_size <= bridge_wr_data;
                            source_changed[1] <= 1;
                        end
                    end
                end
            end else
                case (bridge_addr[15 : 0])
                    16'h0000:
                        if (bridge_wr_data[31 : 16] == 16'h434D && hstate == 0) begin
                            host_status <= {16'h4255, bridge_wr_data[15 : 0]};
                            hcommand <= bridge_wr_data[15 : 0];
                            hstate <= 1;
                        end
                    16'h0020, 16'h0024, 16'h0028, 16'h002C:
                        host_param[bridge_addr[3 : 2]] <= bridge_wr_data;
                    16'h1000:
                        target_status <= bridge_wr_data;
                endcase
        end
        if (hstate == 1) begin
            hstate <= 0;
            host_status <= 32'h4F4B0000;
            case (hcommand)
                16'h0000:
                    host_status <= {16'h4F4B, (boot_ready ? (reset_n ? 16'd4 : 16'd3) : 16'd1)};
                16'h0010:
                    if (mutation_lock)
                        host_status <= 32'h4F4B0001;
                    else
                        reset_n <= 0;
                16'h0011:
                    reset_n <= 1;
                16'h0080:
                    host_status <= 32'h4F4B0001; // no automatic unload/save
                16'h0082:
                    host_status <= {16'h4F4B, ((target_busy || app_busy) ? 16'd2 : 16'd0)};
                16'h008A:
                    if (host_param[0][15 : 0] == 0) begin
                        input_size <= host_param[1];
                        input_changed <= 1;
                        source_changed[0] <= 1;
                    end else if (host_param[0][15 : 0] == 3) begin
                        record_size <= host_param[1];
                        source_changed[1] <= 1;
                    end else if (host_param[0][15 : 0] == 4) begin
                        target_size <= host_param[1];
                        source_changed[2] <= 1;
                    end
                16'h008F, 16'h0090, 16'h00B2: begin
                end
                16'h00A0, 16'h00A4: begin
                    host_response[0] <= 0;
                    host_response[1] <= 0;
                    host_response[2] <= 0;
                end
                16'h00B0:
                    in_menu <= host_param[0][0];
                16'h00B1:
                    cart_powered <= host_param[0][16];
                16'h00B8:
                    host_response[0] <= 32'h444D;
                default:
                    host_status <= 32'h4F4BFFFF;
            endcase
        end
        // Reset commands intentionally do NOT reset this channel while an OS write
        // is outstanding. A timed-out channel is poisoned until FPGA reload, so a
        // late completion cannot be mistaken for another transfer.
        if (!target_busy && !poisoned) begin
            if (boot_ready && !ready_sent) begin
                target_status <= 32'h636D0140;
                target_busy <= 1;
                target_is_file <= 0;
                timeout_count <= 0;
            end else if (file_request && file_ready) begin
                trace_target <= 0;
                trace_host_param <= 0;
                trace_host_command <= 0;
                trace_host_result <= 0;
                trace_host_pending <= 0;
                target_status <= {16'h636D, file_command};
                target_param[0] <= {16'b0, file_slot};
                target_param[1] <= file_offset;
                target_param[2] <= file_address;
                target_param[3] <= file_length;
                target_busy <= 1;
                target_is_file <= 1;
                timeout_count <= 0;
            end
        end else if (target_busy) begin
            timeout_count <= timeout_count + 1;
            if (target_status[31 : 16] == 16'h6F6B) begin
                target_busy <= 0;
                if (target_is_file) begin
                    file_done <= 1;
                    file_result <= target_status[15 : 0];
                end else
                    ready_sent <= 1;
            end else if (timeout_count == TIMEOUT_TICKS - 1) begin
                target_busy <= 0;
                poisoned <= 1;
                if (target_is_file) begin
                    file_done <= 1;
                    file_result <= 16'hFFFF;
                end
            end
        end
    end
endmodule
