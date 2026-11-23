`timescale 1ns/1ps
module tb_utility_video;
reg clk=0;always #5 clk=~clk;
reg reset_n=0;
reg [2:0] selection=0;
reg acknowledge=0,help=0,details=0,poisoned=0,output_save=0,header_warning=0;
reg [7:0] status=0,error_code=0,phase=0;
reg [31:0] progress=0,seconds=0,image_crc=32'h9CED7DC6,programmed_buffers=582,target_size=297964;
reg [8:0] erased_sectors=256;
reg [24:0] error_address=0;
reg [15:0] expected=0,observed=0,save_identity=16'hC209;
reg [13:0] output_number=1;
reg [1:0] rom_state=0;
reg error_is_flash=0,completion_known=0,read_mode=0;
reg [15:0] rom_manufacturer=1,rom_device=16'h227E,raw_flash_status=0;
wire [23:0] rgb;
wire de,hs,vs;
utility_video dut(.*);
integer f,x,y;
task check_percent(input [31:0] byte_count,input [31:0] text);
begin
 progress=byte_count;
 repeat(80) @(negedge clk);
 if(dut.line[319-25*8-:32]!==text)
  $fatal(1,"progress must be readable without leading zeros: got '%s', expected '%s'",dut.line[319-25*8-:32],text);
end endtask
always @(negedge clk) if(reset_n && !de && rgb!==24'h000000)
 $fatal(1,"nonzero RGB outside active pixels: %h",rgb);
task screenshot(input [255:0] path);
begin
 repeat(250000) @(negedge clk);
 wait(dut.x==0 && dut.y==0);
 f=$fopen(path,"w");if(!f) $fatal(1,"screenshot output");
 $fwrite(f,"P3\n320 240\n255\n");
 for(y=0;y<240;y=y+1) for(x=0;x<400;x=x+1) begin
  if(x<320) $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
  @(negedge clk);
 end
 $fclose(f);
end endtask
initial begin
 repeat(3) @(negedge clk);reset_n=1;
 force dut.x=200;force dut.y=96;force dut.result=6;
 force dut.save=1;force dut.bytes_frame=progress;
 check_percent(0,"  0%");check_percent(11797,"  9%");
 check_percent(13108," 10%");check_percent(129762," 99%");check_percent(131072,"100%");
 force dut.save=0;
 check_percent(16777216," 50%");
 force dut.save=1;check_percent(131072,"100%");
 force dut.x=224;#1;
 if(rgb!==24'hFFFFFF) $fatal(1,"percent character missing from rendered pixels");
 force dut.y=104;force dut.elapsed=37;
 repeat(80) @(negedge clk);
 if(dut.line[319-8*8-:64]!=="      37" || dut.line[319-17*8-:8]!=="S")
  $fatal(1,"elapsed time must have seconds unit and no leading zeros");
 release dut.elapsed;
 force dut.flash_error_frame=1;force dut.result=5;force dut.y=136;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"flash screen shows stale backup filename");
 force dut.flash_error_frame=0;
 force dut.result=0;force dut.y=96;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"idle dashboard shows stale transfer counters");
 force dut.y=120;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"non-flash screen shows erase/program counters");
 force dut.y=200;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"dashboard repeats backup reminder");
 force dut.y=208;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"dashboard repeats save limitation");
 force dut.y=224;#1;
 if(dut.line!=={40{8'h20}}) $fatal(1,"dashboard repeats candidate status");
 force dut.y=216;force dut.rom_frame=1;#1;
 if(dut.line[319-:192]!=="ROM POSSIBLY INCOMPLETE ") $fatal(1,"incomplete ROM warning lost");
 release dut.x;release dut.y;release dut.result;release dut.save;release dut.bytes_frame;release dut.rom_frame;release dut.flash_error_frame;
 progress=0;
 // During VS the RGB bus carries frame feature bits. Reserved bits must
 // be zero, not the dashboard background color. Exercise blanking as well
 // as the visible pixels captured by the screenshots.
 wait(vs);#1;
 if(rgb!==24'h000000) $fatal(1,"nonzero RGB during VS encodes invalid reserved frame features: %h",rgb);
 screenshot("build/dashboard.ppm");
 selection=2;status=4;header_warning=1;screenshot("build/confirm.ppm");
 output_save=1;status=8;header_warning=0;progress=131072;screenshot("build/backup.ppm");
 if(dut.bytes_bcd!==40'h0000131072 || dut.count_bcd!==40'h0000000582) $fatal(1,"display decimal counters");
 force dut.x=0;force dut.y=152;
 force dut.result=255;force dut.code=14;force dut.flash_error_frame=1;#1;
 if(dut.line[319-:40]!=="ERASE") $fatal(1,"erase failure mislabeled as name exhaustion");
 force dut.flash_error_frame=0;#1;
 if(dut.line[319-:56]!=="NO FREE") $fatal(1,"allocation error origin lost");
 release dut.x;release dut.y;release dut.result;release dut.code;release dut.flash_error_frame;
 $display("PASS utility_video: actual raster screenshots, decimal values and candidate labels");$finish;
end
endmodule
