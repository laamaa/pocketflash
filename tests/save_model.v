// Pin-level model of the supported 128 KiB flash-save/CPLD interface.
// Every accepted write must be part of a nonpersistent command sequence.
`timescale 1ns / 1ps
module save_model
    #(parameter ID = 16'hC209)
    (input wire clk, cs2_n, rd_n, wr_n, data_drive,
     input wire [15 : 0] address,
     input wire [7 : 0] data_out,
     output wire [7 : 0] data_in);
    reg [7 : 0] memory[0 : 131071];
    reg bank = 0, id_mode = 0;
    integer phase = 0, writes = 0, i;
    reg previous_wr = 1;
    initial
        for (i = 0; i < 131072; i = i + 1)
            memory[i] = (i ^ (i >> 8) ^ (i >> 16) * 8'hA5) & 255;
    assign data_in =
               (!cs2_n && !rd_n && !data_drive)
                   ? (id_mode ? (address[0] ? ID[7 : 0] : ID[15 : 8]) : memory[{bank, address}])
                   : 8'hzz;
    always @(posedge clk) begin
        previous_wr <= wr_n;
        if (!cs2_n && !rd_n && (data_drive || !wr_n))
            $fatal(1, "save bus read contention");
        if (!previous_wr && wr_n && !cs2_n) begin
            if (!data_drive || !rd_n)
                $fatal(1, "save write direction");
            writes = writes + 1;
            if (phase == 3) begin
                if (address != 0 || data_out > 1)
                    $fatal(1, "save bank address/value");
                bank = data_out[0];
                phase = 0;
            end else if (data_out == 8'hF0) begin
                id_mode = 0;
                phase = 0;
            end else
                case (phase)
                    0:
                        if (address == 16'h5555 && data_out == 8'hAA)
                            phase = 1;
                        else
                            $fatal(1, "save unlock1");
                    1:
                        if (address == 16'h2AAA && data_out == 8'h55)
                            phase = 2;
                        else
                            $fatal(1, "save unlock2");
                    2:
                        if (address == 16'h5555 && data_out == 8'h90) begin
                            id_mode = 1;
                            phase = 0;
                        end else if (address == 16'h5555 && data_out == 8'hB0)
                            phase = 3;
                        else
                            $fatal(1, "persistent/unknown save command %h at %h", data_out,
                                   address);
                endcase
        end
    end
endmodule
