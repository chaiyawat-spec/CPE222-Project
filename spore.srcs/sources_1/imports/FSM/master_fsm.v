module master_fsm #(
    parameter EGG_TAPS = 10
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tap_pulse,
    input  wire       sel_left,
    input  wire       sel_right,
    input  wire       sel_confirm,
    input  wire       restart,
    input  wire       player_dead,
    input  wire       secret_form,
    output reg  [2:0] state,
    output reg        is_carnivore,
    output reg        cursor,
    output reg  [3:0] egg_taps
);
    localparam EGG       = 3'd0;
    localparam SELECT    = 3'd1;
    localparam PLAY      = 3'd2;
    localparam WIN       = 3'd3;
    localparam GAME_OVER = 3'd4;

    reg [2:0] next_state;

    always @(posedge clk or posedge rst) begin
        if (rst) state <= EGG;
        else     state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            EGG:    if (egg_taps >= EGG_TAPS) next_state = SELECT;
            SELECT: if (sel_confirm)          next_state = PLAY;
            PLAY: begin
                if      (player_dead) next_state = GAME_OVER;
                else if (secret_form) next_state = WIN;
            end
            WIN, GAME_OVER: if (restart)      next_state = EGG;
            default:                          next_state = EGG;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            egg_taps     <= 4'd0;
            cursor       <= 1'b0;
            is_carnivore <= 1'b0;
        end else begin
            case (state)
                EGG: begin
                    cursor <= 1'b0;
                    if (tap_pulse && egg_taps < EGG_TAPS)
                        egg_taps <= egg_taps + 4'd1;
                end
                SELECT: begin
                    if (sel_left)    cursor <= 1'b0;
                    if (sel_right)   cursor <= 1'b1;
                    if (sel_confirm) is_carnivore <= cursor;
                end
                WIN, GAME_OVER: if (restart) egg_taps <= 4'd0;
                default: ;
            endcase
        end
    end
endmodule
