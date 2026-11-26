module ecosystem_ai_and_collision #(
    // ----- tuning values (set from top_game.v) -----
    parameter [11:0] ELECTRIC_RADIUS    = 12'd24,   // ELECTRIC circle: pixels added to the body radius
    parameter integer STUN_FRAMES       = 240,      // ELECTRIC stun time
    parameter integer FREE_FRAMES       = 60,       // free time after a stun
    parameter [11:0] POISON_RADIUS      = 12'd24,   // POISON circle: pixels added to the body radius
    parameter [2:0]  POISON_DAMAGE      = 3'd1,     // damage per poison tick
    parameter [5:0]  POISON_TICK_FRAMES = 6'd30,    // frames between poison ticks
    parameter [2:0]  ATTACK_DAMAGE      = 3'd1,     // body attack damage
    parameter [2:0]  MORE_DAMAGE_BONUS  = 3'd1,     // extra damage with the MORE DAMAGE skill
    parameter [2:0]  DASH_DAMAGE_BONUS  = 3'd1,     // extra damage while dashing
    parameter [3:0]  ROCK_DROP_MASK     = 4'b0001,  // herbivore: DNA chance from a rock = 1 / 2^(number of 1 bits)
    parameter [6:0]  ROCK_BREAK_FRAMES  = 7'd120,   // cracked rock lifetime in game frames
    parameter [5:0]  DNA_PICKUP_DELAY_FRAMES = 6'd12, // a new DNA cannot be picked up for this many frames
    parameter [2:0]  ENEMY_DROP_MASK    = 3'b111,   // carnivore: DNA chance from an enemy = 1 / 2^(number of 1 bits)
    // ----- final boss (Giant TOTO) tuning -----
    parameter [5:0]  BOSS_MAX_HP             = 6'd16,
    parameter [7:0]  BOSS_SIZE               = 8'd180,
    parameter [11:0] BOSS_AGGRO_RANGE        = 12'd240,
    parameter [7:0]  BOSS_ALERT_FRAMES       = 8'd180,
    parameter [8:0]  BOSS_STALK_FRAMES_P1    = 9'd90,
    parameter [8:0]  BOSS_STALK_FRAMES_P2    = 9'd30,
    parameter [8:0]  BOSS_WARN_FRAMES_P1     = 9'd45,
    parameter [8:0]  BOSS_WARN_FRAMES_P2     = 9'd30,
    parameter [8:0]  BOSS_DASH_FRAMES_P1     = 9'd24,
    parameter [8:0]  BOSS_DASH_FRAMES_P2     = 9'd24,
    parameter [8:0]  BOSS_VULN_FRAMES_P1     = 9'd120,
    parameter [8:0]  BOSS_VULN_FRAMES_P2     = 9'd90,
    parameter [8:0]  BOSS_STUN_FRAMES        = 9'd120,
    parameter [8:0]  BOSS_STUN_IMMUNE_FRAMES = 9'd180,
    parameter [5:0]  BOSS_DASH_SPEED_P1      = 6'd5,
    parameter [5:0]  BOSS_DASH_SPEED_P2      = 6'd6,
    parameter [3:0]  BOSS_CONTACT_DMG        = 4'd1,
    parameter [3:0]  BOSS_DASH_DMG           = 4'd2
)(
    input  wire         clk,
    input  wire         reset,
    input  wire         frame_tick,
    input  wire [1:0]   game_state,
    input  wire [15:0]  rnd_val,
    input  wire [3:0]   unlocked_skills,
    input  wire [11:0]  cam_x,
    input  wire [11:0]  cam_y,
    input  wire [11:0]  player_wx,
    input  wire [11:0]  player_wy,
    input  wire [7:0]   player_size,
    input  wire [1:0]   facing_dir,
    input  wire [2:0]   form_state,
    input  wire         is_god_mode,
    input  wire         is_carnivore,   // 1 = carnivore (DNA from kills), 0 = herbivore (DNA from rocks)
    input  wire         dash_active,
    input  wire         shock_active,
    input  wire         poison_active,
    input  wire         spike_unlocked,
    output wire [95:0]  rocks_wx,
    output wire [95:0]  rocks_wy,
    output reg  [7:0]   rocks_alive,
    output wire [7:0]   rocks_cracked,   // 1 = show the cracked rock picture
    output reg  [7:0]   rock_dna_active,
    output wire [15:0]  rock_dna_types,
    output wire [191:0] enemies_wx,
    output wire [191:0] enemies_wy,
    output reg  [15:0]  enemies_alive,
    output wire [127:0] enemies_sz,
    output wire [47:0]  enemies_hp,
    output wire [47:0]  enemies_max_hp,
    output wire [63:0]  enemies_dna,
    output wire [15:0]  enemies_stun,
    output wire [15:0]  enemies_e_shock,
    output wire [15:0]  enemies_e_poison,
    output reg  [11:0]  dna_wx,
    output reg  [11:0]  dna_wy,
    output reg          dna_active,
    output reg  [1:0]   dna_type,
    output reg  [1:0]   eat_gain,
    output reg          collect_dna,
    output reg  [1:0]   collect_dna_type,
    output reg  [3:0]   damage_amount,
    output reg  [11:0]  boss_wx,
    output reg  [11:0]  boss_wy,
    output wire [7:0]   boss_size,
    output reg          boss_active,
    output reg          boss_defeated,
    output reg  [5:0]   boss_hp,
    output wire [5:0]   boss_max_hp,
    output wire [2:0]   boss_state,
    output wire         boss_phase2,
    output reg  [7:0]   boss_alert_tmr,
    output reg  [5:0]   boss_hit_flash_tmr
);

    reg [11:0] rock_x [0:7];
    reg [11:0] rock_y [0:7];
    reg [6:0]  rock_brk [0:7];     // frame ticks remaining before the rock vanishes
    reg [7:0]  rock_breaking;
    reg [1:0]  rock_dna_type [0:7];
    reg [5:0]  dna_wait;           // frames before dropped enemy DNA can be picked up
    reg        dna_active_d;

    assign rocks_cracked = rock_breaking;
    genvar rock_slot;
    generate
        for (rock_slot = 0; rock_slot < 8; rock_slot = rock_slot + 1) begin : gen_rock_dna_types
            assign rock_dna_types[2*rock_slot +: 2] = rock_dna_type[rock_slot];
        end
    endgenerate

    reg [11:0] enemy_x [0:15];
    reg [11:0] enemy_y [0:15];
    reg [7:0]  enemy_size [0:15];
    reg [2:0]  enemy_hp [0:15];
    reg [2:0]  enemy_max_hp [0:15];
    reg [3:0]  enemy_dna_reg [0:15];
    reg [7:0]  enemy_skill_tmr [0:15];
    reg [8:0]  enemy_skill_cd [0:15];
    reg        enemy_skill_mode [0:15];
    // เก็บเป้าหมายเหยื่อที่ล็อกไว้ของแต่ละตัว (ลดการใช้ LUT จาก 256 คู่ เหลือ 1 คู่/เฟรม)
    reg [3:0]  enemy_prey_idx [0:15];
    reg        enemy_has_prey [0:15];

    assign rocks_wx = {rock_x[7], rock_x[6], rock_x[5], rock_x[4], rock_x[3], rock_x[2], rock_x[1], rock_x[0]};
    assign rocks_wy = {rock_y[7], rock_y[6], rock_y[5], rock_y[4], rock_y[3], rock_y[2], rock_y[1], rock_y[0]};

    assign enemies_wx = {enemy_x[15], enemy_x[14], enemy_x[13], enemy_x[12], enemy_x[11], enemy_x[10], enemy_x[9], enemy_x[8],
                         enemy_x[7],  enemy_x[6],  enemy_x[5],  enemy_x[4],  enemy_x[3],  enemy_x[2],  enemy_x[1], enemy_x[0]};
    assign enemies_wy = {enemy_y[15], enemy_y[14], enemy_y[13], enemy_y[12], enemy_y[11], enemy_y[10], enemy_y[9], enemy_y[8],
                         enemy_y[7],  enemy_y[6],  enemy_y[5],  enemy_y[4],  enemy_y[3],  enemy_y[2],  enemy_y[1], enemy_y[0]};
    assign enemies_sz = {enemy_size[15], enemy_size[14], enemy_size[13], enemy_size[12], enemy_size[11], enemy_size[10], enemy_size[9], enemy_size[8],
                         enemy_size[7],  enemy_size[6],  enemy_size[5],  enemy_size[4],  enemy_size[3],  enemy_size[2],  enemy_size[1], enemy_size[0]};
    genvar health_slot;
    generate
        for (health_slot = 0; health_slot < 16; health_slot = health_slot + 1) begin : gen_max_hp
            assign enemies_max_hp[3*health_slot +: 3] = enemy_max_hp[health_slot];
        end
    endgenerate

    assign enemies_hp = {enemy_hp[15], enemy_hp[14], enemy_hp[13], enemy_hp[12], enemy_hp[11], enemy_hp[10], enemy_hp[9], enemy_hp[8],
                         enemy_hp[7],  enemy_hp[6],  enemy_hp[5],  enemy_hp[4],  enemy_hp[3],  enemy_hp[2],  enemy_hp[1], enemy_hp[0]};
    assign enemies_dna = {enemy_dna_reg[15], enemy_dna_reg[14], enemy_dna_reg[13], enemy_dna_reg[12],
                          enemy_dna_reg[11], enemy_dna_reg[10], enemy_dna_reg[9],  enemy_dna_reg[8],
                          enemy_dna_reg[7],  enemy_dna_reg[6],  enemy_dna_reg[5],  enemy_dna_reg[4],
                          enemy_dna_reg[3],  enemy_dna_reg[2],  enemy_dna_reg[1],  enemy_dna_reg[0]};

    wire [15:0] e_stunned;   // enemy_fsm is in STUN
    wire [15:0] e_chase;     // enemy_fsm is in CHASE
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_flags
            assign enemies_stun[g]     = e_stunned[g];
            assign enemies_e_shock[g]  = (enemy_skill_tmr[g] > 8'd0) && !enemy_skill_mode[g];
            assign enemies_e_poison[g] = (enemy_skill_tmr[g] > 8'd0) &&  enemy_skill_mode[g];
        end
    endgenerate

    reg [5:0] hit_cd;
    reg [5:0] invuln_cd;
    reg [5:0] poison_tick_cd;
    reg [8:0] player_stun_tmr;
    reg [2:0] ai_tick_div;
    reg [3:0] spawn_idx;
    reg [3:0] scan_j; // ตัวนับสแกนเหยื่อทีละ 1 ตัวต่อเฟรม

    function check_aabb;
        input [11:0] ax, ay;
        input [7:0]  asize;
        input [11:0] bx, by;
        input [7:0]  bsize;
        begin
            check_aabb = (ax < bx + {4'd0, bsize}) && (ax + {4'd0, asize} > bx) &&
                         (ay < by + {4'd0, bsize}) && (ay + {4'd0, asize} > by);
        end
    endfunction

    wire [7:0]  spike_len = spike_unlocked ? ((player_size >> 1) + 8'd8) : 8'd0;
    wire [11:0] spk_x = (facing_dir == 2'd1) ? (player_wx + {4'd0, player_size}) :
                        (facing_dir == 2'd3) ? ((player_wx > {4'd0, spike_len}) ? (player_wx - {4'd0, spike_len}) : 12'd0) :
                                               (player_wx + {6'd0, player_size[7:2]});
    wire [11:0] spk_y = (facing_dir == 2'd2) ? (player_wy + {4'd0, player_size}) :
                        (facing_dir == 2'd0) ? ((player_wy > {4'd0, spike_len}) ? (player_wy - {4'd0, spike_len}) : 12'd0) :
                                               (player_wy + {6'd0, player_size[7:2]});
    wire [7:0]  spk_w = (facing_dir == 2'd1 || facing_dir == 2'd3) ? spike_len : (player_size >> 1);
    wire [7:0]  spk_h = (facing_dir == 2'd0 || facing_dir == 2'd2) ? spike_len : (player_size >> 1);

    function check_aabb_rect;
        input [11:0] ax, ay;
        input [7:0]  aw, ah;
        input [11:0] bx, by;
        input [7:0]  bsize;
        begin
            check_aabb_rect = (ax < bx + {4'd0, bsize}) && (ax + {4'd0, aw} > bx) &&
                              (ay < by + {4'd0, bsize}) && (ay + {4'd0, ah} > by);
        end
    endfunction

    wire [2:0]  base_atk    = ATTACK_DAMAGE + (spike_unlocked ? MORE_DAMAGE_BONUS : 3'd0) + (dash_active ? DASH_DAMAGE_BONUS : 3'd0);
    wire [11:0] p_cx        = player_wx + {5'd0, player_size[7:1]};
    wire [11:0] p_cy        = player_wy + {5'd0, player_size[7:1]};
    wire [11:0] electric_radius = {5'd0, player_size[7:1]} + ELECTRIC_RADIUS;
    wire [11:0] poison_radius   = {5'd0, player_size[7:1]} + POISON_RADIUS;

    reg [11:0] e_cx, e_cy, dist_x, dist_y;
    reg [11:0] e_aura_r;
    reg [7:0]  size_diff;
    reg [4:0]  calc_dmg;
    reg [8:0]  spawned_sz_calc;
    reg [11:0] ai_step;
    reg [3:0]  avail_dna;
    reg        hit_by_spike, hit_by_body, can_attack;
    reg        pickup_claimed;
    reg        in_screen_view;
    reg [11:0] prey_dx, prey_dy;
    reg [3:0]  p_idx;

    // ------------------------------------------------------------------
    // One enemy_fsm per enemy: WANDER / CHASE / STUN / FREE
    // Range values and FREE behaviour (moves like WANDER) are assumptions, not team decisions yet.
    // ------------------------------------------------------------------
    localparam [11:0] NEAR_X = 12'd320, NEAR_Y = 12'd240;   // player inside this box: near
    localparam [11:0] FAR_X  = 12'd400, FAR_Y  = 12'd300;   // player outside this box: far (> near)

    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_enemy_fsm
            wire [11:0] ecx = enemy_x[g] + {5'd0, enemy_size[g][7:1]};
            wire [11:0] ecy = enemy_y[g] + {5'd0, enemy_size[g][7:1]};
            wire [11:0] adx = (p_cx > ecx) ? (p_cx - ecx) : (ecx - p_cx);
            wire [11:0] ady = (p_cy > ecy) ? (p_cy - ecy) : (ecy - p_cy);
            wire in_el  = shock_active && enemies_alive[g] &&
                          (adx < electric_radius + {5'd0, enemy_size[g][7:1]}) &&
                          (ady < electric_radius + {5'd0, enemy_size[g][7:1]});
            wire near_p = (adx < NEAR_X) && (ady < NEAR_Y);
            wire far_p  = (adx >= FAR_X) || (ady >= FAR_Y);
            wire [1:0] mode;

            enemy_fsm #(.STUN_FRAMES(STUN_FRAMES), .FREE_FRAMES(FREE_FRAMES)) u_enemy_fsm (
                .clk        (clk),
                .rst        (reset),
                .frame_tick (frame_tick),
                .active     ((game_state != 2'd0) && enemies_alive[g]),  // frozen (not reset) while paused
                .near       (near_p),
                .far        (far_p),
                .in_electric(in_el),
                .mode       (mode),
                .is_stunned (e_stunned[g])
            );
            assign e_chase[g] = (mode == 2'd1);
        end
    endgenerate

    // ------------------------------------------------------------------
    // Final Boss (Giant TOTO): spawns once per round when all 4 DNA are unlocked
    // ------------------------------------------------------------------
    assign boss_size   = BOSS_SIZE;
    assign boss_max_hp = BOSS_MAX_HP;

    localparam [11:0] BOSS_POS_MIN    = 12'd16;
    localparam [11:0] BOSS_POS_MAX    = 12'd2048 - {4'd0, BOSS_SIZE} - 12'd16;
    localparam [11:0] BOSS_SPAWN_HIGH = (12'd1500 > BOSS_POS_MAX) ? BOSS_POS_MAX : 12'd1500;
    localparam [11:0] BOSS_SPAWN_LOW  = (12'd320  < BOSS_POS_MIN) ? BOSS_POS_MIN : 12'd320;

    reg        boss_spawned;
    reg signed [5:0] boss_dash_vx, boss_dash_vy;
    reg        player_hit_this_clk;
    reg        boss_poison_hit, boss_direct_hit, boss_hit_by_body, boss_hit_by_spike;
    reg [5:0]  boss_dmg_this_clk;

    wire [11:0] boss_cx = boss_wx + {5'd0, BOSS_SIZE[7:1]};
    wire [11:0] boss_cy = boss_wy + {5'd0, BOSS_SIZE[7:1]};
    wire [11:0] boss_dx = (p_cx > boss_cx) ? (p_cx - boss_cx) : (boss_cx - p_cx);
    wire [11:0] boss_dy = (p_cy > boss_cy) ? (p_cy - boss_cy) : (boss_cy - p_cy);
    wire [11:0] boss_cheb = (boss_dx > boss_dy) ? boss_dx : boss_dy;
    wire [11:0] boss_radii = {5'd0, player_size[7:1]} + {5'd0, BOSS_SIZE[7:1]};
    wire [11:0] boss_edge_dist = (boss_cheb > boss_radii) ? (boss_cheb - boss_radii) : 12'd0;
    wire        boss_in_range = boss_active && (boss_edge_dist <= BOSS_AGGRO_RANGE);
    wire        boss_in_electric = shock_active && boss_active &&
                                   (boss_dx < electric_radius + {5'd0, BOSS_SIZE[7:1]}) &&
                                   (boss_dy < electric_radius + {5'd0, BOSS_SIZE[7:1]});
    assign      boss_phase2 = boss_active && (boss_hp <= (BOSS_MAX_HP >> 1));

    wire boss_is_telegraph, boss_is_dashing, boss_is_vuln, boss_is_stunned, boss_telegraph_start;
    boss_fsm #(
        .STALK_FRAMES_P1   (BOSS_STALK_FRAMES_P1),
        .STALK_FRAMES_P2   (BOSS_STALK_FRAMES_P2),
        .WARN_FRAMES_P1    (BOSS_WARN_FRAMES_P1),
        .WARN_FRAMES_P2    (BOSS_WARN_FRAMES_P2),
        .DASH_FRAMES_P1    (BOSS_DASH_FRAMES_P1),
        .DASH_FRAMES_P2    (BOSS_DASH_FRAMES_P2),
        .VULN_FRAMES_P1    (BOSS_VULN_FRAMES_P1),
        .VULN_FRAMES_P2    (BOSS_VULN_FRAMES_P2),
        .STUN_FRAMES       (BOSS_STUN_FRAMES),
        .STUN_IMMUNE_FRAMES(BOSS_STUN_IMMUNE_FRAMES)
    ) u_boss_fsm (
        .clk            (clk),
        .rst            (reset),
        .frame_tick     (frame_tick),
        .active         ((game_state != 2'd0) && boss_active),
        .in_range       (boss_in_range),
        .in_electric    (boss_in_electric),
        .phase2         (boss_phase2),
        .state_out      (boss_state),
        .is_telegraph   (boss_is_telegraph),
        .is_dashing     (boss_is_dashing),
        .is_vuln        (boss_is_vuln),
        .is_stunned     (boss_is_stunned),
        .telegraph_start(boss_telegraph_start)
    );

    wire [5:0] boss_dash_spd = boss_phase2 ? BOSS_DASH_SPEED_P2 : BOSS_DASH_SPEED_P1;
    reg  [5:0] boss_mag_x, boss_mag_y;
    always @(*) begin
        if (boss_dx < 12'd4 && boss_dy < 12'd4) begin
            boss_mag_x = boss_dash_spd;
            boss_mag_y = 6'd0;
        end else if (boss_dx >= boss_dy) begin
            boss_mag_x = boss_dash_spd;
            if (boss_dy >= (boss_dx >> 1))      boss_mag_y = (boss_dash_spd > 6'd1) ? (boss_dash_spd - 6'd1) : 6'd1;
            else if (boss_dy >= (boss_dx >> 2)) boss_mag_y = (boss_dash_spd >> 1);
            else                                boss_mag_y = 6'd0;
        end else begin
            boss_mag_y = boss_dash_spd;
            if (boss_dx >= (boss_dy >> 1))      boss_mag_x = (boss_dash_spd > 6'd1) ? (boss_dash_spd - 6'd1) : 6'd1;
            else if (boss_dx >= (boss_dy >> 2)) boss_mag_x = (boss_dash_spd >> 1);
            else                                boss_mag_x = 6'd0;
        end
    end
    wire signed [5:0] boss_dash_vx_next = (p_cx >= boss_cx) ? $signed({1'b0, boss_mag_x[4:0]}) : -$signed({1'b0, boss_mag_x[4:0]});
    wire signed [5:0] boss_dash_vy_next = (p_cy >= boss_cy) ? $signed({1'b0, boss_mag_y[4:0]}) : -$signed({1'b0, boss_mag_y[4:0]});
    wire signed [13:0] boss_next_wx = $signed({2'b00, boss_wx}) + $signed({{8{boss_dash_vx[5]}}, boss_dash_vx});
    wire signed [13:0] boss_next_wy = $signed({2'b00, boss_wy}) + $signed({{8{boss_dash_vy[5]}}, boss_dash_vy});

    integer i;
    // synchronous reset so game_state never drives an async reset pin
    always @(posedge clk) begin
        if (reset || game_state == 2'd0) begin
            rock_x[0] <= 12'd880;  rock_y[0] <= 12'd900;
            rock_x[1] <= 12'd1160; rock_y[1] <= 12'd920;
            rock_x[2] <= 12'd900;  rock_y[2] <= 12'd1150;
            rock_x[3] <= 12'd1180; rock_y[3] <= 12'd1140;
            rock_x[4] <= 12'd600;  rock_y[4] <= 12'd700;
            rock_x[5] <= 12'd1450; rock_y[5] <= 12'd750;
            rock_x[6] <= 12'd650;  rock_y[6] <= 12'd1400;
            rock_x[7] <= 12'd1500; rock_y[7] <= 12'd1420;
            rocks_alive <= 8'b1111_1111;
            rock_breaking <= 8'd0;
            rock_dna_active <= 8'd0;
            for (i = 0; i < 8; i = i + 1) begin
                rock_brk[i] <= 7'd0;
                rock_dna_type[i] <= 2'd0;
            end
            dna_wait     <= 6'd0;
            dna_active_d <= 1'b0;

            enemy_x[0]  <= 12'd850;  enemy_y[0]  <= 12'd1020; enemy_size[0]  <= 8'd12;  enemy_hp[0]  <= 3'd2; enemy_max_hp[0] <= 3'd2; enemy_dna_reg[0]  <= 4'b0001;
            enemy_x[1]  <= 12'd1200; enemy_y[1]  <= 12'd1040; enemy_size[1]  <= 8'd14;  enemy_hp[1]  <= 3'd2; enemy_max_hp[1] <= 3'd2; enemy_dna_reg[1]  <= 4'b0010;
            enemy_x[2]  <= 12'd1020; enemy_y[2]  <= 12'd840;  enemy_size[2]  <= 8'd12;  enemy_hp[2]  <= 3'd2; enemy_max_hp[2] <= 3'd2; enemy_dna_reg[2]  <= 4'b0100;
            enemy_x[3]  <= 12'd750;  enemy_y[3]  <= 12'd1050; enemy_size[3]  <= 8'd15;  enemy_hp[3]  <= 3'd3; enemy_max_hp[3] <= 3'd3; enemy_dna_reg[3]  <= 4'b1000;
            enemy_x[4]  <= 12'd800;  enemy_y[4]  <= 12'd830;  enemy_size[4]  <= 8'd48;  enemy_hp[4]  <= 3'd4; enemy_max_hp[4] <= 3'd4; enemy_dna_reg[4]  <= 4'b0101;
            enemy_x[5]  <= 12'd1230; enemy_y[5]  <= 12'd1180; enemy_size[5]  <= 8'd76;  enemy_hp[5]  <= 3'd5; enemy_max_hp[5] <= 3'd5; enemy_dna_reg[5]  <= 4'b1010;
            enemy_x[6]  <= 12'd960;  enemy_y[6]  <= 12'd1240; enemy_size[6]  <= 8'd110; enemy_hp[6]  <= 3'd6; enemy_max_hp[6] <= 3'd6; enemy_dna_reg[6]  <= 4'b1100;
            enemy_x[7]  <= 12'd1280; enemy_y[7]  <= 12'd860;  enemy_size[7]  <= 8'd140; enemy_hp[7]  <= 3'd7; enemy_max_hp[7] <= 3'd7; enemy_dna_reg[7]  <= 4'b1111;
            enemy_x[8]  <= 12'd300;  enemy_y[8]  <= 12'd320;  enemy_size[8]  <= 8'd16;  enemy_hp[8]  <= 3'd2; enemy_max_hp[8] <= 3'd2; enemy_dna_reg[8]  <= 4'b0001;
            enemy_x[9]  <= 12'd1700; enemy_y[9]  <= 12'd350;  enemy_size[9]  <= 8'd20;  enemy_hp[9]  <= 3'd3; enemy_max_hp[9] <= 3'd3; enemy_dna_reg[9]  <= 4'b0010;
            enemy_x[10] <= 12'd350;  enemy_y[10] <= 12'd1680; enemy_size[10] <= 8'd18;  enemy_hp[10] <= 3'd3; enemy_max_hp[10] <= 3'd3; enemy_dna_reg[10] <= 4'b0100;
            enemy_x[11] <= 12'd1650; enemy_y[11] <= 12'd1700; enemy_size[11] <= 8'd24;  enemy_hp[11] <= 3'd3; enemy_max_hp[11] <= 3'd3; enemy_dna_reg[11] <= 4'b1000;
            enemy_x[12] <= 12'd450;  enemy_y[12] <= 12'd950;  enemy_size[12] <= 8'd56;  enemy_hp[12] <= 3'd5; enemy_max_hp[12] <= 3'd5; enemy_dna_reg[12] <= 4'b0110;
            enemy_x[13] <= 12'd1600; enemy_y[13] <= 12'd980;  enemy_size[13] <= 8'd64;  enemy_hp[13] <= 3'd5; enemy_max_hp[13] <= 3'd5; enemy_dna_reg[13] <= 4'b1001;
            enemy_x[14] <= 12'd1000; enemy_y[14] <= 12'd350;  enemy_size[14] <= 8'd90;  enemy_hp[14] <= 3'd6; enemy_max_hp[14] <= 3'd6; enemy_dna_reg[14] <= 4'b1101;
            enemy_x[15] <= 12'd1050; enemy_y[15] <= 12'd1650; enemy_size[15] <= 8'd120; enemy_hp[15] <= 3'd7; enemy_max_hp[15] <= 3'd7; enemy_dna_reg[15] <= 4'b1111;
            enemies_alive <= 16'hFFFF;

            for (i = 0; i < 16; i = i + 1) begin
                enemy_skill_tmr[i]  <= 8'd0;
                enemy_skill_cd[i]   <= 9'd100 + ({5'd0, i[3:0]} * 9'd20);
                enemy_skill_mode[i] <= i[0];
                enemy_prey_idx[i]   <= 4'd0;
                enemy_has_prey[i]   <= 1'b0;
            end

            dna_active       <= 1'b0;
            dna_type         <= 2'd0;
            eat_gain         <= 2'd0;
            collect_dna      <= 1'b0;
            collect_dna_type <= 2'd0;
            damage_amount    <= 4'd0;
            hit_cd           <= 6'd0;
            invuln_cd        <= 6'd0;
            poison_tick_cd   <= 6'd0;
            player_stun_tmr  <= 9'd0;
            ai_tick_div      <= 3'd0;
            spawn_idx        <= 4'd0;
            scan_j           <= 4'd0;

            boss_wx            <= 12'd1500;
            boss_wy            <= 12'd1500;
            boss_spawned       <= 1'b0;
            boss_active        <= 1'b0;
            boss_defeated      <= 1'b0;
            boss_hp            <= 6'd0;
            boss_alert_tmr     <= 8'd0;
            boss_hit_flash_tmr <= 6'd0;
            boss_dash_vx       <= 6'sd0;
            boss_dash_vy       <= 6'sd0;
        end else if (game_state == 2'd1) begin
            eat_gain            <= 2'd0;
            collect_dna         <= 1'b0;
            damage_amount       <= 4'd0;
            player_hit_this_clk = 1'b0;

            // a new DNA on the ground can be picked up only after DNA_PICKUP_DELAY_FRAMES
            dna_active_d <= dna_active;
            if (dna_active && !dna_active_d)         dna_wait <= DNA_PICKUP_DELAY_FRAMES;
            else if (frame_tick && dna_wait != 6'd0) dna_wait <= dna_wait - 6'd1;

            // 1. เก็บเม็ด DNA
            // The game core consumes one pickup per clock. Give enemy DNA first priority.
            pickup_claimed = collect_dna;
            if (!pickup_claimed && dna_active && dna_active_d && (dna_wait == 6'd0) &&
                check_aabb(player_wx, player_wy, player_size, dna_wx, dna_wy, 8'd8)) begin
                pickup_claimed    = 1'b1;
                dna_active       <= 1'b0;
                collect_dna      <= 1'b1;
                collect_dna_type <= dna_type;
            end

            // A herbivore opens a rock on the first hit. Roll once and keep any DNA
            // at that rock's position until collected, even after the rock disappears.
            for (i = 0; i < 8; i = i + 1) begin
                if (rocks_alive[i] && !rock_breaking[i] && !is_carnivore && (hit_cd == 6'd0) && (form_state != 3'd0) &&
                    (check_aabb(player_wx, player_wy, player_size, rock_x[i], rock_y[i], 8'd16) ||
                     (spike_unlocked && check_aabb_rect(spk_x, spk_y, spk_w, spk_h, rock_x[i], rock_y[i], 8'd16)))) begin
                    hit_cd <= 6'd15;
                    rock_breaking[i] <= 1'b1;
                    rock_brk[i] <= ROCK_BREAK_FRAMES;
                    eat_gain <= 2'd1;

                    avail_dna = ~unlocked_skills;
                    if ((avail_dna != 4'd0) && ((rnd_val[3:0] & ROCK_DROP_MASK) == 4'd0)) begin
                        rock_dna_active[i] <= 1'b1;
                        if (avail_dna[0])      rock_dna_type[i] <= 2'd0;
                        else if (avail_dna[1]) rock_dna_type[i] <= 2'd1;
                        else if (avail_dna[2]) rock_dna_type[i] <= 2'd2;
                        else                   rock_dna_type[i] <= 2'd3;
                    end
                end

                if (rock_breaking[i] && frame_tick) begin
                    if (rock_brk[i] > 7'd1) begin
                        rock_brk[i] <= rock_brk[i] - 7'd1;
                    end else begin
                        rock_breaking[i] <= 1'b0;
                        rocks_alive[i] <= 1'b0;
                    end
                end

                if (rock_dna_active[i]) begin
                    if (unlocked_skills[rock_dna_type[i]]) begin
                        rock_dna_active[i] <= 1'b0;
                    end else if (!pickup_claimed &&
                        check_aabb(player_wx, player_wy, player_size, rock_x[i] + 12'd4, rock_y[i] + 12'd4, 8'd8)) begin
                        pickup_claimed = 1'b1;
                        rock_dna_active[i] <= 1'b0;
                        collect_dna <= 1'b1;
                        collect_dna_type <= rock_dna_type[i];
                    end
                end
            end

            // 3. ปะทะศัตรูทั้ง 16 ตัว & สกิล Shock / Poison
            for (i = 0; i < 16; i = i + 1) begin
                if (enemies_alive[i] && (form_state != 3'd0)) begin
                    e_cx   = enemy_x[i] + {5'd0, enemy_size[i][7:1]};
                    e_cy   = enemy_y[i] + {5'd0, enemy_size[i][7:1]};
                    dist_x = (p_cx > e_cx) ? (p_cx - e_cx) : (e_cx - p_cx);
                    dist_y = (p_cy > e_cy) ? (p_cy - e_cy) : (e_cy - p_cy);

                    if (poison_active && frame_tick && (poison_tick_cd == 6'd0) &&   // damage once per tick, not every clock
                        (dist_x < poison_radius + {5'd0, enemy_size[i][7:1]}) &&
                        (dist_y < poison_radius + {5'd0, enemy_size[i][7:1]})) begin
                        if (enemy_hp[i] <= POISON_DAMAGE) begin
                            enemy_hp[i]      <= 3'd0;
                            enemies_alive[i] <= 1'b0;
                            if (is_carnivore) eat_gain <= (enemy_size[i] >= 8'd30) ? 2'd3 : 2'd2;   // herbivore gains nothing from enemies
                            avail_dna = enemy_dna_reg[i] & (~unlocked_skills);
                            if (is_carnivore && (avail_dna != 4'b0000) && ((rnd_val[2:0] & ENEMY_DROP_MASK) == 3'd0)) begin
                                dna_wx     <= enemy_x[i] + {5'd0, enemy_size[i][7:1]};
                                dna_wy     <= enemy_y[i] + {5'd0, enemy_size[i][7:1]};
                                dna_active <= 1'b1;
                                if (avail_dna[0])      dna_type <= 2'd0;
                                else if (avail_dna[1]) dna_type <= 2'd1;
                                else if (avail_dna[2]) dna_type <= 2'd2;
                                else                   dna_type <= 2'd3;
                            end
                        end else begin
                            enemy_hp[i] <= enemy_hp[i] - POISON_DAMAGE;
                        end
                    end

                    e_aura_r = {5'd0, enemy_size[i][7:1]} + (enemy_skill_mode[i] ? POISON_RADIUS : ELECTRIC_RADIUS);
                    if ((enemy_skill_tmr[i] > 8'd0) &&
                        (dist_x < e_aura_r + {5'd0, player_size[7:1]}) &&
                        (dist_y < e_aura_r + {5'd0, player_size[7:1]})) begin
                        if (!enemy_skill_mode[i]) begin
                            player_stun_tmr <= 9'd120;
                        end else if (invuln_cd == 6'd0) begin
                            damage_amount <= 4'd1;
                            invuln_cd     <= 6'd45;
                        end
                    end

                    hit_by_spike = spike_unlocked && check_aabb_rect(spk_x, spk_y, spk_w, spk_h, enemy_x[i], enemy_y[i], enemy_size[i]);
                    hit_by_body  = check_aabb(player_wx, player_wy, player_size, enemy_x[i], enemy_y[i], enemy_size[i]);

                    can_attack = !is_carnivore || (player_size > enemy_size[i]) || e_stunned[i] || dash_active || hit_by_spike;

                    if (hit_by_spike || hit_by_body) begin
                        if (is_god_mode) begin
                            if (hit_cd == 6'd0) begin
                                hit_cd           <= 6'd15;
                                enemy_hp[i]      <= 3'd0;
                                enemies_alive[i] <= 1'b0;
                                if (is_carnivore) eat_gain <= (enemy_size[i] >= 8'd30) ? 2'd3 : 2'd2;

                                if (enemy_size[i] > player_size) begin
                                    size_diff = enemy_size[i] - player_size;
                                    if (size_diff >= 8'd24)
                                        damage_amount <= 4'd8;
                                    else begin
                                        calc_dmg = (size_diff >> 2) + 5'd2;
                                        damage_amount <= (calc_dmg > 5'd7) ? 4'd7 : calc_dmg[3:0];
                                    end
                                end
                            end
                        end
                        else if (can_attack) begin
                            if (hit_cd == 6'd0) begin
                                hit_cd <= 6'd15;
                                if (enemy_hp[i] <= base_atk) begin
                                    enemy_hp[i]      <= 3'd0;
                                    enemies_alive[i] <= 1'b0;
                                    if (is_carnivore) eat_gain <= (enemy_size[i] >= 8'd30) ? 2'd3 : 2'd2;

                                    avail_dna = enemy_dna_reg[i] & (~unlocked_skills);
                                    if (is_carnivore && (avail_dna != 4'b0000) && ((rnd_val[2:0] & ENEMY_DROP_MASK) == 3'd0)) begin
                                        dna_wx     <= enemy_x[i] + {5'd0, enemy_size[i][7:1]};
                                        dna_wy     <= enemy_y[i] + {5'd0, enemy_size[i][7:1]};
                                        dna_active <= 1'b1;
                                        if (avail_dna[0])      dna_type <= 2'd0;
                                        else if (avail_dna[1]) dna_type <= 2'd1;
                                        else if (avail_dna[2]) dna_type <= 2'd2;
                                        else                   dna_type <= 2'd3;
                                    end
                                end else begin
                                    enemy_hp[i] <= enemy_hp[i] - base_atk;
                                end
                            end
                        end

                        if (!is_god_mode && (!is_carnivore || !can_attack) && hit_by_body &&
                            (enemy_size[i] >= player_size) && !e_stunned[i] && !dash_active) begin
                            if (invuln_cd == 6'd0) begin
                                size_diff = enemy_size[i] - player_size;
                                // ใช้การเลื่อนบิตแทนการหาร (>> 3 แทน / 10) เพื่อประหยัด LUT
                                calc_dmg  = (size_diff >> 3) + 5'd1;
                                damage_amount       <= (calc_dmg > 5'd8) ? 4'd8 : calc_dmg[3:0];
                                invuln_cd           <= 6'd45;
                                player_hit_this_clk = 1'b1;
                            end
                        end
                    end
                end
            end

            // 3B. Final Boss (Giant TOTO): spawn once when form_state == 4 (all 4 DNA), combat & defeat
            if ((form_state == 3'd4) && !boss_spawned && !boss_defeated) begin
                boss_spawned   <= 1'b1;
                boss_active    <= 1'b1;
                boss_hp        <= BOSS_MAX_HP;
                boss_alert_tmr <= BOSS_ALERT_FRAMES;
                boss_wx        <= (p_cx < 12'd1024) ? BOSS_SPAWN_HIGH : BOSS_SPAWN_LOW;
                boss_wy        <= (p_cy < 12'd1024) ? BOSS_SPAWN_HIGH : BOSS_SPAWN_LOW;
            end else if (!boss_active && boss_spawned && (boss_hp == 6'd0) && !boss_defeated) begin
                boss_defeated <= 1'b1;
            end

            if (boss_active) begin
                if (boss_telegraph_start) begin
                    boss_dash_vx <= boss_dash_vx_next;
                    boss_dash_vy <= boss_dash_vy_next;
                end

                boss_poison_hit = poison_active && frame_tick && (poison_tick_cd == 6'd0) &&
                                  (boss_dx < poison_radius + {5'd0, BOSS_SIZE[7:1]}) &&
                                  (boss_dy < poison_radius + {5'd0, BOSS_SIZE[7:1]});
                boss_hit_by_spike = spike_unlocked && check_aabb_rect(spk_x, spk_y, spk_w, spk_h, boss_wx, boss_wy, BOSS_SIZE);
                boss_hit_by_body  = check_aabb(player_wx, player_wy, player_size, boss_wx, boss_wy, BOSS_SIZE);
                boss_direct_hit   = (boss_is_vuln || boss_is_stunned) && (hit_cd == 6'd0) &&
                                    (boss_hit_by_spike || boss_hit_by_body);

                boss_dmg_this_clk = (boss_poison_hit ? {3'd0, POISON_DAMAGE} : 6'd0) +
                                    (boss_direct_hit ? {3'd0, base_atk} : 6'd0);

                if (boss_direct_hit) begin
                    hit_cd <= 6'd15;
                end

                if (boss_dmg_this_clk != 6'd0) begin
                    boss_hit_flash_tmr <= 6'd10;
                    if (boss_hp <= boss_dmg_this_clk) begin
                        boss_hp     <= 6'd0;
                        boss_active <= 1'b0;
                        eat_gain    <= 2'd3;
                    end else begin
                        boss_hp <= boss_hp - boss_dmg_this_clk;
                    end
                end

                if (!(boss_is_vuln || boss_is_stunned) && boss_hit_by_body &&
                    !dash_active && !is_god_mode && (invuln_cd == 6'd0) && !player_hit_this_clk) begin
                    damage_amount <= boss_is_dashing ? BOSS_DASH_DMG : BOSS_CONTACT_DMG;
                    invuln_cd     <= 6'd45;
                end
            end

            // 4. ตัวจับเวลา, เกิดใหม่ทั่วแมพ & ระบบนิเวศ AI
            if (frame_tick) begin
                spawn_idx <= spawn_idx + 4'd1;
                scan_j    <= scan_j + 4'd1; // สแกนหาเหยื่อทีละ 1 ตัวต่อเฟรม

                if (poison_active) begin
                    if (poison_tick_cd == 6'd0) poison_tick_cd <= POISON_TICK_FRAMES;
                    else                        poison_tick_cd <= poison_tick_cd - 6'd1;
                end else begin
                    poison_tick_cd <= 6'd0;
                end

                if (player_stun_tmr > 9'd0) player_stun_tmr <= player_stun_tmr - 9'd1;

                for (i = 0; i < 16; i = i + 1) begin

                    if (enemies_alive[i]) begin
                        in_screen_view = (enemy_x[i] + {4'd0, enemy_size[i]} >= cam_x) && (enemy_x[i] <= cam_x + 12'd640) &&
                                         (enemy_y[i] + {4'd0, enemy_size[i]} >= cam_y) && (enemy_y[i] <= cam_y + 12'd480);

                        if (enemy_skill_tmr[i] > 8'd0) begin
                            enemy_skill_tmr[i] <= enemy_skill_tmr[i] - 8'd1;
                        end else if (enemy_skill_cd[i] > 9'd0) begin
                            enemy_skill_cd[i] <= enemy_skill_cd[i] - 9'd1;
                        end else if (in_screen_view && !e_stunned[i]) begin
                            if (enemy_dna_reg[i][2] && enemy_dna_reg[i][3]) begin
                                enemy_skill_mode[i] <= rnd_val[0];
                                enemy_skill_tmr[i]  <= 8'd180;
                                enemy_skill_cd[i]   <= 9'd300;
                            end else if (enemy_dna_reg[i][2]) begin
                                enemy_skill_mode[i] <= 1'b0;
                                enemy_skill_tmr[i]  <= 8'd180;
                                enemy_skill_cd[i]   <= 9'd300;
                            end else if (enemy_dna_reg[i][3]) begin
                                enemy_skill_mode[i] <= 1'b1;
                                enemy_skill_tmr[i]  <= 8'd180;
                                enemy_skill_cd[i]   <= 9'd300;
                            end
                        end
                    end
                end

                // เกิดใหม่หินพืช
                if (!rocks_alive[spawn_idx[2:0]] && !rock_dna_active[spawn_idx[2:0]] && (rnd_val[1:0] == 2'b00)) begin
                    rock_x[spawn_idx[2:0]] <= 12'd48 + {1'b0, rnd_val[10:0]};
                    rock_y[spawn_idx[2:0]] <= 12'd48 + {1'b0, rnd_val[15:5]};
                    if (rock_x[spawn_idx[2:0]] > 12'd1980) rock_x[spawn_idx[2:0]] <= 12'd1900;
                    if (rock_y[spawn_idx[2:0]] > 12'd1980) rock_y[spawn_idx[2:0]] <= 12'd1900;
                    rocks_alive[spawn_idx[2:0]] <= 1'b1;
                end

                // เกิดใหม่ศัตรูสุ่มทั่วทั้งแมพ 2048x2048
                if (!enemies_alive[spawn_idx] && (rnd_val[2:0] == 3'b000)) begin
                    enemy_x[spawn_idx] <= 12'd60 + {1'b0, rnd_val[10:0]};
                    enemy_y[spawn_idx] <= 12'd60 + {1'b0, rnd_val[15:5]};
                    if (enemy_x[spawn_idx] > 12'd1850) enemy_x[spawn_idx] <= 12'd1800;
                    if (enemy_y[spawn_idx] > 12'd1850) enemy_y[spawn_idx] <= 12'd1800;

                    if (spawn_idx[0] == 1'b0) begin
                        spawned_sz_calc = ({1'b0, player_size} > 9'd24) ?
                                          ({1'b0, player_size} - 9'd8 - {5'd0, rnd_val[3:0]}) : 9'd14;
                        enemy_size[spawn_idx]    <= (spawned_sz_calc < 9'd12) ? 8'd12 : spawned_sz_calc[7:0];
                        enemy_hp[spawn_idx]      <= 3'd2;
                        enemy_max_hp[spawn_idx]  <= 3'd2;
                        enemy_dna_reg[spawn_idx] <= (4'b0001 << rnd_val[1:0]);
                    end else begin
                        spawned_sz_calc = {1'b0, player_size} + 9'd24 + {3'd0, rnd_val[5:0]};
                        enemy_size[spawn_idx]    <= (spawned_sz_calc > 9'd220) ? 8'd220 : spawned_sz_calc[7:0];
                        enemy_hp[spawn_idx]      <= 3'd6;
                        enemy_max_hp[spawn_idx]  <= 3'd6;
                        enemy_dna_reg[spawn_idx] <= (rnd_val[7:4] == 4'd0) ? 4'b1111 : rnd_val[7:4];
                    end
                    enemy_skill_tmr[spawn_idx]<= 8'd0;
                    enemy_skill_cd[spawn_idx] <= 9'd180;
                    enemy_has_prey[spawn_idx] <= 1'b0;
                    enemies_alive[spawn_idx]  <= 1'b1;
                end

                if (hit_cd > 0)    hit_cd    <= hit_cd - 6'd1;
                if (invuln_cd > 0) invuln_cd <= invuln_cd - 6'd1;
                if (boss_spawned && (boss_alert_tmr > 8'd0))
                    boss_alert_tmr <= boss_alert_tmr - 8'd1;
                if ((boss_hit_flash_tmr > 6'd0) && !(boss_active && (boss_dmg_this_clk != 6'd0)))
                    boss_hit_flash_tmr <= boss_hit_flash_tmr - 6'd1;
                ai_tick_div <= ai_tick_div + 3'd1;

                // 4B. Final Boss movement (dash lunge or slow stalk when in aggro range)
                if (boss_active && (boss_hp > 6'd0) && !(boss_dmg_this_clk >= boss_hp)) begin
                    if (boss_is_dashing) begin
                        if (boss_next_wx < $signed({2'b00, BOSS_POS_MIN}))
                            boss_wx <= BOSS_POS_MIN;
                        else if (boss_next_wx > $signed({2'b00, BOSS_POS_MAX}))
                            boss_wx <= BOSS_POS_MAX;
                        else
                            boss_wx <= boss_next_wx[11:0];

                        if (boss_next_wy < $signed({2'b00, BOSS_POS_MIN}))
                            boss_wy <= BOSS_POS_MIN;
                        else if (boss_next_wy > $signed({2'b00, BOSS_POS_MAX}))
                            boss_wy <= BOSS_POS_MAX;
                        else
                            boss_wy <= boss_next_wy[11:0];
                    end else if ((boss_state == 3'd0) && boss_in_range) begin
                        if (boss_phase2 ? (ai_tick_div[0] == 1'b0) : (ai_tick_div[1:0] == 2'd0)) begin
                            if ((p_cx > boss_cx + 12'd4) && (boss_wx < BOSS_POS_MAX))
                                boss_wx <= boss_wx + 12'd1;
                            else if ((p_cx + 12'd4 < boss_cx) && (boss_wx > BOSS_POS_MIN))
                                boss_wx <= boss_wx - 12'd1;

                            if ((p_cy > boss_cy + 12'd4) && (boss_wy < BOSS_POS_MAX))
                                boss_wy <= boss_wy + 12'd1;
                            else if ((p_cy + 12'd4 < boss_cy) && (boss_wy > BOSS_POS_MIN))
                                boss_wy <= boss_wy - 12'd1;
                        end
                    end
                end

                // ------------------------------------------------------------------
                // 5. AI ระบบนิเวศ (แบบประหยัด LUT 100%):
                //    - สแกนหาเหยื่อตัวที่ scan_j ในรัศมี 320px (16 เฟรมสแกนครบทุกตัว)
                //    - ยิ่งตัวใหญ่ยิ่งเดินช้า
                //    - มองเห็นผู้เล่นเฉพาะตอนอยู่ในจอเท่านั้น
                // ------------------------------------------------------------------
                if (form_state != 3'd0) begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (enemies_alive[i] && !e_stunned[i]) begin
                            // อัปเดตการค้นหาเหยื่อหมายเลข scan_j
                            if ((i != scan_j) && enemies_alive[scan_j] && (enemy_size[i] > enemy_size[scan_j] + 8'd4)) begin
                                prey_dx = (enemy_x[i] > enemy_x[scan_j]) ? (enemy_x[i] - enemy_x[scan_j]) : (enemy_x[scan_j] - enemy_x[i]);
                                prey_dy = (enemy_y[i] > enemy_y[scan_j]) ? (enemy_y[i] - enemy_y[scan_j]) : (enemy_y[scan_j] - enemy_y[i]);
                                if ((prey_dx < 12'd320) && (prey_dy < 12'd320)) begin
                                    enemy_has_prey[i] <= 1'b1;
                                    enemy_prey_idx[i] <= scan_j;
                                end
                            end

                            // ความเร็วแปรผกผันกับขนาด (ตัวใหญ่เดินช้ากว่าตัวเล็ก)
                            if ( (enemy_size[i] < 8'd32  && ai_tick_div[0] == 1'b0) ||
                                 (enemy_size[i] >= 8'd32 && enemy_size[i] < 8'd80 && ai_tick_div[1:0] == 2'd0) ||
                                 (enemy_size[i] >= 8'd80 && ai_tick_div == 3'd0) ) begin

                                ai_step = enemy_dna_reg[i][0] ? 12'd2 : 12'd1;
                                in_screen_view = (enemy_x[i] + {4'd0, enemy_size[i]} >= cam_x) && (enemy_x[i] <= cam_x + 12'd640) &&
                                                 (enemy_y[i] + {4'd0, enemy_size[i]} >= cam_y) && (enemy_y[i] <= cam_y + 12'd480);

                                if (e_chase[i]) begin
                                    // CHASE state -> มองเห็นผู้เล่น
                                    if (enemy_size[i] >= player_size) begin
                                        if (player_wx > enemy_x[i]) enemy_x[i] <= enemy_x[i] + ai_step;
                                        else if (player_wx < enemy_x[i]) enemy_x[i] <= enemy_x[i] - ai_step;
                                        if (player_wy > enemy_y[i]) enemy_y[i] <= enemy_y[i] + ai_step;
                                        else if (player_wy < enemy_y[i]) enemy_y[i] <= enemy_y[i] - ai_step;
                                    end else begin
                                        if (player_wx > enemy_x[i] && enemy_x[i] > 24)   enemy_x[i] <= enemy_x[i] - ai_step;
                                        else if (player_wx < enemy_x[i] && enemy_x[i] < 1900) enemy_x[i] <= enemy_x[i] + ai_step;
                                        if (player_wy > enemy_y[i] && enemy_y[i] > 24)   enemy_y[i] <= enemy_y[i] - ai_step;
                                        else if (player_wy < enemy_y[i] && enemy_y[i] < 1900) enemy_y[i] <= enemy_y[i] + ai_step;
                                    end
                                end else if (enemy_has_prey[i]) begin
                                    // อยู่นอกจอ -> ไล่ล่าและกินเหยื่อตัวเล็กกว่าที่ล็อกไว้
                                    p_idx = enemy_prey_idx[i];
                                    if (enemies_alive[p_idx] && (enemy_size[i] > enemy_size[p_idx] + 8'd4)) begin
                                        if (enemy_x[p_idx] > enemy_x[i]) enemy_x[i] <= enemy_x[i] + ai_step;
                                        else if (enemy_x[p_idx] < enemy_x[i]) enemy_x[i] <= enemy_x[i] - ai_step;
                                        if (enemy_y[p_idx] > enemy_y[i]) enemy_y[i] <= enemy_y[i] + ai_step;
                                        else if (enemy_y[p_idx] < enemy_y[i]) enemy_y[i] <= enemy_y[i] - ai_step;

                                        if (check_aabb(enemy_x[i], enemy_y[i], enemy_size[i], enemy_x[p_idx], enemy_y[p_idx], enemy_size[p_idx])) begin
                                            enemies_alive[p_idx] <= 1'b0;
                                            enemy_has_prey[i]    <= 1'b0;
                                            if (enemy_size[i] < 8'd200)
                                                enemy_size[i] <= enemy_size[i] + 8'd2;
                                        end
                                    end else begin
                                        enemy_has_prey[i] <= 1'b0;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

endmodule