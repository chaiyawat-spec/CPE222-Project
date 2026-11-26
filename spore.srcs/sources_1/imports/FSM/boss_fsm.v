module boss_fsm #(
    parameter [8:0] STALK_FRAMES_P1    = 9'd90,
    parameter [8:0] STALK_FRAMES_P2    = 9'd30,
    parameter [8:0] WARN_FRAMES_P1     = 9'd45,
    parameter [8:0] WARN_FRAMES_P2     = 9'd30,
    parameter [8:0] DASH_FRAMES_P1     = 9'd24,
    parameter [8:0] DASH_FRAMES_P2     = 9'd24,
    parameter [8:0] VULN_FRAMES_P1     = 9'd120,
    parameter [8:0] VULN_FRAMES_P2     = 9'd90,
    parameter [8:0] STUN_FRAMES        = 9'd120,
    parameter [8:0] STUN_IMMUNE_FRAMES = 9'd180
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       active,
    input  wire       in_range,
    input  wire       in_electric,
    input  wire       phase2,
    output wire [2:0] state_out,
    output wire       is_telegraph,
    output wire       is_dashing,
    output wire       is_vuln,
    output wire       is_stunned,
    output wire       telegraph_start
);
    localparam [2:0] B_STALK     = 3'd0;
    localparam [2:0] B_TELEGRAPH = 3'd1;
    localparam [2:0] B_DASH      = 3'd2;
    localparam [2:0] B_VULN      = 3'd3;
    localparam [2:0] B_STUN      = 3'd4;

    reg [2:0] state, next_state;
    reg [8:0] timer;
    reg [8:0] stun_immune_tmr;

    wire [8:0] stalk_limit = phase2 ? STALK_FRAMES_P2 : STALK_FRAMES_P1;
    wire [8:0] warn_limit  = phase2 ? WARN_FRAMES_P2  : WARN_FRAMES_P1;
    wire [8:0] dash_limit  = phase2 ? DASH_FRAMES_P2  : DASH_FRAMES_P1;
    wire [8:0] vuln_limit  = phase2 ? VULN_FRAMES_P2  : VULN_FRAMES_P1;

    wire can_stun = in_electric && (stun_immune_tmr == 9'd0) && (state != B_STUN);

    always @(posedge clk) begin
        if (rst || !active) state <= B_STALK;
        else                state <= next_state;
    end

    always @(*) begin
        next_state = state;
        if (!active) begin
            next_state = B_STALK;
        end else begin
            case (state)
                B_STALK: begin
                    if (can_stun)                           next_state = B_STUN;
                    else if (in_range && timer >= stalk_limit) next_state = B_TELEGRAPH;
                end
                B_TELEGRAPH: begin
                    if (can_stun)                           next_state = B_STUN;
                    else if (timer >= warn_limit)           next_state = B_DASH;
                end
                B_DASH: begin
                    if (can_stun)                           next_state = B_STUN;
                    else if (timer >= dash_limit)           next_state = B_VULN;
                end
                B_VULN: begin
                    if (can_stun)                           next_state = B_STUN;
                    else if (timer >= vuln_limit)           next_state = B_STALK;
                end
                B_STUN: begin
                    if (timer >= STUN_FRAMES)               next_state = B_STALK;
                end
                default: next_state = B_STALK;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst || !active) begin
            timer           <= 9'd0;
            stun_immune_tmr <= 9'd0;
        end else begin
            if (next_state != state) begin
                timer <= 9'd0;
                if (state == B_STUN)
                    stun_immune_tmr <= STUN_IMMUNE_FRAMES;
            end else if (frame_tick) begin
                if (state == B_STALK) begin
                    if (in_range && timer != 9'h1FF)
                        timer <= timer + 9'd1;
                end else if (timer != 9'h1FF) begin
                    timer <= timer + 9'd1;
                end
            end

            if (frame_tick && !(next_state != state && state == B_STUN) && (stun_immune_tmr > 9'd0))
                stun_immune_tmr <= stun_immune_tmr - 9'd1;
        end
    end

    assign state_out       = state;
    assign is_telegraph    = (state == B_TELEGRAPH);
    assign is_dashing      = (state == B_DASH);
    assign is_vuln         = (state == B_VULN);
    assign is_stunned      = (state == B_STUN);
    assign telegraph_start = active && (state != B_TELEGRAPH) && (next_state == B_TELEGRAPH);
endmodule
