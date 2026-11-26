module dash_fsm #(
    parameter DASH_FRAMES = 10,
    parameter COOL_FRAMES = 300
)(
    input  wire clk,
    input  wire rst,
    input  wire frame_tick,
    input  wire dash_pulse,
    input  wire active,
    output wire is_dashing,
    output wire ready
);
    localparam READY    = 2'd0;
    localparam DASHING  = 2'd1;
    localparam COOLDOWN = 2'd2;

    reg [1:0] state, next_state;
    reg [8:0] timer;

    always @(posedge clk or posedge rst) begin
        if (rst) state <= READY;
        else     state <= next_state;
    end

    always @(*) begin
        next_state = state;
        if (!active) next_state = READY;
        else begin
            case (state)
                READY:    if (dash_pulse)               next_state = DASHING;
                DASHING:  if (timer >= DASH_FRAMES)     next_state = COOLDOWN;
                COOLDOWN: if (timer >= COOL_FRAMES)     next_state = READY;
                default:                                next_state = READY;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst)                      timer <= 9'd0;
        else if (next_state != state) timer <= 9'd0;
        else if (frame_tick && state != READY)
                                      timer <= timer + 9'd1;
    end

    assign is_dashing = (state == DASHING);
    assign ready      = (state == READY);
endmodule
