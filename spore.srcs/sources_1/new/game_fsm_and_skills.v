module game_fsm_and_skills (
    input  wire        clk,
    input  wire        reset,
    input  wire        frame_tick,
    input  wire        is_paused,
    input  wire        btn_c_pulse,
    input  wire        sw_shock,        // SW[0] Shock
    input  wire        sw_poison,       // SW[1] Poison
    input  wire        sw_dash,         // SW[2] Dash
    input  wire [1:0]  eat_gain,
    input  wire        collect_dna,
    input  wire [1:0]  collect_dna_type,// 0:Dash, 1:Spike, 2:Shock, 3:Poison
    input  wire [3:0]  damage_amount,
    output reg  [1:0]  game_state,
    output reg  [2:0]  form_state,
    output reg  [3:0]  unlocked_skills, // [0]:Dash(SW2), [1]:Spike(Passive), [2]:Shock(SW0), [3]:Poison(SW1)
    output reg         is_god_mode,
    output wire        dash_active,
    output wire        shock_active,
    output wire        poison_active,
    output wire [2:0]  shock_cd_sec,    // วินาที Cooldown ที่เหลือ (0-5)
    output wire [2:0]  poison_cd_sec,
    output wire [2:0]  dash_cd_sec,
    output reg  [13:0] score,
    output reg  [7:0]  growth_points,
    output reg  [7:0]  player_hp
);

    reg [1:0] egg_taps;

    reg [7:0] shock_act_tmr,  poison_act_tmr,  dash_act_tmr;
    reg [8:0] shock_cd_tmr,   poison_cd_tmr,   dash_cd_tmr;
    reg       sw_shock_prev,  sw_poison_prev,  sw_dash_prev;

    wire can_use = (game_state == 2'd1) && !is_paused && (form_state != 3'd0);
    assign shock_active  = can_use && (shock_act_tmr  > 8'd0);
    assign poison_active = can_use && (poison_act_tmr > 8'd0);
    assign dash_active   = can_use && (dash_act_tmr   > 8'd0);

    // แปลงจำนวนเฟรม Cooldown (0..300) เป็นตัวเลขวินาที (0..5)
    assign shock_cd_sec  = (shock_cd_tmr  == 9'd0) ? 3'd0 : ((shock_cd_tmr  + 9'd59) / 9'd60);
    assign poison_cd_sec = (poison_cd_tmr == 9'd0) ? 3'd0 : ((poison_cd_tmr + 9'd59) / 9'd60);
    assign dash_cd_sec   = (dash_cd_tmr   == 9'd0) ? 3'd0 : ((dash_cd_tmr   + 9'd59) / 9'd60);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            game_state      <= 2'd0;
            form_state      <= 3'd0;
            unlocked_skills <= 4'b0000;
            is_god_mode     <= 1'b0;
            score           <= 14'd0;
            growth_points   <= 8'd0;
            player_hp       <= 8'd8;
            egg_taps        <= 2'd0;
            shock_act_tmr   <= 8'd0;
            poison_act_tmr  <= 8'd0;
            dash_act_tmr    <= 8'd0;
            shock_cd_tmr    <= 9'd0;
            poison_cd_tmr   <= 9'd0;
            dash_cd_tmr     <= 9'd0;
            sw_shock_prev   <= 1'b0;
            sw_poison_prev  <= 1'b0;
            sw_dash_prev    <= 1'b0;
        end else begin
            case (game_state)
                2'd0: begin
                    sw_shock_prev  <= sw_shock;
                    sw_poison_prev <= sw_poison;
                    sw_dash_prev   <= sw_dash;
                    if (btn_c_pulse && !is_paused) begin
                        game_state      <= 2'd1;
                        form_state      <= 3'd0;
                        unlocked_skills <= 4'b0000;
                        is_god_mode     <= 1'b0;
                        score           <= 14'd0;
                        growth_points   <= 8'd0;
                        player_hp       <= 8'd8;
                        egg_taps        <= 2'd0;
                        shock_act_tmr   <= 8'd0;
                        poison_act_tmr  <= 8'd0;
                        dash_act_tmr    <= 8'd0;
                        shock_cd_tmr    <= 9'd0;
                        poison_cd_tmr   <= 9'd0;
                        dash_cd_tmr     <= 9'd0;
                    end
                end

                2'd1: begin
                    if (!is_paused) begin
                        sw_shock_prev  <= sw_shock;
                        sw_poison_prev <= sw_poison;
                        sw_dash_prev   <= sw_dash;

                        if (eat_gain > 2'd0) begin
                            if (growth_points < 8'd100)
                                growth_points <= growth_points + {6'd0, eat_gain};
                            if (player_hp < 8'd8)
                                player_hp <= player_hp + 8'd1;

                            if (eat_gain == 2'd1)
                                score <= (score + 14'd10 > 14'd9999) ? 14'd9999 : score + 14'd10;
                            else if (eat_gain == 2'd2)
                                score <= (score + 14'd25 > 14'd9999) ? 14'd9999 : score + 14'd25;
                            else
                                score <= (score + 14'd50 > 14'd9999) ? 14'd9999 : score + 14'd50;
                        end

                        if (collect_dna && !unlocked_skills[collect_dna_type]) begin
                            unlocked_skills[collect_dna_type] <= 1'b1;
                            if (growth_points < 8'd100) growth_points <= growth_points + 8'd1;
                            score <= (score + 14'd20 > 14'd9999) ? 14'd9999 : score + 14'd20;
                        end

                        if (form_state != 3'd0) begin
                            if (sw_shock && !sw_shock_prev && unlocked_skills[2] && (shock_cd_tmr == 9'd0)) begin
                                shock_act_tmr <= 8'd180;
                                shock_cd_tmr  <= 9'd300;
                            end
                            if (sw_poison && !sw_poison_prev && unlocked_skills[3] && (poison_cd_tmr == 9'd0)) begin
                                poison_act_tmr <= 8'd180;
                                poison_cd_tmr  <= 9'd300;
                            end
                            if (sw_dash && !sw_dash_prev && unlocked_skills[0] && (dash_cd_tmr == 9'd0)) begin
                                dash_act_tmr <= 8'd180;
                                dash_cd_tmr  <= 9'd300;
                            end
                        end

                        if (frame_tick) begin
                            if (shock_act_tmr  > 8'd0) shock_act_tmr  <= shock_act_tmr  - 8'd1;
                            if (poison_act_tmr > 8'd0) poison_act_tmr <= poison_act_tmr - 8'd1;
                            if (dash_act_tmr   > 8'd0) dash_act_tmr   <= dash_act_tmr   - 8'd1;

                            if (shock_cd_tmr   > 9'd0) shock_cd_tmr   <= shock_cd_tmr   - 9'd1;
                            if (poison_cd_tmr  > 9'd0) poison_cd_tmr  <= poison_cd_tmr  - 9'd1;
                            if (dash_cd_tmr    > 9'd0) dash_cd_tmr    <= dash_cd_tmr    - 9'd1;
                        end

                        case (form_state)
                            3'd0: begin
                                if (btn_c_pulse) begin
                                    if (egg_taps >= 2'd2) begin
                                        form_state <= 3'd1;
                                        egg_taps   <= 2'd0;
                                    end else begin
                                        egg_taps <= egg_taps + 2'd1;
                                    end
                                end
                            end

                            3'd1: begin
                                if (unlocked_skills[1] || unlocked_skills[3])
                                    form_state <= 3'd2;
                                else if (unlocked_skills[0] || unlocked_skills[2])
                                    form_state <= 3'd3;
                            end

                            3'd2, 3'd3: begin
                                if (unlocked_skills == 4'b1111) begin
                                    form_state  <= 3'd4;
                                    is_god_mode <= 1'b1;
                                end
                            end

                            3'd4: begin
                            end
                        endcase

                        if (damage_amount > 4'd0) begin
                            if (player_hp <= {4'd0, damage_amount}) begin
                                player_hp  <= 8'd0;
                                game_state <= 2'd2;
                            end else begin
                                player_hp <= player_hp - {4'd0, damage_amount};
                            end
                        end
                    end
                end

                2'd2: begin
                    if (btn_c_pulse && !is_paused)
                        game_state <= 2'd0;
                end
            endcase
        end
    end

endmodule