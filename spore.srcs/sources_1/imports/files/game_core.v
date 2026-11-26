// game_core.v
// Replaces game_fsm_and_skills.v.
// Wires the team FSMs (master_fsm, evolution_fsm, dash_fsm) to the score / growth / HP logic.
// Interface notes:
//   - dna_mask uses TEAM bit order:  [0] DASH  [1] MORE DAMAGE  [2] POISON  [3] ELECTRIC
//   - collect_dna_type comes from ecosystem_ai_and_collision and uses ITS order:
//       0 Dash, 1 Spike (MORE DAMAGE), 2 Shock (ELECTRIC), 3 Poison
//   - game_tick must already be gated by pause (frame_tick && !is_paused)
//   - ELECTRIC / POISON auras need the DNA and their switch turned on (sw_electric / sw_poison)
//   - DASH needs the DNA and is triggered by flipping the dash switch up (dash_sw_pulse)
//   - With all 4 DNA the game does NOT end by SW5: defeating the final boss (boss_defeated) triggers WIN
module game_core #(
    parameter DASH_FRAMES      = 10,    // how long a dash lasts (frames)
    parameter DASH_COOL_FRAMES = 300    // wait before the next dash (frames, max 511)
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        game_tick,
    input  wire        is_paused,
    input  wire        btn_c_pulse,
    input  wire        btn_l_pulse,
    input  wire        btn_r_pulse,
    input  wire        sw_electric,    // level: ELECTRIC aura on / off
    input  wire        sw_poison,      // level: POISON aura on / off
    input  wire        dash_sw_pulse,  // pulse: one dash each time the dash switch is flipped up
    input  wire        end_game,       // legacy SW5 input (ignored: SW5 no longer skips the boss)
    input  wire        boss_defeated,  // 1 when the final boss HP reaches 0
    input  wire [1:0]  eat_gain,
    input  wire        collect_dna,
    input  wire [1:0]  collect_dna_type,
    input  wire [3:0]  damage_amount,
    output wire [2:0]  state,
    output wire        is_carnivore,
    output wire        cursor,
    output wire [3:0]  egg_taps,
    output wire [1:0]  form,
    output wire [3:0]  dna_mask,
    output wire        dash_active,
    output wire        shock_active,
    output wire        poison_active,
    output wire [2:0]  dash_cd_sec,
    output reg  [13:0] score,
    output reg  [7:0]  growth_points,
    output reg  [7:0]  player_hp
);

    // must match master_fsm.v
    localparam EGG       = 3'd0;
    localparam SELECT    = 3'd1;
    localparam PLAY      = 3'd2;
    localparam WIN       = 3'd3;
    localparam GAME_OVER = 3'd4;

    wire play = (state == PLAY);
    wire run  = play && !is_paused;

    // button pulses are ignored while paused
    wire c_pulse = btn_c_pulse && !is_paused;
    wire l_pulse = btn_l_pulse && !is_paused;
    wire r_pulse = btn_r_pulse && !is_paused;
    wire dash_pulse_g = dash_sw_pulse && !is_paused;

    wire secret_form;
    wire player_dead = (player_hp == 8'd0);   // master_fsm only looks at it in PLAY
    wire win_request = secret_form && boss_defeated; // SW5 no longer triggers WIN

    // ---------------- master FSM ----------------
    // BTNC is shared: tap (EGG), confirm (SELECT), restart (WIN / GAME_OVER).
    // master_fsm only reacts to each one in its own state.
    master_fsm u_master (
        .clk         (clk),
        .rst         (reset),
        .tap_pulse   (c_pulse),
        .sel_left    (l_pulse),
        .sel_right   (r_pulse),
        .sel_confirm (c_pulse),
        .restart     (c_pulse),
        .player_dead (player_dead),
        .secret_form (win_request),
        .state       (state),
        .is_carnivore(is_carnivore),
        .cursor      (cursor),
        .egg_taps    (egg_taps)
    );

    // ---------------- evolution FSM ----------------
    // eco type -> team one-hot bit
    wire [3:0] got_dna = (run && collect_dna) ?
                         ((collect_dna_type == 2'd0) ? 4'b0001 :     // Dash   -> DASH
                          (collect_dna_type == 2'd1) ? 4'b0010 :     // Spike  -> MORE DAMAGE
                          (collect_dna_type == 2'd2) ? 4'b1000 :     // Shock  -> ELECTRIC
                                                       4'b0100) :    // Poison -> POISON
                         4'b0000;

    evolution_fsm u_evo (
        .clk        (clk),
        .rst        (reset),
        .clear      (state == EGG),
        .got_dna    (got_dna),
        .form       (form),
        .secret_form(secret_form),
        .dna_mask   (dna_mask)
    );

    // ---------------- dash FSM ----------------
    wire dash_ready;

    dash_fsm #(
        .DASH_FRAMES(DASH_FRAMES),
        .COOL_FRAMES(DASH_COOL_FRAMES)
    ) u_dash (
        .clk       (clk),
        .rst       (reset),
        .frame_tick(game_tick),
        .dash_pulse(dash_pulse_g & dna_mask[0]),
        .active    (play),
        .is_dashing(dash_active),
        .ready     (dash_ready)
    );

    // ---------------- auras (switches) ----------------
    assign shock_active  = run && dna_mask[3] && sw_electric;   // ELECTRIC
    assign poison_active = run && dna_mask[2] && sw_poison;     // POISON

    // ---------------- dash cooldown number for the HUD only ----------------
    // Approximation: loads DASH_COOL_FRAMES when dash leaves READY, counts on game_tick.
    reg       dash_ready_d;
    reg [8:0] dash_hud;

    always @(posedge clk) begin
        if (reset || !play) begin
            dash_hud     <= 9'd0;
            dash_ready_d <= 1'b1;
        end else begin
            dash_ready_d <= dash_ready;
            if (dash_ready)
                dash_hud <= 9'd0;
            else if (dash_ready_d)
                dash_hud <= DASH_COOL_FRAMES;
            else if (game_tick && dash_hud != 9'd0)
                dash_hud <= dash_hud - 9'd1;
        end
    end

    assign dash_cd_sec = (dash_hud == 9'd0) ? 3'd0 : ((dash_hud + 9'd59) / 9'd60);

    // ---------------- score, growth, HP ----------------
    wire [3:0] new_dna     = got_dna & ~dna_mask;   // only first pickup of each type counts
    wire       has_new_dna = |new_dna;

    wire [5:0]  eat_score  = (eat_gain == 2'd1) ? 6'd10 :
                             (eat_gain == 2'd2) ? 6'd25 :
                             (eat_gain == 2'd3) ? 6'd50 : 6'd0;
    wire [5:0]  dna_score  = has_new_dna ? 6'd20 : 6'd0;
    wire [14:0] score_sum  = {1'b0, score} + {9'd0, eat_score} + {9'd0, dna_score};
    wire [8:0]  growth_sum = {1'b0, growth_points} + {7'd0, eat_gain} + {8'd0, has_new_dna};

    wire [8:0]  hp_healed  = ((eat_gain != 2'd0) && (player_hp < 8'd8)) ?
                             ({1'b0, player_hp} + 9'd1) : {1'b0, player_hp};
    wire [8:0]  hp_after   = (hp_healed <= {5'd0, damage_amount}) ? 9'd0 :
                             (hp_healed - {5'd0, damage_amount});

    // synchronous clear while in EGG (new game) so no state signal feeds an async reset
    always @(posedge clk) begin
        if (reset || state == EGG) begin
            score         <= 14'd0;
            growth_points <= 8'd0;
            player_hp     <= 8'd8;
        end else if (run) begin
            score         <= (score_sum  > 15'd9999) ? 14'd9999 : score_sum[13:0];
            growth_points <= (growth_sum > 9'd100)   ? 8'd100   : growth_sum[7:0];
            player_hp     <= hp_after[7:0];
        end
    end

endmodule
