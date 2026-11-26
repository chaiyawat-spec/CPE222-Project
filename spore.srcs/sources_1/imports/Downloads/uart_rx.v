// uart_rx.v : 8N1 UART receiver. valid is high for one clock when data holds a new byte.
// CLKS_PER_BIT = clock frequency / baud rate (25.175 MHz / 115200 = about 218).
module uart_rx #(
    parameter CLKS_PER_BIT = 218
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        valid,
    output reg  [7:0] data
);
    // two flip-flops: the pin is asynchronous to the clock
    reg rx1, rx2;
    always @(posedge clk) begin
        rx1 <= rx;
        rx2 <= rx1;
    end

    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
    reg [1:0]  st;
    reg [15:0] cnt;
    reg [2:0]  bit_i;
    reg [7:0]  sh;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            st  <= IDLE;
            cnt <= 16'd0;
        end else begin
            case (st)
                IDLE: begin
                    cnt <= 16'd0;
                    if (!rx2) st <= START;
                end
                START: begin   // check the start bit in its middle
                    if (cnt == CLKS_PER_BIT/2) begin
                        cnt <= 16'd0;
                        if (!rx2) begin bit_i <= 3'd0; st <= DATA; end
                        else      st <= IDLE;
                    end else cnt <= cnt + 16'd1;
                end
                DATA: begin    // every bit is sampled in its middle, LSB first
                    if (cnt == CLKS_PER_BIT-1) begin
                        cnt      <= 16'd0;
                        sh[bit_i] <= rx2;
                        if (bit_i == 3'd7) st <= STOP;
                        else               bit_i <= bit_i + 3'd1;
                    end else cnt <= cnt + 16'd1;
                end
                STOP: begin
                    if (cnt == CLKS_PER_BIT-1) begin
                        st <= IDLE;
                        if (rx2) begin data <= sh; valid <= 1'b1; end   // good stop bit
                    end else cnt <= cnt + 16'd1;
                end
            endcase
        end
    end
endmodule
