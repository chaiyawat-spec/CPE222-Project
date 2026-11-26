module top_game (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire        BTNU, BTND, BTNL, BTNR, BTNC,
    input  wire        UART_TXD_IN, // gamepad from the PC (pad_bridge.py), board pin C4
    input  wire [5:0]  SW,          // SW0 ELECTRIC on/off, SW1 POISON on/off, SW2 DASH, SW3 pause, SW4 new game, SW5 end game
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [15:0] LED,
    output wire        LED16_R, LED16_G, LED16_B,
    output wire        CA, CB, CC, CD, CE, CF, CG, DP,
    output wire [7:0]  AN
);

    wire reset_btn = ~CPU_RESETN;
    wire clk_25m;
    wire locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1(CLK100MHZ),
        .reset(reset_btn),
        .clk_out1(clk_25m),
        .locked(locked)
    );

    // hold the whole design in reset until the PLL is locked
    wire reset = reset_btn | ~locked;

    // ==================================================================
    // TUNING: change the numbers here. 60 frames = 1 second.
    // ==================================================================
    // Movement: speed = SPEED_BASE minus 1 for every 2^SPEED_PENALTY_SHIFT pixels of size, never below SPEED_MIN
    localparam [7:0]   SPEED_BASE          = 8'd14;
    localparam [7:0]   SPEED_MIN           = 8'd8;      // was 6 (bigger = faster when big)
    localparam [2:0]   SPEED_PENALTY_SHIFT = 3'd4;      // 4 = 16 pixels
    // DASH (SW2: flip up for one dash)
    localparam integer DASH_FRAMES         = 10;        // how long a dash lasts
    localparam integer DASH_COOL_FRAMES    = 300;       // wait before the next dash (max 511)
    localparam [7:0]   DASH_SPEED_BONUS    = 8'd12;     // extra top speed while dashing
    // ELECTRIC (SW0: on / off)
    localparam [11:0]  ELECTRIC_RADIUS     = 12'd18;    // circle size: pixels added to the body radius
    localparam integer STUN_FRAMES         = 240;       // stun time
    localparam integer FREE_FRAMES         = 60;        // free time after a stun
    // POISON (SW1: on / off)
    localparam [11:0]  POISON_RADIUS       = 12'd12;    // circle size: pixels added to the body radius
    localparam [2:0]   POISON_DAMAGE       = 3'd1;      // damage per tick
    localparam [5:0]   POISON_TICK_FRAMES  = 6'd30;     // frames between ticks
    // MORE DAMAGE
    localparam [2:0]   ATTACK_DAMAGE       = 3'd1;      // normal attack damage
    localparam [2:0]   MORE_DAMAGE_BONUS   = 3'd1;      // extra damage with the MORE DAMAGE skill
    localparam [2:0]   DASH_DAMAGE_BONUS   = 3'd1;      // extra damage while dashing
    // Player picture: drawn this many pixels bigger than the hit box (bigger = easier to see)
    localparam [7:0]   PLAYER_DRAW_PAD     = 8'd32;
    // Egg: how long the sparkle effect shows after each tap (frames)
    localparam [4:0]   EGG_FX_FRAMES       = 5'd12;
    // Background: 1 = tile map (needs map_rom and tile_rom IP), 0 = old plain background with grid
    localparam         USE_TILE_MAP        = 1;
    // Rocks crack and reveal any DNA on the first hit, then vanish after 2 seconds.
    localparam [6:0]   ROCK_BREAK_FRAMES   = 7'd120;
    // A new DNA on the ground cannot be picked up for this long (so you see it appear first)
    localparam [5:0]   DNA_PICKUP_DELAY    = 6'd12;     // 12 frames = 0.2 s
    // Drop rates: chance = 1 / 2^(number of 1 bits in the mask), all zeros = always
    localparam [3:0]   ROCK_DROP_MASK      = 4'b0001;   // herbivore, DNA from a broken rock (1 in 2)
    localparam [2:0]   ENEMY_DROP_MASK     = 3'b111;    // carnivore, DNA from an eaten enemy (1 in 8)
    // FINAL BOSS (Giant TOTO): appears once per round when all 4 DNA are collected
    localparam [5:0]   BOSS_MAX_HP             = 6'd16;     // boss HP (Phase 2 starts at <= half)
    localparam [7:0]   BOSS_SIZE               = 8'd180;    // Giant TOTO sprite/hitbox size (px)
    localparam [11:0]  BOSS_AGGRO_RANGE        = 12'd240;   // edge distance to engage boss dashes & banner
    localparam [7:0]   BOSS_ALERT_FRAMES       = 8'd180;    // "BOSS TOTO AWAKE!" alert duration (3 s)
    localparam [8:0]   BOSS_STALK_FRAMES_P1    = 9'd90;     // Phase 1 pause before blink warning (1.5 s)
    localparam [8:0]   BOSS_STALK_FRAMES_P2    = 9'd30;     // Phase 2 pause before blink warning (0.5 s)
    localparam [8:0]   BOSS_WARN_FRAMES_P1     = 9'd45;     // Phase 1 blink warning before dash (0.75 s)
    localparam [8:0]   BOSS_WARN_FRAMES_P2     = 9'd30;     // Phase 2 blink warning before dash (0.50 s)
    localparam [8:0]   BOSS_DASH_FRAMES_P1     = 9'd24;     // Phase 1 dash duration (0.40 s)
    localparam [8:0]   BOSS_DASH_FRAMES_P2     = 9'd24;     // Phase 2 dash duration (0.40 s)
    localparam [8:0]   BOSS_VULN_FRAMES_P1     = 9'd120;    // Phase 1 attack opening after dash (2.0 s)
    localparam [8:0]   BOSS_VULN_FRAMES_P2     = 9'd90;     // Phase 2 attack opening after dash (1.5 s)
    localparam [8:0]   BOSS_STUN_FRAMES        = 9'd120;    // Electric stun duration (2.0 s)
    localparam [8:0]   BOSS_STUN_IMMUNE_FRAMES = 9'd180;    // stun cooldown after Electric wears off (3.0 s)
    localparam [5:0]   BOSS_DASH_SPEED_P1      = 6'd5;      // Phase 1 dash speed (px/frame)
    localparam [5:0]   BOSS_DASH_SPEED_P2      = 6'd6;      // Phase 2 dash speed (px/frame)
    localparam [3:0]   BOSS_CONTACT_DMG        = 4'd1;      // contact damage outside dash/vulnerable
    localparam [3:0]   BOSS_DASH_DMG           = 4'd2;      // contact damage during boss dash

    wire video_on, frame_tick;
    wire [9:0] pixel_x, pixel_y;

    vga_controller u_vga (
        .clk_25m(clk_25m),
        .reset(reset),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .video_on(video_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .frame_tick(frame_tick)
    );

    wire up_b, down_b, left_b, right_b, center_b;
    wire left_pulse_b, right_pulse_b, center_pulse_b;
    button_debouncer db_u (.clk(clk_25m), .btn_in(BTNU), .btn_state(up_b),     .btn_pulse());
    button_debouncer db_d (.clk(clk_25m), .btn_in(BTND), .btn_state(down_b),   .btn_pulse());
    button_debouncer db_l (.clk(clk_25m), .btn_in(BTNL), .btn_state(left_b), .btn_pulse(left_pulse_b));
    button_debouncer db_r (.clk(clk_25m), .btn_in(BTNR), .btn_state(right_b), .btn_pulse(right_pulse_b));
    button_debouncer db_c (.clk(clk_25m), .btn_in(BTNC), .btn_state(center_b), .btn_pulse(center_pulse_b));

    // switches go through the same debouncer / synchronizer as the buttons
    wire pause_b, sw_electric_b, sw_poison_b, newgame_b, end_b, dash_sw_state, dash_sw_pulse_b;
    button_debouncer db_s0 (.clk(clk_25m), .btn_in(SW[0]), .btn_state(sw_electric_b),   .btn_pulse());
    button_debouncer db_s1 (.clk(clk_25m), .btn_in(SW[1]), .btn_state(sw_poison_b),     .btn_pulse());
    button_debouncer db_s2 (.clk(clk_25m), .btn_in(SW[2]), .btn_state(dash_sw_state), .btn_pulse(dash_sw_pulse_b));
    button_debouncer db_s3 (.clk(clk_25m), .btn_in(SW[3]), .btn_state(pause_b),     .btn_pulse());
    button_debouncer db_s4 (.clk(clk_25m), .btn_in(SW[4]), .btn_state(newgame_b), .btn_pulse());
    button_debouncer db_s5 (.clk(clk_25m), .btn_in(SW[5]), .btn_state(end_b),   .btn_pulse());

    // ------------------------------------------------------------------
    // Gamepad: the PC sends the pad state over the USB-UART cable (pad_bridge.py).
    // Pad and board buttons/switches work together (OR).
    // ------------------------------------------------------------------
    wire pad_up, pad_down, pad_left, pad_right, pad_a;
    wire pad_l_pulse, pad_r_pulse, pad_c_pulse, pad_dash_pulse;
    wire pad_electric, pad_poison, pad_pause, pad_end, pad_newgame, pad_connected;

    pad_input #(.CLKS_PER_BIT(218)) u_pad (      // 25.175 MHz / 115200 baud
        .clk(clk_25m), .rst(reset), .rx(UART_TXD_IN),
        .up(pad_up), .down(pad_down), .left(pad_left), .right(pad_right), .a_level(pad_a),
        .l_pulse(pad_l_pulse), .r_pulse(pad_r_pulse), .c_pulse(pad_c_pulse), .dash_pulse(pad_dash_pulse),
        .electric_on(pad_electric), .poison_on(pad_poison), .pause_on(pad_pause), .end_on(pad_end),
        .newgame(pad_newgame), .connected(pad_connected)
    );

    wire up_s    = up_b    | pad_up;
    wire down_s  = down_b  | pad_down;
    wire left_s  = left_b  | pad_left;
    wire right_s = right_b | pad_right;
    wire center_s = center_b | pad_a;
    wire left_pulse   = left_pulse_b   | pad_l_pulse;
    wire right_pulse  = right_pulse_b  | pad_r_pulse;
    wire center_pulse = center_pulse_b | pad_c_pulse;

    wire is_paused     = pause_b       | pad_pause;
    wire sw_electric   = sw_electric_b | pad_electric;
    wire sw_poison     = sw_poison_b   | pad_poison;
    wire dash_sw_pulse = dash_sw_pulse_b | pad_dash_pulse;
    wire game_reset_sw = newgame_b     | pad_newgame;
    wire end_game_sw   = end_b         | pad_end;

    // reset for the game logic: board reset, PLL not locked, or new game (SW4 up / pad Back held)
    wire game_rst = reset | game_reset_sw;

    // ------------------------------------------------------------------
    // Game control: team FSMs (master / evolution / dash) through game_core
    // ------------------------------------------------------------------
    // must match master_fsm.v
    localparam EGG = 3'd0, SELECT = 3'd1, PLAY = 3'd2, WIN = 3'd3, GAME_OVER = 3'd4;

    wire [2:0]  state;
    wire        is_carnivore, cursor;
    wire [3:0]  egg_taps;
    wire [1:0]  form;
    wire [3:0]  dna_mask;       // team order: [0] DASH [1] MORE DAMAGE [2] POISON [3] ELECTRIC
    wire        dash_active, shock_active, poison_active;
    wire [2:0]  dash_cd_sec;
    // the auras are automatic now, so there is no cooldown number to show for them
    wire [2:0]  shock_cd_sec  = 3'd0;
    wire [2:0]  poison_cd_sec = 3'd0;
    wire [13:0] score;
    wire [7:0]  growth_points;
    wire [7:0]  player_hp;
    wire [3:0]  damage_amount;
    wire [1:0]  eat_gain;
    wire        collect_dna;
    wire [1:0]  collect_dna_type;
    wire [11:0] boss_wx, boss_wy;
    wire [7:0]  boss_size;
    wire        boss_active, boss_defeated, boss_phase2;
    wire [5:0]  boss_hp, boss_max_hp;
    wire [2:0]  boss_state;
    wire [7:0]  boss_alert_tmr;
    wire [5:0]  boss_hit_flash_tmr;

    // Run the intro once on the boss activation edge, using the raw VGA frame tick.
    localparam [6:0] BOSS_INTRO_FRAMES = 7'd120;
    reg boss_was_active;
    reg [6:0] boss_intro_left;
    wire boss_intro_start = boss_active && !boss_was_active;
    wire boss_intro = (state == PLAY) && (boss_intro_start || (boss_intro_left != 7'd0));
    wire game_frozen = is_paused || boss_intro;
    wire game_tick = frame_tick && !game_frozen;
    always @(posedge clk_25m) begin
        if (game_rst) begin
            boss_was_active <= 1'b0;
            boss_intro_left <= 7'd0;
        end else begin
            boss_was_active <= boss_active;
            if (boss_intro_start)
                boss_intro_left <= BOSS_INTRO_FRAMES;
            else if (frame_tick && boss_intro_left != 7'd0)
                boss_intro_left <= boss_intro_left - 7'd1;
        end
    end

    localparam [1:0] MENU = 2'd0, CHOOSE = 2'd1, SCORES = 2'd2, IDLE = 2'd3;
    localparam [1:0] START_ITEM = 2'd0, SCORE_ITEM = 2'd1, EXIT_ITEM = 2'd2;
    reg menu_open;
    reg [1:0] menu_screen, menu_item;
    reg menu_up_d, menu_down_d;
    wire choosing_side = left_pulse || right_pulse;
    wire menu_up = up_s && !menu_up_d;
    wire menu_down = down_s && !menu_down_d;

    always @(posedge clk_25m) begin
        menu_up_d <= up_s;
        menu_down_d <= down_s;
        if (game_rst) begin
            menu_open <= 1'b1;
            menu_screen <= MENU;
            menu_item <= START_ITEM;
        end else if (menu_open && !is_paused) begin
            if (menu_screen != MENU) begin
                if (center_pulse) menu_screen <= MENU;
            end else if (center_pulse) begin
                case (menu_item)
                    START_ITEM: menu_open <= 1'b0;
                    SCORE_ITEM: menu_screen <= SCORES;
                    EXIT_ITEM: begin menu_screen <= IDLE; menu_item <= START_ITEM; end
                    default: menu_item <= START_ITEM;
                endcase
            end else if (menu_up) begin
                menu_item <= START_ITEM;
            end else if (left_pulse || (menu_down && menu_item == START_ITEM)) begin
                menu_item <= SCORE_ITEM;
            end else if (right_pulse) begin
                menu_item <= EXIT_ITEM;
            end
        end

    end

    // Record the final score when a play session reaches WIN or GAME_OVER.
    // SW4 opens the menu and preserves scores. Board reset clears the history.
    reg [2:0] previous_state;
    reg [13:0] best_score, last_score;
    always @(posedge clk_25m) begin
        if (reset) begin
            previous_state <= EGG;
            best_score <= 14'd0;
            last_score <= 14'd0;
        end else begin
            previous_state <= state;
            if (previous_state == PLAY && ((state == WIN) || (state == GAME_OVER))) begin
                last_score <= score;
                if (score > best_score) best_score <= score;
            end
        end
    end

    wire game_center_pulse = center_pulse && !menu_open &&
                             ((state != SELECT) || !choosing_side);

    game_core #(
        .DASH_FRAMES(DASH_FRAMES),
        .DASH_COOL_FRAMES(DASH_COOL_FRAMES)
    ) u_core (
        .clk(clk_25m),
        .reset(game_rst),
        .game_tick(game_tick),
        .is_paused(game_frozen),
        .btn_c_pulse(game_center_pulse),
        .btn_l_pulse(left_pulse),
        .btn_r_pulse(right_pulse),
        .sw_electric(sw_electric),
        .sw_poison(sw_poison),
        .dash_sw_pulse(dash_sw_pulse),
        .end_game(end_game_sw),
        .boss_defeated(boss_defeated),
        .eat_gain(eat_gain),
        .collect_dna(collect_dna),
        .collect_dna_type(collect_dna_type),
        .damage_amount(damage_amount),
        .state(state),
        .is_carnivore(is_carnivore),
        .cursor(cursor),
        .egg_taps(egg_taps),
        .form(form),
        .dna_mask(dna_mask),
        .dash_active(dash_active),
        .shock_active(shock_active),
        .poison_active(poison_active),
        .dash_cd_sec(dash_cd_sec),
        .score(score),
        .growth_points(growth_points),
        .player_hp(player_hp)
    );

    // ------------------------------------------------------------------
    // Adapters for modules that still use the old signals
    // (ecosystem_ai_and_collision, sprite_renderer, peripherals_driver).
    // Remove them when those modules are converted to the team state names.
    // ------------------------------------------------------------------
    // old DNA order: [0] Dash [1] Spike [2] Shock [3] Poison
    wire [3:0] unlocked_skills_c = {dna_mask[2], dna_mask[3], dna_mask[1], dna_mask[0]};
    reg  [3:0] unlocked_skills;

    // old form_state: 0 egg, 1 baby, 2 herbivore, 3 carnivore, 4 perfect
    wire [2:0] form_state_c = (state == EGG)   ? 3'd0 :
                              (form == 2'd0)   ? 3'd1 :
                              (form == 2'd1)   ? (is_carnivore ? 3'd3 : 3'd2) : 3'd4;
    reg  [2:0] form_state;

    // old game_state for movement and eco: 0 reset world, 1 run, 3 frozen (pause / WIN / GAME_OVER)
    wire [1:0] run_state_c = game_frozen                          ? 2'd3 :
                             (state == PLAY)                    ? 2'd1 :
                             (state == EGG || state == SELECT)  ? 2'd0 : 2'd3;
    reg  [1:0] run_state;

    // old game_state for the renderer: 1 world view, 2 game over screen
    wire [1:0] render_state_c = (state == GAME_OVER) ? 2'd2 : 2'd1;
    reg  [1:0] render_state;

    wire is_win = (state == WIN);

    // sparkle effect on the egg for a moment after every tap
    reg [4:0] egg_fx_t;
    always @(posedge clk_25m) begin
        if (game_rst)                              egg_fx_t <= 5'd0;
        else if (game_center_pulse && !is_paused && state == EGG)     egg_fx_t <= EGG_FX_FRAMES;
        else if (game_tick && egg_fx_t != 5'd0)    egg_fx_t <= egg_fx_t - 5'd1;
    end
    wire egg_fx = (egg_fx_t != 5'd0);

    // Registered copies (timing fix): they cut the long path
    // state -> body size -> camera -> sprite address. They lag by one clock, which is invisible.
    always @(posedge clk_25m) begin
        unlocked_skills <= unlocked_skills_c;
        form_state      <= form_state_c;
        run_state       <= run_state_c;
        render_state    <= render_state_c;
    end

    wire [8:0] raw_p_size = (form_state == 3'd0) ? 9'd16 :
                            (form_state == 3'd4) ? (9'd32 + ({1'b0, growth_points} << 1)) :
                                                   (9'd16 + ({1'b0, growth_points} << 1));
    wire [7:0] player_size_c = (raw_p_size > 9'd160) ? 8'd160 : raw_p_size[7:0];
    reg  [7:0] player_size;
    always @(posedge clk_25m) player_size <= player_size_c;

    // ------------------------------------------------------------------
    // bigger body = slower (see SPEED_* in the TUNING block)
    // ------------------------------------------------------------------
    wire [7:0] size_penalty = (player_size > 8'd16) ? ((player_size - 8'd16) >> SPEED_PENALTY_SHIFT) : 8'd0;
    wire [7:0] spd_raw      = (size_penalty >= SPEED_BASE) ? 8'd0 : (SPEED_BASE - size_penalty);
    wire [7:0] base_spd_u   = (spd_raw < SPEED_MIN) ? SPEED_MIN : spd_raw;
    wire signed [7:0] max_speed = dash_active ? ($signed({1'b0, base_spd_u[6:0]}) + $signed({1'b0, DASH_SPEED_BONUS[6:0]})) :
                                                $signed({1'b0, base_spd_u[6:0]});
    wire signed [7:0] accel = 8'sd2;

    localparam WORLD_MAX = 12'd2048;
    reg  [11:0] player_wx, player_wy;
    reg signed [7:0] vx, vy;
    // Keep the original cardinal codes; add NE, SE, SW, NW as 4..7.
    reg  [2:0]  facing_dir;
    // Opposite buttons cancel on each axis, for both facing and movement.
    wire move_up    = up_s    && !down_s;
    wire move_down  = down_s  && !up_s;
    wire move_left  = left_s  && !right_s;
    wire move_right = right_s && !left_s;

    // Velocity is in quarter pixels. Scale both axes by 181/256 (~1/sqrt(2))
    // when moving diagonally and retain subpixels across frames.
    reg [9:0] player_frac_x, player_frac_y;
    wire diagonal_velocity = (vx != 8'sd0) && (vy != 8'sd0);
    wire signed [16:0] step_x = diagonal_velocity ? vx * 17'sd181 : vx * 17'sd256;
    wire signed [16:0] step_y = diagonal_velocity ? vy * 17'sd181 : vy * 17'sd256;
    wire signed [22:0] next_x_fp = $signed({1'b0, player_wx, player_frac_x}) + step_x;
    wire signed [22:0] next_y_fp = $signed({1'b0, player_wy, player_frac_y}) + step_y;
    wire signed [13:0] next_wx = next_x_fp >>> 10;
    wire signed [13:0] next_wy = next_y_fp >>> 10;

    function automatic signed [7:0] update_velocity;
        input signed [7:0] velocity;
        input move_negative, move_positive;
        input signed [7:0] speed_limit;
        reg signed [7:0] magnitude;
        begin
            magnitude = velocity < 0 ? -velocity : velocity;
            if (move_negative)
                update_velocity = (velocity <= -speed_limit + accel) ? -speed_limit : velocity - accel;
            else if (move_positive)
                update_velocity = (velocity >= speed_limit - accel) ? speed_limit : velocity + accel;
            else if (magnitude < 8'sd8)
                update_velocity = 8'sd0;
            else
                update_velocity = velocity < 0 ? velocity + (magnitude >>> 3) : velocity - (magnitude >>> 3);
        end
    endfunction

    // synchronous reset so run_state never drives an async reset pin
    always @(posedge clk_25m) begin
        if (game_rst || run_state == 2'd0) begin
            player_wx  <= 12'd1024;
            player_wy  <= 12'd1024;
            player_frac_x <= 10'd0;
            player_frac_y <= 10'd0;
            vx         <= 8'sd0;
            vy         <= 8'sd0;
            facing_dir <= 3'd1;
        end else if (frame_tick && run_state == 2'd1) begin
            case ({move_up, move_down, move_left, move_right})
                4'b1000: facing_dir <= 3'd0; // N
                4'b0001: facing_dir <= 3'd1; // E
                4'b0100: facing_dir <= 3'd2; // S
                4'b0010: facing_dir <= 3'd3; // W
                4'b1001: facing_dir <= 3'd4; // NE
                4'b0101: facing_dir <= 3'd5; // SE
                4'b0110: facing_dir <= 3'd6; // SW
                4'b1010: facing_dir <= 3'd7; // NW
                default: ; // Released/cancelled input keeps the last facing.
            endcase

            vx <= update_velocity(vx, move_left, move_right, max_speed);
            vy <= update_velocity(vy, move_up, move_down, max_speed);

            if (next_wx < 14'sd16) begin
                player_wx <= 12'd16;
                player_frac_x <= 10'd0;
                vx <= 8'sd0;
            end else if (next_wx > $signed({2'b00, WORLD_MAX - {4'd0, player_size} - 12'd16})) begin
                player_wx <= WORLD_MAX - {4'd0, player_size} - 12'd16;
                player_frac_x <= 10'd0;
                vx <= 8'sd0;
            end else begin
                player_wx <= next_wx[11:0];
                player_frac_x <= next_x_fp[9:0];
            end

            if (next_wy < 14'sd16) begin
                player_wy <= 12'd16;
                player_frac_y <= 10'd0;
                vy <= 8'sd0;
            end else if (next_wy > $signed({2'b00, WORLD_MAX - {4'd0, player_size} - 12'd16})) begin
                player_wy <= WORLD_MAX - {4'd0, player_size} - 12'd16;
                player_frac_y <= 10'd0;
                vy <= 8'sd0;
            end else begin
                player_wy <= next_wy[11:0];
                player_frac_y <= next_y_fp[9:0];
            end
        end
    end

    // "is the player really moving" for the swimming animation and the water ripples
    wire moving_c = (vx >= 8'sd4) || (vx <= -8'sd4) || (vy >= 8'sd4) || (vy <= -8'sd4);
    reg  player_moving;
    always @(posedge clk_25m) player_moving <= moving_c && (run_state == 2'd1);

    wire [11:0] p_center_wx = player_wx + {5'd0, player_size[7:1]};
    wire [11:0] p_center_wy = player_wy + {5'd0, player_size[7:1]};

    wire [11:0] cam_x_c = (p_center_wx < 12'd320) ? 12'd0 :
                          (p_center_wx > 12'd1728) ? 12'd1408 : (p_center_wx - 12'd320);
    wire [11:0] cam_y_c = (p_center_wy < 12'd240) ? 12'd0 :
                          (p_center_wy > 12'd1808) ? 12'd1568 : (p_center_wy - 12'd240);
    reg  [11:0] cam_x, cam_y;   // registered: shortens the path into the sprite renderer
    always @(posedge clk_25m) begin
        cam_x <= cam_x_c;
        cam_y <= cam_y_c;
    end

    wire [15:0] rnd_val;
    lfsr_16bit u_lfsr (.clk(clk_25m), .reset(reset), .rnd(rnd_val));

    // ขยายศัตรูเป็น 16 ตัวทั่วแมพ!
    wire [95:0]  rocks_wx, rocks_wy;
    wire [7:0]   rocks_alive;
    wire [7:0]   rocks_cracked, rock_dna_active;
    wire [15:0]  rock_dna_types;
    wire [191:0] enemies_wx, enemies_wy;
    wire [15:0]  enemies_alive;
    wire [127:0] enemies_sz;
    wire [47:0]  enemies_hp, enemies_max_hp;
    wire [63:0]  enemies_dna;
    wire [15:0]  enemies_stun;
    wire [15:0]  enemies_e_shock;
    wire [15:0]  enemies_e_poison;
    wire [11:0]  dna_wx, dna_wy;
    wire         dna_active;
    wire [1:0]   dna_type;

    ecosystem_ai_and_collision #(
        .ELECTRIC_RADIUS(ELECTRIC_RADIUS),
        .STUN_FRAMES(STUN_FRAMES),
        .FREE_FRAMES(FREE_FRAMES),
        .POISON_RADIUS(POISON_RADIUS),
        .POISON_DAMAGE(POISON_DAMAGE),
        .POISON_TICK_FRAMES(POISON_TICK_FRAMES),
        .ATTACK_DAMAGE(ATTACK_DAMAGE),
        .MORE_DAMAGE_BONUS(MORE_DAMAGE_BONUS),
        .DASH_DAMAGE_BONUS(DASH_DAMAGE_BONUS),
        .ROCK_DROP_MASK(ROCK_DROP_MASK),
        .ROCK_BREAK_FRAMES(ROCK_BREAK_FRAMES),
        .DNA_PICKUP_DELAY_FRAMES(DNA_PICKUP_DELAY),
        .ENEMY_DROP_MASK(ENEMY_DROP_MASK),
        .BOSS_MAX_HP(BOSS_MAX_HP),
        .BOSS_SIZE(BOSS_SIZE),
        .BOSS_AGGRO_RANGE(BOSS_AGGRO_RANGE),
        .BOSS_ALERT_FRAMES(BOSS_ALERT_FRAMES),
        .BOSS_STALK_FRAMES_P1(BOSS_STALK_FRAMES_P1),
        .BOSS_STALK_FRAMES_P2(BOSS_STALK_FRAMES_P2),
        .BOSS_WARN_FRAMES_P1(BOSS_WARN_FRAMES_P1),
        .BOSS_WARN_FRAMES_P2(BOSS_WARN_FRAMES_P2),
        .BOSS_DASH_FRAMES_P1(BOSS_DASH_FRAMES_P1),
        .BOSS_DASH_FRAMES_P2(BOSS_DASH_FRAMES_P2),
        .BOSS_VULN_FRAMES_P1(BOSS_VULN_FRAMES_P1),
        .BOSS_VULN_FRAMES_P2(BOSS_VULN_FRAMES_P2),
        .BOSS_STUN_FRAMES(BOSS_STUN_FRAMES),
        .BOSS_STUN_IMMUNE_FRAMES(BOSS_STUN_IMMUNE_FRAMES),
        .BOSS_DASH_SPEED_P1(BOSS_DASH_SPEED_P1),
        .BOSS_DASH_SPEED_P2(BOSS_DASH_SPEED_P2),
        .BOSS_CONTACT_DMG(BOSS_CONTACT_DMG),
        .BOSS_DASH_DMG(BOSS_DASH_DMG)
    ) u_eco (
        .clk(clk_25m),
        .reset(game_rst),
        .frame_tick(game_tick),
        .game_state(run_state),
        .rnd_val(rnd_val),
        .unlocked_skills(unlocked_skills),
        .cam_x(cam_x),
        .cam_y(cam_y),
        .player_wx(player_wx),
        .player_wy(player_wy),
        .player_size(player_size),
        .facing_dir(facing_dir),
        .form_state(form_state),
        .is_god_mode(1'b0),
        .is_carnivore(is_carnivore),
        .dash_active(dash_active),
        .shock_active(shock_active),
        .poison_active(poison_active),
        .spike_unlocked(unlocked_skills[1]),
        .rocks_wx(rocks_wx),
        .rocks_wy(rocks_wy),
        .rocks_alive(rocks_alive),
        .rocks_cracked(rocks_cracked),
        .rock_dna_active(rock_dna_active),
        .rock_dna_types(rock_dna_types),
        .enemies_wx(enemies_wx),
        .enemies_wy(enemies_wy),
        .enemies_alive(enemies_alive),
        .enemies_sz(enemies_sz),
        .enemies_hp(enemies_hp),
        .enemies_max_hp(enemies_max_hp),
        .enemies_dna(enemies_dna),
        .enemies_stun(enemies_stun),
        .enemies_e_shock(enemies_e_shock),
        .enemies_e_poison(enemies_e_poison),
        .dna_wx(dna_wx),
        .dna_wy(dna_wy),
        .dna_active(dna_active),
        .dna_type(dna_type),
        .eat_gain(eat_gain),
        .collect_dna(collect_dna),
        .collect_dna_type(collect_dna_type),
        .damage_amount(damage_amount),
        .boss_wx(boss_wx),
        .boss_wy(boss_wy),
        .boss_size(boss_size),
        .boss_active(boss_active),
        .boss_defeated(boss_defeated),
        .boss_hp(boss_hp),
        .boss_max_hp(boss_max_hp),
        .boss_state(boss_state),
        .boss_phase2(boss_phase2),
        .boss_alert_tmr(boss_alert_tmr),
        .boss_hit_flash_tmr(boss_hit_flash_tmr)
    );

    // Focus on the spawn point. Slide the rendered sprite in without moving its hitbox.
    wire [6:0] intro_slide_frames = (boss_intro_left > 7'd70) ? boss_intro_left - 7'd70 : 7'd0;
    wire [11:0] intro_slide = {2'b00, intro_slide_frames, 3'b000};
    wire [11:0] intro_x_base = (boss_wx > 12'd230) ? boss_wx - 12'd230 : 12'd0;
    wire [11:0] intro_cam_x = intro_x_base + ((boss_intro_left > 7'd96 && boss_intro_left[1]) ? 12'd4 : 12'd0);
    wire [11:0] intro_cam_y = (boss_wy > 12'd250) ? boss_wy - 12'd250 : 12'd0;
    wire [11:0] render_cam_x = boss_intro ? intro_cam_x : cam_x;
    wire [11:0] render_cam_y = boss_intro ? intro_cam_y : cam_y;
    wire [11:0] render_boss_wx = boss_intro ? boss_wx + intro_slide : boss_wx;

    wire [11:0] rgb_out;
    sprite_renderer #(.USE_TILE_MAP(USE_TILE_MAP), .PLAYER_PAD(PLAYER_DRAW_PAD)) u_render (
        .clk_25m(clk_25m),
        .video_on(video_on),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .cam_x(render_cam_x),
        .cam_y(render_cam_y),
        .game_state(render_state),
        .form_state(form_state),
        .unlocked_skills(unlocked_skills),
        .facing_dir(facing_dir),
        .is_carnivore(is_carnivore),
        .egg_taps(egg_taps),
        .egg_fx(egg_fx),
        .player_moving(player_moving),
        .wake_reset(game_rst),
        .wake_tick(game_tick),
        .wake_enabled(state == PLAY),
        .shock_active(shock_active),
        .poison_active(poison_active),
        .shock_cd_sec(shock_cd_sec),
        .poison_cd_sec(poison_cd_sec),
        .dash_cd_sec(dash_cd_sec),
        .player_hp(player_hp),
        .player_size(player_size),
        .player_wx(player_wx),
        .player_wy(player_wy),
        .rocks_wx(rocks_wx),
        .rocks_wy(rocks_wy),
        .rocks_alive(rocks_alive),
        .rocks_cracked(rocks_cracked),
        .rock_dna_active(rock_dna_active),
        .rock_dna_types(rock_dna_types),
        .enemies_wx(enemies_wx),
        .enemies_wy(enemies_wy),
        .enemies_alive(enemies_alive),
        .enemies_sz(enemies_sz),
        .enemies_dna(enemies_dna),
        .enemies_stun(enemies_stun),
        .enemies_e_shock(enemies_e_shock),
        .enemies_e_poison(enemies_e_poison),
        .dna_wx(dna_wx),
        .dna_wy(dna_wy),
        .dna_active(dna_active),
        .dna_type(dna_type),
        .boss_wx(render_boss_wx),
        .boss_wy(boss_wy),
        .boss_size(boss_size),
        .boss_active(boss_active),
        .boss_state(boss_state),
        .boss_phase2(boss_phase2),
        .boss_alert(boss_intro && boss_intro_left != 7'd0 && boss_intro_left <= 7'd88 && boss_alert_tmr != 8'd0),
        .boss_hit_flash(boss_hit_flash_tmr != 6'd0),
        .rgb_out(rgb_out)
    );

    // ------------------------------------------------------------------
    // Scan one enemy per clock during vertical blanking. Use distance from
    // the two bodies' edges, so all five sizes feel similarly responsive.
    reg target_scan_active, target_found, target_valid;
    reg [3:0] scan_enemy, best_enemy, target_enemy;
    reg [11:0] best_distance;
    wire [7:0] scan_size = enemies_sz[{scan_enemy, 3'd0} +: 8];
    wire [11:0] scan_x = enemies_wx[12*scan_enemy +: 12] + {5'd0, scan_size[7:1]};
    wire [11:0] scan_y = enemies_wy[12*scan_enemy +: 12] + {5'd0, scan_size[7:1]};
    wire [11:0] target_pc_x = player_wx + {5'd0, player_size[7:1]};
    wire [11:0] target_pc_y = player_wy + {5'd0, player_size[7:1]};
    wire [11:0] target_dx = (scan_x >= target_pc_x) ? scan_x - target_pc_x : target_pc_x - scan_x;
    wire [11:0] target_dy = (scan_y >= target_pc_y) ? scan_y - target_pc_y : target_pc_y - scan_y;
    wire [11:0] center_distance = (target_dx > target_dy) ? target_dx : target_dy;
    wire [11:0] body_radii = {5'd0, player_size[7:1]} + {5'd0, scan_size[7:1]};
    wire [11:0] target_distance = (center_distance > body_radii) ? center_distance - body_radii : 12'd0;
    wire is_candidate = enemies_alive[scan_enemy] && (target_distance <= 12'd48);
    wire closer_enemy = is_candidate && (!target_found || target_distance < best_distance);

    always @(posedge clk_25m) begin
        if (game_rst || state != PLAY) begin
            target_scan_active <= 1'b0;
            target_valid <= 1'b0;
        end else if (frame_tick) begin
            target_scan_active <= 1'b1;
            scan_enemy <= 4'd0;
            target_found <= 1'b0;
        end else if (target_scan_active) begin
            if (closer_enemy) begin
                target_found <= 1'b1;
                best_enemy <= scan_enemy;
                best_distance <= target_distance;
            end
            if (scan_enemy == 4'd15) begin
                target_scan_active <= 1'b0;
                target_valid <= target_found || is_candidate;
                target_enemy <= closer_enemy ? scan_enemy : best_enemy;
            end else begin
                scan_enemy <= scan_enemy + 4'd1;
            end
        end
    end

    wire [7:0] target_size = enemies_sz[{target_enemy, 3'd0} +: 8];
    wire [2:0] enemy_target_type = (target_size <= 8'd16) ? 3'd0 :
                                   (target_size <= 8'd24) ? 3'd1 :
                                   (target_size <= 8'd60) ? 3'd2 :
                                   (target_size <= 8'd100) ? 3'd3 : 3'd4;
    wire [11:0] boss_cx_t    = boss_wx + {5'd0, boss_size[7:1]};
    wire [11:0] boss_cy_t    = boss_wy + {5'd0, boss_size[7:1]};
    wire [11:0] boss_dx_t    = (boss_cx_t >= target_pc_x) ? (boss_cx_t - target_pc_x) : (target_pc_x - boss_cx_t);
    wire [11:0] boss_dy_t    = (boss_cy_t >= target_pc_y) ? (boss_cy_t - target_pc_y) : (target_pc_y - boss_cy_t);
    wire [11:0] boss_cheb_t  = (boss_dx_t > boss_dy_t) ? boss_dx_t : boss_dy_t;
    wire [11:0] boss_radii_t = {5'd0, player_size[7:1]} + {5'd0, boss_size[7:1]};
    wire [11:0] boss_dist_t  = (boss_cheb_t > boss_radii_t) ? (boss_cheb_t - boss_radii_t) : 12'd0;
    wire        boss_banner_show = !boss_intro && boss_active && (boss_dist_t <= BOSS_AGGRO_RANGE) && (state == PLAY);

    wire [2:0] target_type   = boss_banner_show ? 3'd4 : enemy_target_type;
    wire       target_show   = !boss_intro && (boss_banner_show || (target_valid && enemies_alive[target_enemy] && state == PLAY));
    wire [5:0] target_hp     = boss_banner_show ? boss_hp : {3'd0, enemies_hp[3*target_enemy +: 3]};
    wire [5:0] target_max_hp = boss_banner_show ? boss_max_hp : {3'd0, enemies_max_hp[3*target_enemy +: 3]};
    wire [2:0] menu_page = menu_open ? {1'b0, menu_screen} :
                           (state == WIN) ? 3'd5 : (state == GAME_OVER) ? 3'd6 :
                           cursor ? 3'd4 : {1'b0, CHOOSE};
    wire [1:0] highlighted_item = menu_item;
    wire menu_video, banner_video;
    wire [11:0] menu_rgb, banner_rgb;
    menu_screens u_menu_screens (
        .clk(clk_25m),
        .reset(game_rst),
        .frame_tick(frame_tick),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .show_screen(menu_open || state == SELECT || state == WIN || state == GAME_OVER),
        .screen_page(menu_page),
        .highlight(highlighted_item),
        .best_score(best_score),
        .last_score(last_score),
        .show_banner(target_show),
        .banner_type(target_type),
        .banner_hp(target_hp),
        .banner_max_hp(target_max_hp),
        .banner_active(banner_video),
        .banner_rgb(banner_rgb),
        .active(menu_video),
        .rgb(menu_rgb)
    );

    wire [11:0] final_rgb = menu_video ? menu_rgb : banner_video ? banner_rgb : rgb_out;

    assign VGA_R = final_rgb[11:8];
    assign VGA_G = final_rgb[7:4];
    assign VGA_B = final_rgb[3:0];

    peripherals_driver u_periph (
        .clk(clk_25m),
        .reset(reset),
        .form_state(form_state),
        .is_god_mode(is_win),
        .unlocked_skills(unlocked_skills),
        .score(score),
        .player_hp(player_hp),
        .LED(LED),
        .LED16_R(LED16_R), .LED16_G(LED16_G), .LED16_B(LED16_B),
        .CA(CA), .CB(CB), .CC(CC), .CD(CD), .CE(CE), .CF(CF), .CG(CG), .DP(DP),
        .AN(AN)
    );

endmodule
