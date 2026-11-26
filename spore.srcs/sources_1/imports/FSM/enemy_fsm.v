module enemy_fsm #(
    parameter STUN_FRAMES = 240,   // 4 seconds at 60 frames per second
    parameter FREE_FRAMES = 60     // 1 second free to move
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,  // one-clock pulse, once per frame
    input  wire       active,      // master FSM is in PLAY
    input  wire       near,        // player inside detect range
    input  wire       far,         // player outside lose range (far range > near range)
    input  wire       in_electric, // enemy is inside the ELECTRIC aura
    output wire [1:0] mode,
    output wire       is_stunned
);
    localparam WANDER = 2'd0;
    localparam CHASE  = 2'd1;
    localparam STUN   = 2'd2;
    localparam FREE   = 2'd3;

    reg [1:0] state, next_state;
    reg [8:0] timer;               // frames in STUN or FREE, max 511

    // state register
    always @(posedge clk or posedge rst) begin
        if (rst) state <= WANDER;
        else     state <= next_state;
    end

    // next-state logic
    always @(*) begin
        next_state = state;
        if (!active) next_state = WANDER;
        else begin
            case (state)
                WANDER: begin
                    if      (in_electric) next_state = STUN;
                    else if (near)        next_state = CHASE;
                end
                CHASE: begin
                    if      (in_electric) next_state = STUN;
                    else if (far)         next_state = WANDER;
                end
                STUN: if (timer >= STUN_FRAMES) next_state = FREE;
                FREE: if (timer >= FREE_FRAMES) begin
                          if      (in_electric) next_state = STUN;
                          else if (near)        next_state = CHASE;
                          else                  next_state = WANDER;
                      end
                default: next_state = WANDER;
            endcase
        end
    end

    // timer: cleared on every state change, counts frames in STUN and FREE
    always @(posedge clk or posedge rst) begin
        if (rst)                      timer <= 9'd0;
        else if (next_state != state) timer <= 9'd0;
        else if (frame_tick && (state == STUN || state == FREE) && timer != 9'h1FF)
                                      timer <= timer + 9'd1;
    end

    // Moore outputs
    assign mode       = state;
    assign is_stunned = (state == STUN);
endmodule
