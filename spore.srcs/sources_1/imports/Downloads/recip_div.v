// recip_div.v : q = floor(K * 65536 / den), computed bit by bit (about 23 clocks per result).
// Used to scale a K x K picture to a box of "den" pixels:  texel = (pixel offset * q) >> 16
// den must be at least 4 (the game uses 12 or more). The result is updated all the time,
// so it follows a growing player within a few microseconds.
module recip_div #(
    parameter K = 48
)(
    input  wire        clk,
    input  wire [7:0]  den,
    output reg  [19:0] q
);
    localparam [21:0] NUM = K * 65536;

    reg        busy;
    reg [4:0]  i;
    reg [7:0]  d;
    reg [7:0]  rem;
    reg [21:0] qq;

    wire [8:0] sh = {rem, NUM[i]};
    wire       ge = (sh >= {1'b0, d});

    initial begin busy = 1'b0; q = 20'd0; end

    always @(posedge clk) begin
        if (!busy) begin
            d    <= (den < 8'd4) ? 8'd4 : den;
            rem  <= 8'd0;
            qq   <= 22'd0;
            i    <= 5'd21;
            busy <= 1'b1;
        end else begin
            if (ge) begin
                rem   <= sh[7:0] - d;     // sh - d < d, so it fits 8 bits
                qq[i] <= 1'b1;
            end else begin
                rem   <= sh[7:0];
            end
            if (i == 5'd0) begin
                q    <= {qq[19:1], ge};
                busy <= 1'b0;
            end else begin
                i <= i - 5'd1;
            end
        end
    end
endmodule
