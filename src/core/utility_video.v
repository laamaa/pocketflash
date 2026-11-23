// Text-only public dashboard. Frame snapshots are display-only.
`timescale 1ns / 1ps
`default_nettype none
module utility_video
    (input wire clk, reset_n,
     input wire [2 : 0] selection,
     input wire acknowledge, help, details, poisoned, output_save, header_warning,
     input wire [7 : 0] status, error_code, phase,
     input wire [31 : 0] progress, seconds, image_crc, programmed_buffers, target_size,
     input wire [8 : 0] erased_sectors,
     input wire [24 : 0] error_address,
     input wire [15 : 0] expected, observed, save_identity,
     input wire [13 : 0] output_number,
     input wire [1 : 0] rom_state,
     input wire error_is_flash, completion_known, read_mode,
     input wire [15 : 0] rom_manufacturer, rom_device, raw_flash_status,
     output wire [23 : 0] rgb,
     output wire de, hs, vs);
    reg [8 : 0] x = 0, y = 0;
    reg [2 : 0] selected = 0;
    reg [1 : 0] rom_frame = 0;
    reg flash_error_frame = 0, known_frame = 0, read_frame = 0;
    reg [15 : 0] manufacturer_frame = 0, device_frame = 0, raw_status_frame = 0;
    reg warning_frame = 0;
    reg ack = 0, help_frame = 0, detail = 0, poison = 0, save = 0;
    reg [7 : 0] result = 0, code = 0, phase_frame = 0;
    reg [31 : 0] bytes_frame = 0, elapsed = 0, crc_frame = 0, size_frame = 0, count_frame = 0;
    reg [8 : 0] erases_frame = 0;
    reg [24 : 0] address_frame = 0;
    reg [15 : 0] expected_frame = 0, observed_frame = 0, id_frame = 0;
    reg [13 : 0] number_frame = 1;
    always @(posedge clk) begin
        if (!reset_n) begin
            x <= 0;
            y <= 0;
        end else if (x == 399) begin
            x <= 0;
            y <= y == 309 ? 0 : y + 1'b1;
        end else
            x <= x + 1'b1;
        if (x == 399 && y == 309) begin
            rom_frame <= rom_state;
            flash_error_frame <= error_is_flash;
            known_frame <= completion_known;
            read_frame <= read_mode;
            manufacturer_frame <= rom_manufacturer;
            device_frame <= rom_device;
            raw_status_frame <= raw_flash_status;
            warning_frame <= header_warning;
            selected <= selection;
            ack <= acknowledge;
            help_frame <= help;
            detail <= details;
            poison <= poisoned;
            save <= output_save;
            result <= status;
            code <= error_code;
            phase_frame <= phase;
            bytes_frame <= progress;
            elapsed <= seconds;
            crc_frame <= image_crc;
            size_frame <= target_size;
            count_frame <= programmed_buffers;
            erases_frame <= erased_sectors;
            address_frame <= error_address;
            expected_frame <= expected;
            observed_frame <= observed;
            id_frame <= save_identity;
            number_frame <= output_number;
        end
    end
    assign de = x < 320 && y < 240;
    assign hs = x >= 336 && x < 368;
    assign vs = y >= 242 && y < 245;
    wire [5 : 0] col = x[8 : 3];
    wire [4 : 0] row = y[7 : 3];
    reg [319 : 0] line;
    reg [7 : 0] ch;
    function [7 : 0] hexchar
        (input [3 : 0] n);
        begin
            hexchar = n < 10 ? 48 + n : 55 + n;
        end
    endfunction
    function [7 : 0] decimalchar
        (input [39 : 0] digits,
         input integer place);
        begin
            decimalchar =
                place > 0 && (digits >> (place * 4)) == 0 ? " " : 48 + digits[place * 4 +: 4];
        end
    endfunction
    function [34 : 0] glyph;
        input [7 : 0] c;
        begin
            case (c)
                8'h41:
                    glyph = 35'b01110100011000111111100011000110001;
                8'h42:
                    glyph = 35'b11110100011000111110100011000111110;
                8'h43:
                    glyph = 35'b01111100001000010000100001000001111;
                8'h44:
                    glyph = 35'b11110100011000110001100011000111110;
                8'h45:
                    glyph = 35'b11111100001000011110100001000011111;
                8'h46:
                    glyph = 35'b11111100001000011110100001000010000;
                8'h47:
                    glyph = 35'b01111100001000010111100011000101111;
                8'h48:
                    glyph = 35'b10001100011000111111100011000110001;
                8'h49:
                    glyph = 35'b11111001000010000100001000010011111;
                8'h4A:
                    glyph = 35'b00111000100001000010100101001001100;
                8'h4B:
                    glyph = 35'b10001100101010011000101001001010001;
                8'h4C:
                    glyph = 35'b10000100001000010000100001000011111;
                8'h4D:
                    glyph = 35'b10001110111010110101100011000110001;
                8'h4E:
                    glyph = 35'b10001110011010110011100011000110001;
                8'h4F:
                    glyph = 35'b01110100011000110001100011000101110;
                8'h50:
                    glyph = 35'b11110100011000111110100001000010000;
                8'h51:
                    glyph = 35'b01110100011000110001101011001001101;
                8'h52:
                    glyph = 35'b11110100011000111110101001001010001;
                8'h53:
                    glyph = 35'b01111100001000001110000010000111110;
                8'h54:
                    glyph = 35'b11111001000010000100001000010000100;
                8'h55:
                    glyph = 35'b10001100011000110001100011000101110;
                8'h56:
                    glyph = 35'b10001100011000110001100010101000100;
                8'h57:
                    glyph = 35'b10001100011000110101101011010101010;
                8'h58:
                    glyph = 35'b10001100010101000100010101000110001;
                8'h59:
                    glyph = 35'b10001100010101000100001000010000100;
                8'h5A:
                    glyph = 35'b11111000010001000100010001000011111;
                8'h30:
                    glyph = 35'b01110100011001110101110011000101110;
                8'h31:
                    glyph = 35'b00100011000010000100001000010001110;
                8'h32:
                    glyph = 35'b01110100010000100010001000100011111;
                8'h33:
                    glyph = 35'b11110000010000101110000010000111110;
                8'h34:
                    glyph = 35'b00010001100101010010111110001000010;
                8'h35:
                    glyph = 35'b11111100001000011110000010000111110;
                8'h36:
                    glyph = 35'b01110100001000011110100011000101110;
                8'h37:
                    glyph = 35'b11111000010001000100010000100001000;
                8'h38:
                    glyph = 35'b01110100011000101110100011000101110;
                8'h39:
                    glyph = 35'b01110100011000101111000010000101110;
                8'h3A:
                    glyph = 35'b00000001000010000000001000010000000;
                8'h2E:
                    glyph = 35'b00000000000000000000000000010000100;
                8'h2F:
                    glyph = 35'b00001000010001000100010001000010000;
                8'h2D:
                    glyph = 35'b00000000000000011111000000000000000;
                8'h3E:
                    glyph = 35'b10000010000010000010001000100010000;
                8'h3D:
                    glyph = 35'b00000000001111100000111110000000000;
                8'h25:
                    glyph = 35'b11001110100010001000101100011000000;
                default:
                    glyph = 0;
            endcase
        end
    endfunction
    wire [31 : 0] percentage = (bytes_frame * 32'd100) >> (save ? 17 : 25);
    wire [39 : 0] percent_bcd;
    binary_decimal percent_decimal(.clk(clk),
                                   .value(percentage),
                                   .digits(percent_bcd));
    integer i;
    wire [39 : 0] bytes_bcd;
    binary_decimal bytes_decimal(.clk(clk),
                                 .value(bytes_frame),
                                 .digits(bytes_bcd));
    wire [39 : 0] seconds_bcd;
    binary_decimal seconds_decimal(.clk(clk),
                                   .value(elapsed),
                                   .digits(seconds_bcd));
    wire [39 : 0] size_bcd;
    binary_decimal size_decimal(.clk(clk),
                                .value(size_frame),
                                .digits(size_bcd));
    wire [39 : 0] erases_bcd;
    binary_decimal erases_decimal(.clk(clk),
                                  .value({23'b0, erases_frame}),
                                  .digits(erases_bcd));
    wire [39 : 0] count_bcd;
    binary_decimal count_decimal(.clk(clk),
                                 .value(count_frame),
                                 .digits(count_bcd));
    wire [39 : 0] name_bcd;
    binary_decimal name_decimal(.clk(clk),
                                .value({18'b0, number_frame}),
                                .digits(name_bcd));
    always @* begin
        i = 0;
        line = "                                        ";
        case (row)
            0:
                line = "POCKETFLASH 0.2.0-BETA.1                ";
            2:
                line = "GL-S 32 MIB / 128 KIB SAVE PROFILE      ";
            4:
                line = "  BACKUP ROM                            ";
            5:
                line = "  BACKUP SAVES                          ";
            6:
                line = "  FLASH ROM                             ";
            7:
                line = "  VERIFY ROM                            ";
            8:
                line = "  HELP                                  ";
            10:
                line = "READY                                   ";
            12:
                line = "BYTES:                                  ";
            13:
                line = "TIME:            S                      ";
            14:
                line = "IMAGE:           B                      ";
            15:
                line = "ERASES:         BUFFERS:                ";
            17:
                line = "OUTPUT:                                 ";
            19:
                line = "                                        ";
            22:
                line = "A SELECT   B BACK / CANCEL              ";
            23:
                line = "X DETAILS                               ";
        endcase
        if (row >= 4 && row <= 8 && row == selected + 4)
            line[319 -: 8] = ">";
        if (row == 10)
            case (result)
                1:
                    line = "FINDING UNUSED BACKUP NAME              ";
                2:
                    line = "READING CARTRIDGE                       ";
                3:
                    line = "CHECKING SELECTED ROM                   ";
                4:
                    line = "RELEASE A THEN HOLD A TWO SECONDS       ";
                5:
                    line = "FLASHING - B STOPS AFTER SECTOR         ";
                6:
                    line = "VERIFYING EVERY BYTE                    ";
                7:
                    line = "FINISHING AND RELEASING CARTRIDGE       ";
                8:
                    line = "BACKUP VERIFIED                         ";
                9:
                    line = "ROM VERIFIED                            ";
                255:
                    line = "OPERATION STOPPED - SEE BELOW           ";
            endcase
        if (row == 12)
            for (i = 0; i < 8; i = i + 1)
                line[319 - (8 + i) * 8 -: 8] = decimalchar(bytes_bcd, 7 - i);
        if (row == 12) begin
            for (i = 0; i < 3; i = i + 1)
                line[319 - (25 + i) * 8 -: 8] = decimalchar(percent_bcd, 2 - i);
            line[319 - 28 * 8 -: 8] = "%";
        end
        if (row == 13)
            for (i = 0; i < 8; i = i + 1)
                line[319 - (8 + i) * 8 -: 8] = decimalchar(seconds_bcd, 7 - i);
        if (row == 14)
            for (i = 0; i < 8; i = i + 1)
                line[319 - (8 + i) * 8 -: 8] = decimalchar(size_bcd, 7 - i);
        if (row == 15) begin
            for (i = 0; i < 3; i = i + 1)
                line[319 - (8 + i) * 8 -: 8] = decimalchar(erases_bcd, 2 - i);
            for (i = 0; i < 5; i = i + 1)
                line[319 - (25 + i) * 8 -: 8] = decimalchar(count_bcd, 4 - i);
        end
        if (row == 17) begin
            line = save ? "OUTPUT: SAVE0001.SAV / .PFS             "
                        : "OUTPUT: ROM0001.GBA / .PFR              ";
            for (i = 0; i < 4; i = i + 1)
                line[319 - ((save ? 12 : 11) + i) * 8 -: 8] = 48 + name_bcd[(3 - i) * 4 +: 4];
        end
        // Keep normal screens focused on the current action. Detailed diagnostics
        // remain available below through X; incomplete-ROM warnings stay persistent.
        if (result == 0 && (row == 12 || row == 13))
            line = {40{8'h20}};
        if (row == 14 &&
            (save || size_frame == 0 || (selected != 2 && selected != 3 && !flash_error_frame)))
            line = {40{8'h20}};
        if (row == 15 && (!flash_error_frame || result == 0))
            line = {40{8'h20}};
        if (row == 17 &&
            (result == 0 || flash_error_frame || (selected >= 2 && !save && result != 8) || ack))
            line = {40{8'h20}};
        if (warning_frame && row == 20)
            line = "WARNING: GBA HEADER IS INVALID          ";
        if (ack) begin
            if (row == 10)
                line = "FLASH WILL REPLACE THE ENTIRE ROM       ";
            if (row == 12)
                line = "I HAVE MANAGED MY OWN BACKUPS           ";
            if (row == 13)
                line = "I ACCEPT THE RISK OF LOSING THE ROM     ";
            if (row == 15)
                line = "A ACKNOWLEDGE AND CHECK IMAGE           ";
            if (row == 16)
                line = "B BACK                                  ";
        end
        if (help_frame) begin
            if (row == 10)
                line = "BACK UP ROM AND SAVES BEFORE FLASHING   ";
            if (row == 12)
                line = "SELECT A GBA FILE IN POCKET MENU        ";
            if (row == 13)
                line = "FLASH ROM: ACKNOWLEDGE THEN HOLD A      ";
            if (row == 14)
                line = "VERIFY ROM: COMPARE WITH SELECTED FILE  ";
            if (row == 15)
                line = "BACKUPS: SAVES/POCKETFLASH/COMMON       ";
            if (row == 17)
                line = "B CANCELS AT A SAFE BOUNDARY            ";
            if (row == 18)
                line = "SAVE BACKUP ONLY - NO SAVE RESTORE      ";
            if (row == 19)
                line = "POWER OFF BEFORE CHANGING CARTRIDGES    ";
            if (row == 20)
                line = "SEE INCLUDED GUIDE FOR RECOVERY         ";
        end
        if (result == 255) begin
            if (row == 19)
                case (code)
                    1:
                        line = "CHECK CARTRIDGE POWER                   ";
                    2:
                        line = "SELECT 192 BYTE TO 32 MIB GBA FILE      ";
                    3:
                        line = "CARTRIDGE READ FAILED                   ";
                    4:
                        line = "BACKUP NAME EXISTS - TRY AGAIN          ";
                    5:
                        line = "SD ERROR - CHECK CARD AND FREE SPACE    ";
                    6:
                        line = "CANCELLED - BACKUP MAY BE PARTIAL       ";
                    7:
                        line = "ROM CHANGED - SELECT FILE AND RETRY     ";
                    8:
                        line = "VERIFY MISMATCH - CHECK DETAILS         ";
                    9:
                        line = "UNSUPPORTED FLASH PROFILE               ";
                    11:
                        line = "BACKUP CRC MISMATCH - RETRY             ";
                    12:
                        line = "BACKUP RECORD INVALID - RETRY           ";
                    14:
                        line = flash_error_frame ? "ERASE FAILED - REFLASH A KNOWN GOOD ROM "
                                                 : "NO FREE BACKUP NAMES 0001 TO 9999       ";
                    13:
                        line = "IMAGE OR CACHE CHECK FAILED - RETRY     ";
                    15:
                        line = "PROGRAM FAILED - REFLASH KNOWN GOOD ROM ";
                    16:
                        line = "POWER OFF AND RELOAD CORE               ";
                    17:
                        line = "POWER OFF AND RELOAD CORE               ";
                    default:
                        line = "ERROR - SEE GUIDE AND DETAILS           ";
                endcase
            if (row == 20 && rom_frame == 1)
                line = "ROM MAY BE INCOMPLETE - REFLASH FULL ROM";
        end
        if (poison && row == 19)
            line = "POWER OFF AND RELOAD BEFORE RETRY       ";
        if (row == 27 && rom_frame == 1)
            line = "ROM POSSIBLY INCOMPLETE - REFLASH       ";
        if (detail) begin
            if (row == 18) begin
                line = "FLASH STATUS:       KNOWN:   READ:      ";
                for (i = 0; i < 4; i = i + 1)
                    line[319 - (14 + i) * 8 -: 8] = hexchar(raw_status_frame[(3 - i) * 4 +: 4]);
                line[319 - 27 * 8 -: 8] = known_frame ? "1" : "0";
                line[319 - 35 * 8 -: 8] = read_frame ? "1" : "0";
            end
            if (row == 24)
                line = "CRC:          PHASE:       ERROR:       ";
            if (row == 25)
                line = "ADDRESS:         EXPECTED:      READ:   ";
            if (row == 26)
                line = "SAVE ID:                                ";
            if (row == 24) begin
                for (i = 0; i < 8; i = i + 1)
                    line[319 - (5 + i) * 8 -: 8] = hexchar(crc_frame[(7 - i) * 4 +: 4]);
                line[319 - 21 * 8 -: 8] = hexchar(phase_frame[7 : 4]);
                line[319 - 22 * 8 -: 8] = hexchar(phase_frame[3 : 0]);
                line[319 - 34 * 8 -: 8] = hexchar(code[7 : 4]);
                line[319 - 35 * 8 -: 8] = hexchar(code[3 : 0]);
            end
            if (row == 25) begin
                for (i = 0; i < 7; i = i + 1)
                    line[319 - (9 + i) * 8 -: 8] =
                        hexchar(({3'b0, address_frame} >> ((6 - i) * 4)) & 15);
                for (i = 0; i < 4; i = i + 1) begin
                    line[319 - (26 + i) * 8 -: 8] = hexchar(expected_frame[(3 - i) * 4 +: 4]);
                    line[319 - (36 + i) * 8 -: 8] = hexchar(observed_frame[(3 - i) * 4 +: 4]);
                end
            end
            if (row == 26) begin
                line = "SAVE ID:       ROM ID:                  ";
                for (i = 0; i < 4; i = i + 1) begin
                    line[319 - (9 + i) * 8 -: 8] = hexchar(id_frame[(3 - i) * 4 +: 4]);
                    line[319 - (23 + i) * 8 -: 8] = hexchar(manufacturer_frame[(3 - i) * 4 +: 4]);
                    line[319 - (28 + i) * 8 -: 8] = hexchar(device_frame[(3 - i) * 4 +: 4]);
                end
            end
        end
        ch = col < 40 ? line[(39 - col) * 8 +: 8] : 0;
    end
    wire [34 : 0] shape = glyph(ch);
    wire ink = x[2 : 0] < 5 && y[2 : 0] < 7 && shape[34 - y[2 : 0] * 5 - x[2 : 0]];
    // APF interprets RGB during blanking as frame/end-of-line control words.
    // Zero selects progressive output and scaler slot 0, as in status_video.
    assign rgb = !de ? 24'h000000 : ink ? (row == 0 ? 24'h48E8C8 : 24'hFFFFFF) : 24'h102C30;
endmodule
