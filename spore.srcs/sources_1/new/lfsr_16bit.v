module lfsr_16bit (
    input  wire        clk,
    input  wire        reset,
    output reg  [15:0] rnd
);

    wire feedback = rnd[15] ^ rnd[14] ^ rnd[12] ^ rnd[3];

    always @(posedge clk or posedge reset) begin
        if (reset)
            rnd <= 16'hACE1; // ค่า Seed เริ่มต้น
        else
            rnd <= {rnd[14:0], feedback};
    end

endmodule