// Simulation-only replacements for Vivado IP. ROM latency matches the .xci files.
`timescale 1ns/1ps
module clk_wiz_0(input clk_in1, reset, output clk_out1, locked);
    assign clk_out1 = clk_in1;
    assign locked = !reset;
endmodule

module map_rom(input clka, input [11:0] addra, output reg [2:0] douta);
    reg [2:0] mem [0:4095];
    initial $readmemh("map.mem", mem);
    always @(posedge clka) douta <= mem[addra];
endmodule

module tile_rom(input clka, input [12:0] addra, output reg [11:0] douta);
    reg [11:0] mem [0:6143];
    initial $readmemh("tile.mem", mem);
    always @(posedge clka) douta <= (addra < 6144) ? mem[addra] : 12'hF0F;
endmodule

module art_rom(input clka, clkb, input [17:0] addra, addrb,
               output reg [11:0] douta, doutb);
    reg [11:0] mem [0:180479];
    initial $readmemh("art.mem", mem);
    always @(posedge clka) douta <= (addra < 180480) ? mem[addra] : 12'hF0F;
    always @(posedge clkb) doutb <= (addrb < 180480) ? mem[addrb] : 12'hF0F;
endmodule
