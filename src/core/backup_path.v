`timescale 1ns / 1ps
`default_nettype none
module backup_path
    (input wire is_save, report_path,
     input wire [15 : 0] digits,
     input wire [7 : 0] index,
     output reg [7 : 0] value);
    localparam [207 : 0] PREFIX = "/Saves/pocketflash/common/";
    reg [31 : 0] name;
    reg [23 : 0] extension;
    integer position;
    always @* begin
        name = is_save ? "save" : "rom ";
        extension = is_save ? (report_path ? "pfs" : "sav") : (report_path ? "pfr" : "gba");
        position = index - 26 - (is_save ? 4 : 3);
        value = 0;
        if (index < 26)
            value = PREFIX[(25 - index) * 8 +: 8];
        else if (index < 26 + (is_save ? 4 : 3))
            value = name[(3 - (index - 26)) * 8 +: 8];
        else
            case (position)
                0:
                    value = 48 + digits[15 : 12];
                1:
                    value = 48 + digits[11 : 8];
                2:
                    value = 48 + digits[7 : 4];
                3:
                    value = 48 + digits[3 : 0];
                4:
                    value = ".";
                5, 6, 7:
                    value = extension[(7 - position) * 8 +: 8];
                default:
                    value = 0;
            endcase
    end
endmodule
