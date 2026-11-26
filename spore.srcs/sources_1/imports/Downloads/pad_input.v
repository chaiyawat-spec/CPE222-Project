// pad_input.v : gamepad state received from the PC over UART (see pad_bridge.py).
//
// Packet = 2 bytes, 60 times per second, sent all the time (it is also the keep-alive):
//   byte 0 = 0 s6 s5 s4 s3 s2 s1 s0      (bit 7 = 0: low half)
//   byte 1 = 1 s13 s12 s11 s10 s9 s8 s7  (bit 7 = 1: high half)
// Button bits (1 = pressed):
//   0 up   1 down   2 left   3 right   4 A   5 X   6 Y   7 B   8 Start   9 Back   10 RB
//
// Outputs:
//   up/down/left/right/a_level : levels, same use as the board buttons
//   l_pulse / r_pulse / c_pulse: one clock when left / right / A goes down
//   dash_pulse                 : one clock when B goes down
//   electric_on / poison_on    : toggled by X / Y   (works like SW0 / SW1)
//   pause_on                   : toggled by Start   (works like SW3)
//   end_on                     : toggled by RB      (works like SW5)
//   newgame                    : level, high while Back is held (works like SW4)
//   connected                  : packets are arriving. If they stop for TIMEOUT_CLKS
//                                everything is cleared, so no button can stay stuck.
module pad_input #(
    parameter CLKS_PER_BIT = 218,
    parameter TIMEOUT_CLKS = 12_500_000   // about 0.5 s at 25 MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,
    output wire up, down, left, right, a_level,
    output wire l_pulse, r_pulse, c_pulse, dash_pulse,
    output wire electric_on, poison_on, pause_on, end_on,
    output wire newgame,
    output wire connected
);
    wire       rx_valid;
    wire [7:0] rx_data;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(rx), .valid(rx_valid), .data(rx_data)
    );

    reg [6:0]  low;
    reg        have_low;
    reg [10:0] raw, prev;
    reg [24:0] timer;
    reg [10:0] rise;
    reg        t_electric, t_poison, t_pause, t_end;

    wire alive    = (timer < TIMEOUT_CLKS);
    wire pkt_done = rx_valid && rx_data[7] && have_low;   // a complete packet arrives this clock
    assign connected = alive;

    always @(posedge clk) begin
        if (rst) begin
            low <= 7'd0; have_low <= 1'b0;
            raw <= 11'd0; prev <= 11'd0; rise <= 11'd0;
            timer <= TIMEOUT_CLKS;            // starts "not connected"
            t_electric <= 1'b0; t_poison <= 1'b0; t_pause <= 1'b0; t_end <= 1'b0;
        end else begin
            prev <= raw;
            rise <= raw & ~prev;

            if (timer < TIMEOUT_CLKS) timer <= timer + 25'd1;

            if (rx_valid) begin
                if (!rx_data[7]) begin                    // low half
                    low      <= rx_data[6:0];
                    have_low <= 1'b1;
                end else if (have_low) begin              // high half completes a packet
                    raw      <= {rx_data[3:0], low};
                    have_low <= 1'b0;
                    timer    <= 25'd0;
                end
            end

            if (!alive && !pkt_done) begin                // script stopped: release everything
                raw <= 11'd0;
                t_electric <= 1'b0; t_poison <= 1'b0; t_pause <= 1'b0; t_end <= 1'b0;
            end else begin
                if (rise[5])  t_electric <= ~t_electric;
                if (rise[6])  t_poison   <= ~t_poison;
                if (rise[8])  t_pause    <= ~t_pause;
                if (rise[10]) t_end      <= ~t_end;
            end
        end
    end

    assign up          = raw[0];
    assign down        = raw[1];
    assign left        = raw[2];
    assign right       = raw[3];
    assign a_level     = raw[4];
    assign l_pulse     = rise[2];
    assign r_pulse     = rise[3];
    assign c_pulse     = rise[4];
    assign dash_pulse  = rise[7];
    assign electric_on = t_electric;
    assign poison_on   = t_poison;
    assign pause_on    = t_pause;
    assign end_on      = t_end;
    assign newgame     = raw[9];
endmodule
