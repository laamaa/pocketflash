// PocketFlash. Top-level interface follows the Analogue core template.
`timescale 1ns / 1ps
`default_nettype none

module core_top
    (

        //
        // physical connections
        //

        ///////////////////////////////////////////////////
        // clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

        input wire clk_74a,
        // mainclk1
        input wire clk_74b,
        // mainclk1

        ///////////////////////////////////////////////////
        // cartridge interface
        // switches between 3.3v and 5v mechanically
        // output enable for multibit translators controlled by pic32

        // GBA AD[15:8]
        inout wire [7 : 0] cart_tran_bank2,
        output wire cart_tran_bank2_dir,

        // GBA AD[7:0]
        inout wire [7 : 0] cart_tran_bank3,
        output wire cart_tran_bank3_dir,

        // GBA A[23:16]
        inout wire [7 : 0] cart_tran_bank1,
        output wire cart_tran_bank1_dir,

        // GBA [7] PHI#
        // GBA [6] WR#
        // GBA [5] RD#
        // GBA [4] CS1#/CS#
        //     [3:0] unwired
        inout wire [7 : 4] cart_tran_bank0,
        output wire cart_tran_bank0_dir,

        // GBA CS2#/RES#
        inout wire cart_tran_pin30,
        output wire cart_tran_pin30_dir,
        // when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
        // the goal is that when unconfigured, the FPGA weak pullups won't interfere.
        // thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
        // and general IO drive this pin.
        output wire cart_pin30_pwroff_reset,

        // GBA IRQ/DRQ
        inout wire cart_tran_pin31,
        output wire cart_tran_pin31_dir,

        // infrared
        input wire port_ir_rx,
        output wire port_ir_tx,
        output wire port_ir_rx_disable,

        // GBA link port
        inout wire port_tran_si,
        output wire port_tran_si_dir,
        inout wire port_tran_so,
        output wire port_tran_so_dir,
        inout wire port_tran_sck,
        output wire port_tran_sck_dir,
        inout wire port_tran_sd,
        output wire port_tran_sd_dir,

        ///////////////////////////////////////////////////
        // cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

        output wire [21 : 16] cram0_a,
        inout wire [15 : 0] cram0_dq,
        input wire cram0_wait,
        output wire cram0_clk,
        output wire cram0_adv_n,
        output wire cram0_cre,
        output wire cram0_ce0_n,
        output wire cram0_ce1_n,
        output wire cram0_oe_n,
        output wire cram0_we_n,
        output wire cram0_ub_n,
        output wire cram0_lb_n,

        output wire [21 : 16] cram1_a,
        inout wire [15 : 0] cram1_dq,
        input wire cram1_wait,
        output wire cram1_clk,
        output wire cram1_adv_n,
        output wire cram1_cre,
        output wire cram1_ce0_n,
        output wire cram1_ce1_n,
        output wire cram1_oe_n,
        output wire cram1_we_n,
        output wire cram1_ub_n,
        output wire cram1_lb_n,

        ///////////////////////////////////////////////////
        // sdram, 512mbit 16bit

        output wire [12 : 0] dram_a,
        output wire [1 : 0] dram_ba,
        inout wire [15 : 0] dram_dq,
        output wire [1 : 0] dram_dqm,
        output wire dram_clk,
        output wire dram_cke,
        output wire dram_ras_n,
        output wire dram_cas_n,
        output wire dram_we_n,

        ///////////////////////////////////////////////////
        // sram, 1mbit 16bit

        output wire [16 : 0] sram_a,
        inout wire [15 : 0] sram_dq,
        output wire sram_oe_n,
        output wire sram_we_n,
        output wire sram_ub_n,
        output wire sram_lb_n,

        ///////////////////////////////////////////////////
        // vblank driven by dock for sync in a certain mode

        input wire vblank,

        ///////////////////////////////////////////////////
        // i/o to 6515D breakout usb uart

        output wire dbg_tx,
        input wire dbg_rx,

        ///////////////////////////////////////////////////
        // i/o pads near jtag connector user can solder to

        output wire user1,
        input wire user2,

        ///////////////////////////////////////////////////
        // RFU internal i2c bus

        inout wire aux_sda,
        output wire aux_scl,

        ///////////////////////////////////////////////////
        // RFU, do not use
        output wire vpll_feed,

        //
        // logical connections
        //

        ///////////////////////////////////////////////////
        // video, audio output to scaler
        output wire [23 : 0] video_rgb,
        output wire video_rgb_clock,
        output wire video_rgb_clock_90,
        output wire video_de,
        output wire video_skip,
        output wire video_vs,
        output wire video_hs,

        output wire audio_mclk,
        input wire audio_adc,
        output wire audio_dac,
        output wire audio_lrck,

        ///////////////////////////////////////////////////
        // bridge bus connection
        // synchronous to clk_74a
        output wire bridge_endian_little,
        input wire [31 : 0] bridge_addr,
        input wire bridge_rd,
        output reg [31 : 0] bridge_rd_data,
        input wire bridge_wr,
        input wire [31 : 0] bridge_wr_data,

        ///////////////////////////////////////////////////
        // controller data
        //
        // key bitmap:
        //   [0]    dpad_up
        //   [1]    dpad_down
        //   [2]    dpad_left
        //   [3]    dpad_right
        //   [4]    face_a
        //   [5]    face_b
        //   [6]    face_x
        //   [7]    face_y
        //   [8]    trig_l1
        //   [9]    trig_r1
        //   [10]   trig_l2
        //   [11]   trig_r2
        //   [12]   trig_l3
        //   [13]   trig_r3
        //   [14]   face_select
        //   [15]   face_start
        //   [31:28] type
        // joy values - unsigned
        //   [ 7: 0] lstick_x
        //   [15: 8] lstick_y
        //   [23:16] rstick_x
        //   [31:24] rstick_y
        // trigger values - unsigned
        //   [ 7: 0] ltrig
        //   [15: 8] rtrig
        //
        input wire [31 : 0] cont1_key,
        input wire [31 : 0] cont2_key,
        input wire [31 : 0] cont3_key,
        input wire [31 : 0] cont4_key,
        input wire [31 : 0] cont1_joy,
        input wire [31 : 0] cont2_joy,
        input wire [31 : 0] cont3_joy,
        input wire [31 : 0] cont4_joy,
        input wire [15 : 0] cont1_trig,
        input wire [15 : 0] cont2_trig,
        input wire [15 : 0] cont3_trig,
        input wire [15 : 0] cont4_trig);

    // tie off the rest of the pins we are not using
    assign cram0_a = 'h0;
    assign cram0_dq = {16{1'bZ}};
    assign cram0_clk = 0;
    assign cram0_adv_n = 1;
    assign cram0_cre = 0;
    assign cram0_ce0_n = 1;
    assign cram0_ce1_n = 1;
    assign cram0_oe_n = 1;
    assign cram0_we_n = 1;
    assign cram0_ub_n = 1;
    assign cram0_lb_n = 1;

    assign cram1_a = 'h0;
    assign cram1_dq = {16{1'bZ}};
    assign cram1_clk = 0;
    assign cram1_adv_n = 1;
    assign cram1_cre = 0;
    assign cram1_ce0_n = 1;
    assign cram1_ce1_n = 1;
    assign cram1_oe_n = 1;
    assign cram1_we_n = 1;
    assign cram1_ub_n = 1;
    assign cram1_lb_n = 1;

    assign sram_a = 'h0;
    assign sram_dq = {16{1'bZ}};
    assign sram_oe_n = 1;
    assign sram_we_n = 1;
    assign sram_ub_n = 1;
    assign sram_lb_n = 1;

    assign dbg_tx = 1'bZ;
    assign user1 = 1'bZ;
    assign aux_scl = 1'bZ;
    assign vpll_feed = 1'bZ;

    assign port_ir_tx = 0;
    assign port_ir_rx_disable = 1;
    assign bridge_endian_little = 0;
    assign port_tran_si = 1'bz;
    assign port_tran_si_dir = 0;
    assign port_tran_so = 1'bz;
    assign port_tran_so_dir = 0;
    assign port_tran_sck = 1'bz;
    assign port_tran_sck_dir = 0;
    assign port_tran_sd = 1'bz;
    assign port_tran_sd_dir = 0;
    assign aux_sda = 1'bz;
    assign audio_mclk = 0;
    assign audio_dac = 0;
    assign audio_lrck = 0;
    assign video_skip = 0;
    assign dram_a = 0;
    assign dram_ba = 0;
    assign dram_dq = 16'hzzzz;
    assign dram_dqm = 2'b11;
    assign dram_clk = 0;
    assign dram_cke = 0;
    assign dram_ras_n = 1;
    assign dram_cas_n = 1;
    assign dram_we_n = 1;

    // Single utility: no alternate menus or cartridge owners exist in this top level.
    wire reset_n, in_menu, cart_powered, pll_locked, pixel_clk, pixel_clk90;
    wire [31 : 0] command_q, target_size, ram_bridge_q;
    wire [2 : 0] source_changed;
    wire file_ready, file_done, file_poisoned;
    wire [15 : 0] file_result, ram_q;
    wire [23 : 0] utility_rgb;
    wire utility_de, utility_hs, utility_vs;
    wire utility_busy, utility_lock, utility_poison, utility_file_request, utility_ram_wr;
    wire [15 : 0] utility_file_command, utility_file_slot, utility_ram_offset, utility_ram_data;
    wire [31 : 0] utility_file_offset, utility_file_address, utility_file_length,
                  utility_open_flags, utility_open_size;
    wire [15 : 0] utility_ad;
    wire utility_ad_drive, utility_high_drive, utility_cs, utility_rd, utility_wr, utility_cs2;
    wire [7 : 0] utility_high;
    wire [2 : 0] utility_selection;
    wire utility_header_warning;
    wire utility_ack, utility_help, utility_details, utility_save, utility_report;
    wire [7 : 0] utility_status, utility_error, utility_phase;
    wire [31 : 0] utility_progress, utility_seconds, utility_crc, utility_buffers;
    wire [8 : 0] utility_erases;
    wire [24 : 0] utility_error_address;
    wire [15 : 0] utility_expected, utility_observed, utility_save_id;
    wire [13 : 0] utility_number;
    wire [15 : 0] utility_digits;
    wire [1 : 0] utility_rom_state;
    wire utility_error_is_flash, utility_known, utility_read_mode;
    wire [15 : 0] utility_rom_manufacturer, utility_rom_device, utility_raw_status;

    apf_command commands(.clk(clk_74a),
                         .boot_ready(pll_locked),
                         .app_busy(utility_busy),
                         .mutation_lock(utility_lock),
                         .bridge_addr(bridge_addr),
                         .bridge_wr_data(bridge_wr_data),
                         .bridge_wr(bridge_wr),
                         .bridge_rd(bridge_rd),
                         .bridge_rd_data(command_q),
                         .reset_n(reset_n),
                         .in_menu(in_menu),
                         .cart_powered(cart_powered),
                         .input_size(),
                         .input_changed(),
                         .record_size(),
                         .target_size(target_size),
                         .source_changed(source_changed),
                         .file_request(utility_file_request),
                         .file_command(utility_file_command),
                         .file_slot(utility_file_slot),
                         .file_offset(utility_file_offset),
                         .file_address(utility_file_address),
                         .file_length(utility_file_length),
                         .file_ready(file_ready),
                         .file_done(file_done),
                         .file_result(file_result),
                         .file_poisoned(file_poisoned),
                         .trace_target(),
                         .trace_host_param(),
                         .trace_host_command(),
                         .trace_host_result());
    transfer_ram buffer(.clk(clk_74a),
                        .bridge_wr(bridge_wr && bridge_addr[31 : 16] == 16'h1000),
                        .bridge_rd(bridge_rd && bridge_addr[31 : 16] == 16'h1000),
                        .bridge_offset(bridge_addr[15 : 0]),
                        .bridge_data(bridge_wr_data),
                        .bridge_q(ram_bridge_q),
                        .engine_wr(utility_ram_wr),
                        .engine_offset(utility_ram_offset),
                        .engine_data(utility_ram_data),
                        .engine_q(ram_q));

    assign cart_tran_bank2 = utility_ad_drive ? utility_ad[15 : 8] : 8'hzz;
    assign cart_tran_bank3 = utility_ad_drive ? utility_ad[7 : 0] : 8'hzz;
    assign cart_tran_bank2_dir = utility_ad_drive;
    assign cart_tran_bank3_dir = utility_ad_drive;
    assign cart_tran_bank1 = utility_high_drive ? utility_high : 8'hzz;
    assign cart_tran_bank1_dir = utility_high_drive;
    assign cart_tran_bank0 = {1'b0, utility_wr, utility_rd, utility_cs};
    assign cart_tran_bank0_dir = 1;
    assign cart_tran_pin30 = utility_cs2;
    assign cart_tran_pin30_dir = 1;
    assign cart_pin30_pwroff_reset = 0;
    assign cart_tran_pin31 = 1'bz;
    assign cart_tran_pin31_dir = 0;

    wire [31 : 0] utility_path_word;
    genvar path_lane;
    generate
        for (path_lane = 0; path_lane < 4; path_lane = path_lane + 1) begin : utility_paths
            wire [7 : 0] byte_index = bridge_addr[7 : 0] + path_lane;
            backup_path path(.is_save(utility_save),
                             .report_path(utility_report),
                             .digits(utility_digits),
                             .index(byte_index),
                             .value(utility_path_word[(3 - path_lane) * 8 +: 8]));
        end
    endgenerate

    // APF open struct: path[256], flags, size; control words are big-endian.
    reg [31 : 0] struct_q;
    reg [1 : 0] rd_region = 0;
    always @(posedge clk_74a)
        if (bridge_rd) begin
            if (bridge_addr[31 : 24] == 8'hF8)
                rd_region <= 0;
            else if (bridge_addr[31 : 16] == 16'h1000)
                rd_region <= 1;
            else begin
                rd_region <= 2;
                struct_q <= 0;
                if (bridge_addr[31 : 16] == 16'h1001) begin
                    if (bridge_addr[15 : 0] < 256)
                        struct_q <= utility_path_word;
                    else if (bridge_addr[15 : 0] == 256)
                        struct_q <= utility_open_flags;
                    else if (bridge_addr[15 : 0] == 260)
                        struct_q <= utility_open_size;
                end
            end
        end
    always @*
        case (rd_region)
            0:
                bridge_rd_data = command_q;
            1:
                bridge_rd_data = ram_bridge_q;
            default:
                bridge_rd_data = struct_q;
        endcase
    video_pll pll(.clk(clk_74a),
                  .pixel_clk(pixel_clk),
                  .pixel_clk90(pixel_clk90),
                  .locked(pll_locked));
    assign video_rgb_clock = pixel_clk;
    assign video_rgb_clock_90 = pixel_clk90;
    // APF app reset must not clear transport poison or stop an accepted mutation.
    reg flash_started = 0;
    always @(posedge clk_74a) begin
        if (!pll_locked)
            flash_started <= 0;
        else if (reset_n)
            flash_started <= 1;
    end
    generate
        if (1) begin : public_mode
            pocketflash_utility utility(.clk(clk_74a),
                                        .core_reset_n(pll_locked && flash_started),
                                        .app_reset_n(reset_n),
                                        .in_menu(in_menu),
                                        .cart_powered(cart_powered),
                                        .keys(cont1_key[15 : 0]),
                                        .target_size(target_size),
                                        .target_changed(source_changed[2]),
                                        .file_poisoned(file_poisoned),
                                        .file_ready(file_ready),
                                        .file_done(file_done),
                                        .file_result(file_result),
                                        .ram_q(ram_q),
                                        .ad_in({cart_tran_bank2, cart_tran_bank3}),
                                        .save_data_in(cart_tran_bank1),
                                        .busy(utility_busy),
                                        .mutation_lock(utility_lock),
                                        .poisoned(utility_poison),
                                        .file_request(utility_file_request),
                                        .file_command(utility_file_command),
                                        .file_slot(utility_file_slot),
                                        .file_offset(utility_file_offset),
                                        .file_address(utility_file_address),
                                        .file_length(utility_file_length),
                                        .open_flags(utility_open_flags),
                                        .open_size(utility_open_size),
                                        .ram_wr(utility_ram_wr),
                                        .ram_offset(utility_ram_offset),
                                        .ram_data(utility_ram_data),
                                        .ad_out(utility_ad),
                                        .ad_drive(utility_ad_drive),
                                        .high_drive(utility_high_drive),
                                        .high_out(utility_high),
                                        .cs_n(utility_cs),
                                        .rd_n(utility_rd),
                                        .wr_n(utility_wr),
                                        .cs2_n(utility_cs2),
                                        .selection(utility_selection),
                                        .acknowledge(utility_ack),
                                        .help(utility_help),
                                        .details(utility_details),
                                        .header_warning(utility_header_warning),
                                        .status(utility_status),
                                        .error_code(utility_error),
                                        .progress(utility_progress),
                                        .image_crc(utility_crc),
                                        .programmed_buffers(utility_buffers),
                                        .seconds(utility_seconds),
                                        .erased_sectors(utility_erases),
                                        .error_address(utility_error_address),
                                        .expected(utility_expected),
                                        .observed(utility_observed),
                                        .output_number(utility_number),
                                        .output_digits(utility_digits),
                                        .rom_state(utility_rom_state),
                                        .error_is_flash(utility_error_is_flash),
                                        .rom_manufacturer(utility_rom_manufacturer),
                                        .rom_device(utility_rom_device),
                                        .raw_flash_status(utility_raw_status),
                                        .completion_known(utility_known),
                                        .read_mode(utility_read_mode),
                                        .output_save(utility_save),
                                        .report_path(utility_report),
                                        .phase(utility_phase),
                                        .save_identity(utility_save_id));
            utility_video utility_display(.clk(pixel_clk),
                                          .reset_n(pll_locked),
                                          .selection(utility_selection),
                                          .acknowledge(utility_ack),
                                          .help(utility_help),
                                          .details(utility_details),
                                          .header_warning(utility_header_warning),
                                          .poisoned(utility_poison),
                                          .output_save(utility_save),
                                          .status(utility_status),
                                          .error_code(utility_error),
                                          .phase(utility_phase),
                                          .progress(utility_progress),
                                          .seconds(utility_seconds),
                                          .image_crc(utility_crc),
                                          .programmed_buffers(utility_buffers),
                                          .target_size(target_size),
                                          .erased_sectors(utility_erases),
                                          .error_address(utility_error_address),
                                          .expected(utility_expected),
                                          .observed(utility_observed),
                                          .save_identity(utility_save_id),
                                          .output_number(utility_number),
                                          .rom_state(utility_rom_state),
                                          .error_is_flash(utility_error_is_flash),
                                          .rom_manufacturer(utility_rom_manufacturer),
                                          .rom_device(utility_rom_device),
                                          .raw_flash_status(utility_raw_status),
                                          .completion_known(utility_known),
                                          .read_mode(utility_read_mode),
                                          .rgb(utility_rgb),
                                          .de(utility_de),
                                          .hs(utility_hs),
                                          .vs(utility_vs));
        end
    endgenerate
    assign video_rgb = utility_rgb;
    assign video_de = utility_de;
    assign video_hs = utility_hs;
    assign video_vs = utility_vs;
endmodule
