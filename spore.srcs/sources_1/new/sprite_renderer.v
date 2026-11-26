module sprite_renderer #(
    parameter USE_TILE_MAP   = 1,   // 1 = tile map background, 0 = old plain background with grid lines
    parameter SHOW_DIR_ARROW = 0,   // 1 = white arrow in front of the player (the picture itself now turns)
    parameter PLAYER_PAD     = 32,  // the player picture is drawn this many pixels bigger than its hit box
    parameter SHOW_SPIKE     = 0    // 1 = red triangle in front of the player when MORE DAMAGE is owned (shows the hit area)
)(
    input  wire         clk_25m,
    input  wire         video_on,
    input  wire [9:0]   pixel_x,
    input  wire [9:0]   pixel_y,
    input  wire [11:0]  cam_x,
    input  wire [11:0]  cam_y,
    input  wire [1:0]   game_state,
    input  wire [2:0]   form_state,
    input  wire [3:0]   unlocked_skills, // [0]:Dash, [1]:Spike, [2]:Shock, [3]:Poison
    input  wire [2:0]   facing_dir, // N,E,S,W,NE,SE,SW,NW
    input  wire         is_carnivore,    // 1 = carnivore body
    input  wire [3:0]   egg_taps,        // egg pictures 0..9
    input  wire         egg_fx,          // sparkle effect on the egg
    input  wire         player_moving,   // the player is swimming / walking
    input  wire         wake_reset,
    input  wire         wake_tick,
    input  wire         wake_enabled,
    input  wire         shock_active,
    input  wire         poison_active,
    input  wire [2:0]   shock_cd_sec,
    input  wire [2:0]   poison_cd_sec,
    input  wire [2:0]   dash_cd_sec,
    input  wire [7:0]   player_hp,
    input  wire [7:0]   player_size,
    input  wire [11:0]  player_wx,
    input  wire [11:0]  player_wy,
    input  wire [95:0]  rocks_wx,
    input  wire [95:0]  rocks_wy,
    input  wire [7:0]   rocks_alive,
    input  wire [7:0]   rocks_cracked,   // 1 = cracked rock picture
    input  wire [7:0]   rock_dna_active,
    input  wire [15:0]  rock_dna_types,
    input  wire [191:0] enemies_wx,
    input  wire [191:0] enemies_wy,
    input  wire [15:0]  enemies_alive,
    input  wire [127:0] enemies_sz,
    input  wire [63:0]  enemies_dna,
    input  wire [15:0]  enemies_stun,
    input  wire [15:0]  enemies_e_shock,
    input  wire [15:0]  enemies_e_poison,
    input  wire [11:0]  dna_wx,
    input  wire [11:0]  dna_wy,
    input  wire         dna_active,
    input  wire [1:0]   dna_type,
    input  wire [11:0]  boss_wx,
    input  wire [11:0]  boss_wy,
    input  wire [7:0]   boss_size,
    input  wire         boss_active,
    input  wire [2:0]   boss_state,
    input  wire         boss_phase2,
    input  wire         boss_alert,
    input  wire         boss_hit_flash,
    output wire [11:0]  rgb_out
);

    wire [11:0] world_x = cam_x + {2'b00, pixel_x};
    wire [11:0] world_y = cam_y + {2'b00, pixel_y};

    wire [11:0] r_x [0:7];
    wire [11:0] r_y [0:7];
    assign {r_x[7], r_x[6], r_x[5], r_x[4], r_x[3], r_x[2], r_x[1], r_x[0]} = rocks_wx;
    assign {r_y[7], r_y[6], r_y[5], r_y[4], r_y[3], r_y[2], r_y[1], r_y[0]} = rocks_wy;

    wire [11:0] e_x   [0:15];
    wire [11:0] e_y   [0:15];
    wire [7:0]  e_sz  [0:15];
    wire [3:0]  e_dna [0:15];
    assign {e_x[15], e_x[14], e_x[13], e_x[12], e_x[11], e_x[10], e_x[9], e_x[8],
            e_x[7],  e_x[6],  e_x[5],  e_x[4],  e_x[3],  e_x[2],  e_x[1], e_x[0]} = enemies_wx;
    assign {e_y[15], e_y[14], e_y[13], e_y[12], e_y[11], e_y[10], e_y[9], e_y[8],
            e_y[7],  e_y[6],  e_y[5],  e_y[4],  e_y[3],  e_y[2],  e_y[1], e_y[0]} = enemies_wy;
    assign {e_sz[15], e_sz[14], e_sz[13], e_sz[12], e_sz[11], e_sz[10], e_sz[9], e_sz[8],
            e_sz[7],  e_sz[6],  e_sz[5],  e_sz[4],  e_sz[3],  e_sz[2],  e_sz[1], e_sz[0]} = enemies_sz;
    assign {e_dna[15], e_dna[14], e_dna[13], e_dna[12], e_dna[11], e_dna[10], e_dna[9], e_dna[8],
            e_dna[7],  e_dna[6],  e_dna[5],  e_dna[4],  e_dna[3],  e_dna[2],  e_dna[1], e_dna[0]} = enemies_dna;

    wire is_perfect = (form_state == 3'd4);

    wire in_player = (world_x >= player_wx) && (world_x < player_wx + {4'd0, player_size}) &&
                     (world_y >= player_wy) && (world_y < player_wy + {4'd0, player_size});

    wire [7:0]  in_rock;
    wire [15:0] in_enemy;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_rk
            assign in_rock[g] = rocks_alive[g] &&
                                (world_x >= r_x[g]) && (world_x < r_x[g] + 12'd16) &&
                                (world_y >= r_y[g]) && (world_y < r_y[g] + 12'd16);
        end
        for (g = 0; g < 16; g = g + 1) begin : gen_en
            assign in_enemy[g] = enemies_alive[g] &&
                                 (world_x >= e_x[g]) && (world_x < e_x[g] + {4'd0, e_sz[g]}) &&
                                 (world_y >= e_y[g]) && (world_y < e_y[g] + {4'd0, e_sz[g]});
        end
    endgenerate

    // The old sprite_rom is no longer used: rocks are drawn from art_rom too.
    // These stay so the pipeline below does not change.
    wire        has_sprite = 1'b0;
    wire [11:0] rom_data   = 12'hF0F;

    reg        has_sprite_d1;
    reg [1:0]  game_state_d1;
    reg [11:0] world_x_d1, world_y_d1;
    reg [9:0]  px_d1, py_d1;
    always @(posedge clk_25m) begin
        has_sprite_d1 <= has_sprite;
        game_state_d1 <= game_state;
        world_x_d1    <= world_x;
        world_y_d1    <= world_y;
        px_d1         <= pixel_x;
        py_d1         <= pixel_y;
    end

    // ------------------------------------------------------------------
    // Second pipeline stage. The tile background needs two ROM reads in a row
    // (map_rom: which tile, then tile_rom: its pixels), so everything else waits one more clock.
    // ------------------------------------------------------------------
    reg        has_sprite_d2, video_on_d1, video_on_d2;
    reg [1:0]  game_state_d2;
    reg [11:0] world_x_d2, world_y_d2, rom_data_d2;
    reg [9:0]  px_d2, py_d2;
    always @(posedge clk_25m) begin
        video_on_d1   <= video_on;
        video_on_d2   <= video_on_d1;
        has_sprite_d2 <= has_sprite_d1;
        game_state_d2 <= game_state_d1;
        world_x_d2    <= world_x_d1;
        world_y_d2    <= world_y_d1;
        px_d2         <= px_d1;
        py_d2         <= py_d1;
        rom_data_d2   <= rom_data;
    end

    // ------------------------------------------------------------------
    // Tile map background: world is 64 x 64 tiles of 32 x 32 pixels.
    //   map_rom  (4096 x 3 bit)  : address = {tile_y, tile_x}           -> tile id (valid in stage d1)
    //   tile_rom (6144 x 12 bit) : address = {tile id, pixel_y, pixel_x} -> colour    (valid in stage d2)
    // ------------------------------------------------------------------
    wire [2:0]  map_tile_id;
    map_rom u_map_rom (
        .clka (clk_25m),
        .addra({world_y[10:5], world_x[10:5]}),
        .douta(map_tile_id)
    );

    wire [11:0] tile_data;
    tile_rom u_tile_rom (
        .clka (clk_25m),
        .addra({map_tile_id, world_y_d1[4:0], world_x_d1[4:0]}),
        .douta(tile_data)
    );

    // ------------------------------------------------------------------
    // Third pipeline stage (the art layer needs three clocks)
    // ------------------------------------------------------------------
    reg        has_sprite_d3, video_on_d3;
    reg [1:0]  game_state_d3;
    reg [11:0] world_x_d3, world_y_d3, rom_data_d3, tile_data_d3;
    reg [9:0]  px_d3, py_d3;
    always @(posedge clk_25m) begin
        video_on_d3   <= video_on_d2;
        has_sprite_d3 <= has_sprite_d2;
        game_state_d3 <= game_state_d2;
        world_x_d3    <= world_x_d2;
        world_y_d3    <= world_y_d2;
        px_d3         <= px_d2;
        py_d3         <= py_d2;
        rom_data_d3   <= rom_data_d2;
        tile_data_d3  <= tile_data;
    end

    // ------------------------------------------------------------------
    // Art layer: egg, player (body + DNA parts), enemies, DNA pickups. One ROM: art_rom.
    // Addresses (12-bit words) must match make_art_assets.py:
    //   PLAYER_BASE 0       32 pictures 48x48  : (carnivore * 16 + DNA mask)
    //   EGG_BASE    73728   20 pictures 72x64  : 0..9 cracks, 10..19 cracks + effect
    //   ENEMY_BASE  165888   5 pictures 48x48
    //   PICK_BASE   177408   4 pictures 16x16
    // Clock 0: pick what is under the pixel   Clock 1: scale (offset x 1/size)
    // Clock 2: turn / sway and build the address   Clock 3: art_rom data is ready
    // ------------------------------------------------------------------
    localparam [17:0] EGG_BASE   = 18'd73728;
    localparam [17:0] ENEMY_BASE = 18'd165888;
    localparam [17:0] PICK_BASE  = 18'd177408;
    localparam [17:0] ROCK_BASE  = 18'd178432;   // 2 pictures 32x32: whole rock, cracked rock
    localparam [2:0]  K_NONE = 3'd0, K_PLAYER = 3'd1, K_PICK = 3'd2, K_ENEMY = 3'd3, K_EGG = 3'd4, K_ROCK = 3'd5;

    // 1/size factors (serial dividers): one for the player, one for every enemy
    wire [19:0] p_inv;
    wire [7:0]  p_draw = player_size + PLAYER_PAD;          // drawn size of the player picture
    recip_div #(.K(48)) u_div_p (.clk(clk_25m), .den(p_draw), .q(p_inv));
    wire [19:0] e_inv [0:15];
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_div
            recip_div #(.K(48)) u_div_e (.clk(clk_25m), .den(e_sz[g]), .q(e_inv[g]));
        end
    endgenerate
    wire [19:0] boss_inv;
    recip_div #(.K(48)) u_div_boss (.clk(clk_25m), .den(boss_size), .q(boss_inv));

    // free running frame counter (for the swaying tail)
    reg [8:0] frame_cnt = 9'd0;
    always @(posedge clk_25m) if (pixel_x == 10'd0 && pixel_y == 10'd0) frame_cnt <= frame_cnt + 9'd1;

    // ---- clock 0 ----
    wire egg_mode   = (form_state == 3'd0);
    wire [11:0] pd_x0 = player_wx - (PLAYER_PAD >> 1);   // the picture is centred on the hit box
    wire [11:0] pd_y0 = player_wy - (PLAYER_PAD >> 1);
    wire in_pdraw = (world_x >= pd_x0) && (world_x < pd_x0 + {4'd0, p_draw}) &&
                    (world_y >= pd_y0) && (world_y < pd_y0 + {4'd0, p_draw});
    wire in_egg_box = (pixel_x >= 10'd248) && (pixel_x < 10'd392) && (pixel_y >= 10'd176) && (pixel_y < 10'd304);

    wire [11:0] pk_x0 = (dna_wx > 12'd4) ? (dna_wx - 12'd4) : 12'd0;
    wire [11:0] pk_y0 = (dna_wy > 12'd4) ? (dna_wy - 12'd4) : 12'd0;
    wire in_pick = dna_active && (world_x >= pk_x0) && (world_x < pk_x0 + 12'd16) &&
                                 (world_y >= pk_y0) && (world_y < pk_y0 + 12'd16);

    reg [3:0] en_sel;
    reg       en_any;
    integer   q;
    always @(*) begin
        en_sel = 4'd0;
        en_any = 1'b0;
        for (q = 0; q < 16; q = q + 1)
            if (in_enemy[q]) begin en_sel = q[3:0]; en_any = 1'b1; end
    end
    wire [11:0] en_x    = e_x[en_sel];
    wire [11:0] en_y    = e_y[en_sel];
    wire [7:0]  en_size = e_sz[en_sel];
    // enemy picture by size: small ones are picture 0, the biggest is picture 4
    wire [2:0]  en_type = (en_size <= 8'd16)  ? 3'd0 :
                          (en_size <= 8'd24)  ? 3'd1 :
                          (en_size <= 8'd60)  ? 3'd2 :
                          (en_size <= 8'd100) ? 3'd3 : 3'd4;

    // DNA layer order in the pictures: 1 tail shell = DASH, 2 antennae = MORE DAMAGE,
    //                                  3 upper fins = POISON, 4 lower fins = ELECTRIC
    // unlocked_skills: [0] Dash [1] Spike [2] Shock [3] Poison  ->  mask bit0..3 = layer 1 Dash, 2 More damage, 3 Poison, 4 Electric
    wire [3:0] dna_mask_l = {unlocked_skills[2], unlocked_skills[3], unlocked_skills[1], unlocked_skills[0]};
    wire [3:0] egg_frame  = (egg_taps > 4'd9 ? 4'd9 : egg_taps) + (egg_fx ? 4'd10 : 4'd0);

    // rocks are drawn 32x32, centred on their 16x16 hit box
    wire [7:0] in_rockd, in_rock_pick;
    generate
        for (g = 0; g < 8; g = g + 1) begin : gen_rkd
            wire [11:0] rx0 = (r_x[g] > 12'd8) ? (r_x[g] - 12'd8) : 12'd0;
            wire [11:0] ry0 = (r_y[g] > 12'd8) ? (r_y[g] - 12'd8) : 12'd0;
            assign in_rockd[g] = rocks_alive[g] &&
                                 (world_x >= rx0) && (world_x < rx0 + 12'd32) &&
                                 (world_y >= ry0) && (world_y < ry0 + 12'd32);
            assign in_rock_pick[g] = rock_dna_active[g] &&
                                     (world_x >= r_x[g]) && (world_x < r_x[g] + 12'd16) &&
                                     (world_y >= r_y[g]) && (world_y < r_y[g] + 12'd16);
        end
    endgenerate
    reg [2:0] rk_sel, rock_pick_sel;
    reg       rk_any, rock_pick_any;
    integer   rq;
    always @(*) begin
        rk_sel = 3'd0;
        rk_any = 1'b0;
        rock_pick_sel = 3'd0;
        rock_pick_any = 1'b0;
        for (rq = 0; rq < 8; rq = rq + 1) begin
            if (in_rockd[rq]) begin rk_sel = rq[2:0]; rk_any = 1'b1; end
            if (in_rock_pick[rq]) begin rock_pick_sel = rq[2:0]; rock_pick_any = 1'b1; end
        end
    end
    wire [11:0] rk_x0 = (r_x[rk_sel] > 12'd8) ? (r_x[rk_sel] - 12'd8) : 12'd0;
    wire [11:0] rk_y0 = (r_y[rk_sel] > 12'd8) ? (r_y[rk_sel] - 12'd8) : 12'd0;
    wire [3:0] rock_pick_x = world_x - r_x[rock_pick_sel];
    wire [3:0] rock_pick_y = world_y - r_y[rock_pick_sel];

    // Opacity of the four existing 16x16 PICK_BASE sprites (F0F is transparent).
    // Use the rock as the B-layer candidate wherever the DNA sprite is transparent.
    localparam [255:0] PICK_OPAQUE_0 = 256'h000000000FF01FF81FF83FFC3FFC3FFC3FF81FF80FF00FF00FF00FE000000000;
    localparam [255:0] PICK_OPAQUE_1 = 256'h0000018003C007E003C003C00180018001800180018001800180018000000000;
    localparam [255:0] PICK_OPAQUE_2 = 256'h00000000000003C003C007E007F007F007F007E007E003C00180000000000000;
    localparam [255:0] PICK_OPAQUE_3 = 256'h000000000000018007E007E007E007E007E007E003E003C00180000000000000;
    wire [7:0] rock_pick_pixel = {rock_pick_y, rock_pick_x};
    wire [1:0] rock_pick_type = rock_dna_types[2*rock_pick_sel +: 2];
    wire rock_pick_opaque = rock_pick_any &&
        ((rock_pick_type == 2'd0) ? PICK_OPAQUE_0[rock_pick_pixel] :
         (rock_pick_type == 2'd1) ? PICK_OPAQUE_1[rock_pick_pixel] :
         (rock_pick_type == 2'd3) ? PICK_OPAQUE_2[rock_pick_pixel] : PICK_OPAQUE_3[rock_pick_pixel]);
    // The art ROM puts Poison before Electric, the reverse of the ecosystem type IDs.
    wire [1:0] draw_dna_type = rock_pick_opaque ? rock_pick_type : dna_type;
    wire [1:0] pk_idx = {draw_dna_type[1], draw_dna_type[1] ^ draw_dna_type[0]};
    reg [2:0] rock_pick_pipe;
    always @(posedge clk_25m) rock_pick_pipe <= {rock_pick_pipe[1:0], rock_pick_opaque};

    // ---- clock 0: two candidates for every pixel ----
    //   A (front)  : the egg or the player
    //   B (behind) : DNA pickup, enemy or rock (the first that applies)
    // Both pictures are read together from the dual port art_rom. A transparent pixel of A
    // lets B (and then the background) show through, so nothing disappears behind the empty
    // corners of the player's picture.
    reg [2:0] kA0;
    reg [7:0] oxA0, oyA0;
    always @(*) begin
        kA0 = K_NONE; oxA0 = 8'd0; oyA0 = 8'd0;
        if (egg_mode && in_egg_box) begin
            kA0 = K_EGG;    oxA0 = pixel_x - 10'd248; oyA0 = pixel_y - 10'd176;
        end else if (!egg_mode && in_pdraw) begin
            kA0 = K_PLAYER; oxA0 = world_x - pd_x0;   oyA0 = world_y - pd_y0;
        end
    end

    wire in_boss = boss_active &&
                   (world_x >= boss_wx) && (world_x < boss_wx + {4'd0, boss_size}) &&
                   (world_y >= boss_wy) && (world_y < boss_wy + {4'd0, boss_size});

    reg [2:0] kB0;
    reg [7:0] oxB0, oyB0;
    reg [3:0] selB0;
    reg [2:0] etB0;
    reg       boss_hit0;
    always @(*) begin
        kB0 = K_NONE; oxB0 = 8'd0; oyB0 = 8'd0; selB0 = 4'd0; etB0 = 3'd0; boss_hit0 = 1'b0;
        if (rock_pick_opaque) begin
            kB0 = K_PICK;  oxB0 = {4'd0, rock_pick_x}; oyB0 = {4'd0, rock_pick_y};
        end else if (in_pick) begin
            kB0 = K_PICK;  oxB0 = world_x - pk_x0; oyB0 = world_y - pk_y0;
        end else if (in_boss) begin
            kB0 = K_ENEMY; oxB0 = world_x - boss_wx; oyB0 = world_y - boss_wy; etB0 = 3'd4; boss_hit0 = 1'b1;
        end else if (en_any) begin
            kB0 = K_ENEMY; oxB0 = world_x - en_x;  oyB0 = world_y - en_y; selB0 = en_sel; etB0 = en_type;
        end else if (rk_any) begin
            kB0 = K_ROCK;  oxB0 = world_x - rk_x0; oyB0 = world_y - rk_y0; etB0 = {2'b00, rocks_cracked[rk_sel]};
        end
    end

    reg [2:0] kA1, anA1, kB1, etB1;
    reg [7:0] oxA1, oyA1, oxB1, oyB1;
    reg [3:0] egA1, selB1;
    reg [2:0] faceA1;
    reg [1:0] pkB1;
    reg [4:0] nA1;
    reg       mvA1, boss_hit1, boss_hit2, boss_hit3;
    always @(posedge clk_25m) begin
        kA1 <= kA0; oxA1 <= oxA0; oyA1 <= oyA0;
        faceA1 <= facing_dir; nA1 <= {is_carnivore, dna_mask_l}; egA1 <= egg_frame;
        anA1 <= player_moving ? frame_cnt[4:2] : frame_cnt[5:3];   // faster while moving
        mvA1 <= player_moving;
        kB1 <= kB0; oxB1 <= oxB0; oyB1 <= oyB0; selB1 <= selB0; etB1 <= etB0; pkB1 <= pk_idx;
        boss_hit1 <= boss_hit0;
    end

    // ---- clock 1: texel = offset * (K / size) ----
    wire [27:0] mxA = oxA1 * p_inv;
    wire [27:0] myA = oyA1 * p_inv;
    wire [6:0]  sxA = mxA[22:16];
    wire [6:0]  syA = myA[22:16];
    reg  [6:0]  txA1, tyA1;
    always @(*) begin
        if (kA1 == K_PLAYER) begin
            txA1 = (sxA > 7'd47) ? 7'd47 : sxA;
            tyA1 = (syA > 7'd47) ? 7'd47 : syA;
        end else begin                                            // egg is drawn 2x
            txA1 = oxA1[7:1];
            tyA1 = {1'b0, oyA1[6:1]};
        end
    end

    wire [19:0] invB = boss_hit1 ? boss_inv : e_inv[selB1];
    wire [27:0] mxB  = oxB1 * invB;
    wire [27:0] myB  = oyB1 * invB;
    wire [6:0]  sxB  = mxB[22:16];
    wire [6:0]  syB  = myB[22:16];
    reg  [6:0]  txB1, tyB1;
    always @(*) begin
        case (kB1)
            K_ENEMY: begin
                txB1 = (sxB > 7'd47) ? 7'd47 : sxB;
                tyB1 = (syB > 7'd47) ? 7'd47 : syB;
            end
            K_ROCK:  begin txB1 = {2'd0, oxB1[4:0]}; tyB1 = {2'd0, oyB1[4:0]}; end
            default: begin txB1 = {3'd0, oxB1[3:0]}; tyB1 = {3'd0, oyB1[3:0]}; end   // DNA pickup
        endcase
    end

    reg [2:0] kA2, anA2, kB2, etB2;
    reg [6:0] txA2, tyA2, txB2, tyB2;
    reg [3:0] egA2;
    reg [2:0] faceA2;
    reg [1:0] pkB2;
    reg [4:0] nA2;
    reg       mvA2;
    always @(posedge clk_25m) begin
        kA2 <= kA1; txA2 <= txA1; tyA2 <= tyA1; anA2 <= anA1; faceA2 <= faceA1; nA2 <= nA1; egA2 <= egA1; mvA2 <= mvA1;
        kB2 <= kB1; txB2 <= txB1; tyB2 <= tyB1; etB2 <= etB1; pkB2 <= pkB1;
        boss_hit2 <= boss_hit1;
    end

    // ---- clock 2: build the addresses ----
    // Player: the picture has its head up. Turn it so the head points where the player faces.
    // Inverse rotation about (23.5,23.5). Doubled coordinates keep the
    // half-texel centre exact; 181/256 approximates 1/sqrt(2).
    // Signed intermediates and bounds checks make outside texels transparent,
    // rather than wrapping them into a neighbouring sprite in the atlas.
    wire signed [8:0] rx2 = $signed({1'b0, txA2, 1'b0}) - 9'sd47;
    wire signed [8:0] ry2 = $signed({1'b0, tyA2, 1'b0}) - 9'sd47;
    wire signed [17:0] diag_sum  = (rx2 + ry2) * 18'sd181;
    wire signed [17:0] diag_diff = (ry2 - rx2) * 18'sd181;
    reg signed [8:0] rot_x, rot_y;
    always @(*) begin
        case (faceA2)
            3'd0: begin rot_x = txA2;         rot_y = tyA2;         end // N
            3'd1: begin rot_x = tyA2;         rot_y = 9'sd47-txA2; end // E
            3'd2: begin rot_x = 9'sd47-txA2; rot_y = 9'sd47-tyA2; end // S
            3'd3: begin rot_x = 9'sd47-tyA2; rot_y = txA2;         end // W
            3'd4: begin // NE
                rot_x = (18'sd12288 + diag_sum)  >>> 9;
                rot_y = (18'sd12288 + diag_diff) >>> 9;
            end
            3'd5: begin // SE
                rot_x = (18'sd12288 + diag_diff) >>> 9;
                rot_y = (18'sd12288 - diag_sum)  >>> 9;
            end
            3'd6: begin // SW
                rot_x = (18'sd12288 - diag_sum)  >>> 9;
                rot_y = (18'sd12288 - diag_diff) >>> 9;
            end
            default: begin // NW
                rot_x = (18'sd12288 - diag_diff) >>> 9;
                rot_y = (18'sd12288 + diag_sum)  >>> 9;
            end
        endcase
    end
    wire rot_ok = (rot_x >= 9'sd0) && (rot_x <= 9'sd47) &&
                  (rot_y >= 9'sd0) && (rot_y <= 9'sd47);
    wire [5:0] sx = rot_x[5:0];
    wire [5:0] sy = rot_y[5:0];

    // sway: idle = the tail tip sways a little; moving = the whole rear half swims, faster and wider
    wire [2:0] wi = anA2 + sy[4:2];
    reg signed [3:0] wv;
    always @(*) begin
        case (wi)
            3'd1, 3'd2, 3'd3: wv = 4'sd1;
            3'd5, 3'd6, 3'd7: wv = -4'sd1;
            default:          wv = 4'sd0;
        endcase
    end
    reg signed [7:0] sway;
    always @(*) begin
        if (sy >= 6'd40)      sway = mvA2 ? (wv * 3) : (wv * 2);
        else if (sy >= 6'd28) sway = mvA2 ? (wv * 2) : wv;
        else if (sy >= 6'd16) sway = mvA2 ? wv : 8'sd0;
        else                  sway = 8'sd0;
    end
    wire signed [7:0] sxw   = $signed({2'b00, sx}) + sway;
    wire              sx_ok = (sxw >= 8'sd0) && (sxw <= 8'sd47);
    wire [5:0]        sxu   = sxw[5:0];

    reg [17:0] art_addrA, art_addrB;
    reg        art_okA, art_okB;
    always @(*) begin
        art_addrA = 18'd0;
        art_okA   = 1'b0;
        case (kA2)
            K_PLAYER: begin
                art_okA   = rot_ok && sx_ok;
                art_addrA = ({13'd0, nA2} << 11) + ({13'd0, nA2} << 8) +
                            ({12'd0, sy} << 5) + ({12'd0, sy} << 4) + {12'd0, sxu};
            end
            K_EGG: begin
                art_okA   = 1'b1;
                art_addrA = EGG_BASE + ({14'd0, egA2} << 12) + ({14'd0, egA2} << 9) +
                            ({11'd0, tyA2} << 6) + ({11'd0, tyA2} << 3) + {11'd0, txA2};
            end
            default: art_okA = 1'b0;
        endcase
    end
    always @(*) begin
        art_addrB = 18'd0;
        art_okB   = 1'b0;
        case (kB2)
            K_ENEMY: begin
                art_okB   = 1'b1;
                art_addrB = ENEMY_BASE + ({15'd0, etB2} << 11) + ({15'd0, etB2} << 8) +
                            ({11'd0, tyB2} << 5) + ({11'd0, tyB2} << 4) + {11'd0, txB2};
            end
            K_PICK: begin
                art_okB   = 1'b1;
                art_addrB = PICK_BASE + ({16'd0, pkB2} << 8) + ({11'd0, tyB2} << 4) + {11'd0, txB2};
            end
            K_ROCK: begin
                art_okB   = 1'b1;
                art_addrB = ROCK_BASE + ({17'd0, etB2[0]} << 10) + ({11'd0, tyB2} << 5) + {11'd0, txB2};
            end
            default: art_okB = 1'b0;
        endcase
    end

    wire [11:0] art_dataA, art_dataB;
    art_rom u_art_rom (                          // Block Memory Generator: Dual Port ROM
        .clka (clk_25m), .addra(art_addrA), .douta(art_dataA),
        .clkb (clk_25m), .addrb(art_addrB), .doutb(art_dataB)
    );

    reg art_hitA_d3, art_hitB_d3;
    always @(posedge clk_25m) begin
        art_hitA_d3 <= art_okA;
        art_hitB_d3 <= art_okB;
        boss_hit3   <= boss_hit2;
    end

    // ------------------------------------------------------------------
    // World-space ripples left behind by the swimmer
    // ------------------------------------------------------------------
    wire [11:0] pc_x = player_wx + {4'd0, player_size[7:1]};
    wire [11:0] pc_y = player_wy + {4'd0, player_size[7:1]};
    wire [2:0]  pl_tile;
    map_rom u_map_rom_p (                         // second copy of map_rom: tile under the player
        .clka (clk_25m),
        .addra({pc_y[10:5], pc_x[10:5]}),
        .douta(pl_tile)
    );
    // water tiles: 0 water, 1 ripple water, 2 deep water, 4 seaweed
    reg pl_on_water;
    always @(posedge clk_25m)
        pl_on_water <= (pl_tile == 3'd0) || (pl_tile == 3'd1) || (pl_tile == 3'd2) || (pl_tile == 3'd4);

    localparam [4:0] WAKE_LIFETIME = 5'd24;
    localparam [11:0] WAKE_SPACING = 12'd44;
    reg [11:0] wake_x [0:3];
    reg [11:0] wake_y [0:3];
    reg [4:0] wake_age [0:3];
    reg [1:0] wake_head;
    reg [11:0] wake_anchor_x, wake_anchor_y;
    reg have_wake_anchor;
    wire [11:0] wake_travel_x = (pc_x > wake_anchor_x) ? pc_x - wake_anchor_x : wake_anchor_x - pc_x;
    wire [11:0] wake_travel_y = (pc_y > wake_anchor_y) ? pc_y - wake_anchor_y : wake_anchor_y - pc_y;
    wire wake_can_emit = player_moving &&
                         ({1'b0, wake_travel_x} + {1'b0, wake_travel_y} >= {1'b0, WAKE_SPACING});

    integer wake_slot;
    always @(posedge clk_25m) begin
        if (wake_reset || !wake_enabled) begin
            for (wake_slot = 0; wake_slot < 4; wake_slot = wake_slot + 1) begin
                wake_age[wake_slot] <= WAKE_LIFETIME;
                wake_x[wake_slot] <= 12'd0;
                wake_y[wake_slot] <= 12'd0;
            end
            wake_head <= 2'd0;
            have_wake_anchor <= 1'b0;
            wake_anchor_x <= pc_x;
            wake_anchor_y <= pc_y;
        end else if (wake_tick) begin
            for (wake_slot = 0; wake_slot < 4; wake_slot = wake_slot + 1)
                if (wake_age[wake_slot] < WAKE_LIFETIME)
                    wake_age[wake_slot] <= wake_age[wake_slot] + 5'd1;

            if (!pl_on_water || !have_wake_anchor) begin
                have_wake_anchor <= pl_on_water;
                wake_anchor_x <= pc_x;
                wake_anchor_y <= pc_y;
            end else if (wake_can_emit) begin
                // The previous sample remains fixed in world coordinates as the camera moves.
                wake_x[wake_head] <= wake_anchor_x;
                wake_y[wake_head] <= wake_anchor_y;
                wake_age[wake_head] <= 5'd0;
                wake_head <= wake_head + 2'd1;
                wake_anchor_x <= pc_x;
                wake_anchor_y <= pc_y;
            end
        end
    end

    wire [3:0] wake_bright, wake_medium, wake_faint;
    genvar wake_index;
    generate
        for (wake_index = 0; wake_index < 4; wake_index = wake_index + 1) begin : gen_wake_ring
            wire [11:0] dx = (world_x_d3 > wake_x[wake_index]) ? world_x_d3 - wake_x[wake_index] :
                                                              wake_x[wake_index] - world_x_d3;
            wire [11:0] dy = (world_y_d3 > wake_y[wake_index]) ? world_y_d3 - wake_y[wake_index] :
                                                              wake_y[wake_index] - world_y_d3;
            wire [4:0] age = wake_age[wake_index];
            wire [5:0] outer = 6'd6 + {1'b0, age} + {2'b00, age[4:1]};
            wire [5:0] inner = outer - 6'd2;
            wire [5:0] ell_y = {1'b0, dy[4:0]} + {2'b00, dy[4:1]};
            wire [11:0] sq_x = dx[5:0] * dx[5:0];
            wire [11:0] sq_y = ell_y * ell_y;
            wire [12:0] sq_distance = {1'b0, sq_x} + {1'b0, sq_y};
            wire [11:0] sq_inner = inner * inner;
            wire [11:0] sq_outer = outer * outer;
            wire in_ring = age < WAKE_LIFETIME && dx <= 12'd40 && dy <= 12'd27 &&
                           sq_distance >= {1'b0, sq_inner} && sq_distance <= {1'b0, sq_outer};
            assign wake_bright[wake_index] = in_ring && age < 5'd8;
            assign wake_medium[wake_index] = in_ring && age >= 5'd8 && age < 5'd16;
            assign wake_faint[wake_index] = in_ring && age >= 5'd16;
        end
    endgenerate

    wire [1:0] wake_strength = (|wake_bright) ? 2'd3 : (|wake_medium) ? 2'd2 :
                              (|wake_faint) ? 2'd1 : 2'd0;
    wire rp_on = wake_enabled && (wake_strength != 2'd0);
    wire [11:0] wake_background = (USE_TILE_MAP != 0) ? tile_data_d3 : 12'h024;

    function [3:0] ripple_channel;
        input [3:0] background, tint;
        input [1:0] strength;
        reg [6:0] sum;
        begin
            case (strength)
                2'd3: begin
                    sum = {3'd0, background} + {3'd0, tint} + 7'd1;
                    ripple_channel = sum[4:1];
                end
                2'd2: begin
                    sum = {2'd0, background, 1'b0} + {3'd0, background} + {3'd0, tint} + 7'd2;
                    ripple_channel = sum[5:2];
                end
                default: begin
                    sum = {background, 3'd0} - {3'd0, background} + {3'd0, tint} + 7'd4;
                    ripple_channel = sum[6:3];
                end
            endcase
        end
    endfunction

    wire [11:0] rp_color = {ripple_channel(wake_background[11:8], 4'h9, wake_strength),
                           ripple_channel(wake_background[7:4], 4'hE, wake_strength),
                           ripple_channel(wake_background[3:0], 4'hF, wake_strength)};

    // ------------------------------------------------------------------
    // ลูกศรชี้ทิศทาง & หนาม Spike ด้านหน้า
    // ------------------------------------------------------------------
    wire [11:0] p_cx = player_wx + {5'd0, player_size[7:1]};
    wire [11:0] p_cy = player_wy + {5'd0, player_size[7:1]};

    reg in_dir_arrow;
    reg in_front_spike;
    wire signed [13:0] marker_dx = $signed({2'd0, world_x_d3}) - $signed({2'd0, p_cx});
    wire signed [13:0] marker_dy = $signed({2'd0, world_y_d3}) - $signed({2'd0, p_cy});
    reg signed [21:0] marker_forward, marker_side;
    wire signed [21:0] marker_start = $signed({15'd0, player_size[7:1]});
    always @(*) begin
        // Project into the player's local axes, including diagonal debug markers.
        case (facing_dir)
            3'd0: begin marker_forward = -marker_dy; marker_side = marker_dx; end
            3'd1: begin marker_forward = marker_dx;  marker_side = marker_dy; end
            3'd2: begin marker_forward = marker_dy;  marker_side = marker_dx; end
            3'd3: begin marker_forward = -marker_dx; marker_side = marker_dy; end
            3'd4: begin marker_forward = ((marker_dx-marker_dy)*22'sd181) >>> 8;
                        marker_side = ((marker_dx+marker_dy)*22'sd181) >>> 8; end
            3'd5: begin marker_forward = ((marker_dx+marker_dy)*22'sd181) >>> 8;
                        marker_side = ((marker_dx-marker_dy)*22'sd181) >>> 8; end
            3'd6: begin marker_forward = ((-marker_dx+marker_dy)*22'sd181) >>> 8;
                        marker_side = ((marker_dx+marker_dy)*22'sd181) >>> 8; end
            default: begin marker_forward = ((-marker_dx-marker_dy)*22'sd181) >>> 8;
                           marker_side = ((marker_dx-marker_dy)*22'sd181) >>> 8; end
        endcase
        in_dir_arrow   = 1'b0;
        in_front_spike = 1'b0;
        if ((form_state != 3'd0) && (marker_forward >= marker_start) &&
            (marker_forward < marker_start + 22'sd10) &&
            (marker_side <= marker_start + 22'sd9 - marker_forward) &&
            (marker_side >= -(marker_start + 22'sd9 - marker_forward))) begin
            if (unlocked_skills[1]) in_front_spike = 1'b1;
            else                    in_dir_arrow   = 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // หลอดเลือดศัตรู & วงแหวนสกิลศัตรูทั้ง 16 ตัว
    // ------------------------------------------------------------------
    reg in_enemy_aura_shock, in_enemy_aura_poison, in_enemy_stun_ring;
    reg [11:0] ec_x, ec_y, edx, edy;
    reg [23:0] edist_sq;
    reg [15:0] er_in, er_out;
    integer b;

    always @(*) begin
        in_enemy_aura_shock  = 1'b0;
        in_enemy_aura_poison = 1'b0;
        in_enemy_stun_ring   = 1'b0;

        for (b = 0; b < 16; b = b + 1) begin
            if (enemies_alive[b]) begin
                ec_x = e_x[b] + {5'd0, e_sz[b][7:1]};
                ec_y = e_y[b] + {5'd0, e_sz[b][7:1]};
                edx  = (world_x_d3 > ec_x) ? (world_x_d3 - ec_x) : (ec_x - world_x_d3);
                edy  = (world_y_d3 > ec_y) ? (world_y_d3 - ec_y) : (ec_y - world_y_d3);
                edist_sq = (edx * edx) + (edy * edy);
                er_out   = ({8'd0, e_sz[b]} >> 1) + (enemies_e_shock[b] ? 16'd18 :
                           enemies_e_poison[b] ? 16'd12 : 16'd8);
                er_in    = er_out - 16'd3;

                if ((edist_sq >= (er_in * er_in)) && (edist_sq <= (er_out * er_out))) begin
                    if (enemies_stun[b])          in_enemy_stun_ring   = 1'b1;
                    else if (enemies_e_shock[b])  in_enemy_aura_shock  = 1'b1;
                    else if (enemies_e_poison[b]) in_enemy_aura_poison = 1'b1;
                end
            end
        end
    end

    // Boss state ring & alert banner ("BOSS TOTO AWAKE!")
    wire [11:0] boss_cx = boss_wx + {5'd0, boss_size[7:1]};
    wire [11:0] boss_cy = boss_wy + {5'd0, boss_size[7:1]};
    wire [11:0] bdx = (world_x_d3 > boss_cx) ? (world_x_d3 - boss_cx) : (boss_cx - world_x_d3);
    wire [11:0] bdy = (world_y_d3 > boss_cy) ? (world_y_d3 - boss_cy) : (boss_cy - world_y_d3);
    wire [23:0] bdist_sq = (bdx * bdx) + (bdy * bdy);
    wire [15:0] br_out   = ({8'd0, boss_size} >> 1) + 16'd10;
    wire [15:0] br_in    = br_out - 16'd4;
    wire        in_boss_ring = boss_active && (bdx <= {4'd0, boss_size}) && (bdy <= {4'd0, boss_size}) &&
                               (bdist_sq >= (br_in * br_in)) && (bdist_sq <= (br_out * br_out));
    wire [11:0] boss_ring_color = (boss_state == 3'd1) ? (frame_cnt[2] ? 12'hFF0 : 12'hF21) :
                                  (boss_state == 3'd2) ? 12'hF41 :
                                  (boss_state == 3'd3) ? (frame_cnt[3] ? 12'h3F9 : 12'h2C7) :
                                  (boss_state == 3'd4) ? 12'hFE4 :
                                  (boss_phase2 ? 12'hD13 : 12'h94A);

    localparam [671:0] BOSS_AWAKE_MSG = 672'h11f45145100e10e1003cf38f_0012516d1011111100410451_101151551011111100410451_10f0df55f01111110038e44f_101151451011111100041451_101251451011111100041451_11f44e44e00e7ce7c079e38f;
    wire in_boss_alert_box    = boss_alert && (game_state_d3 == 2'd1) &&
                                (px_d3 >= 10'd208) && (px_d3 < 10'd432) &&
                                (py_d3 >= 10'd225) && (py_d3 < 10'd255);
    wire in_boss_alert_border = in_boss_alert_box &&
                                ((px_d3 < 10'd210) || (px_d3 >= 10'd430) ||
                                 (py_d3 < 10'd227) || (py_d3 >= 10'd253));
    wire [7:0] alert_dx = px_d3 - 10'd224;
    wire [3:0] alert_dy = py_d3 - 10'd233;
    wire [6:0] alert_col  = alert_dx[7:1];
    wire [2:0] alert_line = alert_dy[3:1];
    wire [9:0] alert_idx  = {alert_line, 6'd0} + {alert_line, 5'd0} + {3'd0, alert_col};
    wire in_boss_alert_text = boss_alert && (game_state_d3 == 2'd1) &&
                              (px_d3 >= 10'd224) && (px_d3 < 10'd416) &&
                              (py_d3 >= 10'd233) && (py_d3 < 10'd247) &&
                              BOSS_AWAKE_MSG[alert_idx];

    // ------------------------------------------------------------------
    localparam [335:0] HUD_DASH = 336'h00000044f44f0000004504510000004504510000007ce7d100000044145100000044145100000045e38f;
    localparam [335:0] HUD_MORE_DMG = 336'h7913c07d13914514400494514514400454517554403cf45505544005145505b44005145b7913c07cf391;
    localparam [335:0] HUD_ELECTRIC = 336'h79f44479f7df0442440410410441440410410443c404f04f04444404104104444404104179f3df79f05f;
    localparam [335:0] HUD_POISON = 336'h00044e3df38100045140444100045140444100065138444f0005510444510004d104445100044e79f38f;
    localparam [335:0] HUD_LOCK = 336'h00000045e39f0000002414410000001414410000000c144100000014144100000024144100000045e381;
    localparam [335:0] HUD_READY = 336'h0000043d17d100000445104900000445104500000445f3cf00000a4510510000114510510000113ce7cf;
    localparam [335:0] HUD_ON = 336'h00000000044e0000000004510000000004510000000006510000000005510000000004d100000000044e;
    localparam [335:0] HUD_OFF = 336'h00000000104e00000000105100000000105100000000f3d100000000105100000000105100000001f7ce;
    localparam [335:0] HUD_WAIT = 336'h00000011f45100000010445b0000001044550000001047d50000001044510000001044510000007df391;

    wire in_dna_hud_box = px_d3 >= 10'd452 && px_d3 < 10'd635 && py_d3 >= 10'd6 && py_d3 < 10'd87;
    wire [1:0] skill_row = (py_d3 < 10'd28) ? 2'd0 : (py_d3 < 10'd47) ? 2'd1 :
                           (py_d3 < 10'd66) ? 2'd2 : 2'd3;
    wire [9:0] skill_y = (skill_row == 2'd0) ? 10'd10 : (skill_row == 2'd1) ? 10'd29 :
                          (skill_row == 2'd2) ? 10'd48 : 10'd67;
    wire [4:0] hud_dy = py_d3 - skill_y;
    wire [7:0] hud_dx = (px_d3 >= 10'd568) ? px_d3 - 10'd568 : px_d3 - 10'd462;
    wire [5:0] hud_col = hud_dx[6:1];
    wire [2:0] hud_line = hud_dy[3:1];
    wire [8:0] hud_index = {hud_line, 5'd0} + {hud_line, 4'd0} + {3'd0, hud_col};
    wire [335:0] skill_name = (skill_row == 2'd0) ? HUD_DASH : (skill_row == 2'd1) ? HUD_MORE_DMG :
                              (skill_row == 2'd2) ? HUD_ELECTRIC : HUD_POISON;
    wire skill_unlocked = unlocked_skills[skill_row];
    wire [335:0] skill_status = !skill_unlocked ? HUD_LOCK :
                               (skill_row == 2'd0) ? ((dash_cd_sec == 3'd0) ? HUD_READY : HUD_WAIT) :
                               (skill_row == 2'd1) ? HUD_ON :
                               (skill_row == 2'd2) ? (shock_active ? HUD_ON : HUD_OFF) :
                                                    (poison_active ? HUD_ON : HUD_OFF);
    wire in_hud_name = in_dna_hud_box && px_d3 >= 10'd462 && px_d3 < 10'd558 &&
                       py_d3 >= skill_y && py_d3 < skill_y + 10'd14 && skill_name[hud_index];
    wire in_hud_status = in_dna_hud_box && px_d3 >= 10'd568 && px_d3 < 10'd628 &&
                         py_d3 >= skill_y && py_d3 < skill_y + 10'd14 && skill_status[hud_index];
    wire [11:0] hud_status_color = !skill_unlocked ? 12'hA99 :
                                     (skill_row == 2'd2) ? 12'hD9F :
                                     (skill_row == 2'd3) ? 12'hFD5 : 12'h8F9;

    // HUD 1: หลอดเลือดผู้เล่นมุมซ้ายบน
    wire in_hp_border = (px_d3 >= 10'd14) && (px_d3 <= 10'd146) &&
                        (py_d3 >= 10'd14) && (py_d3 <= 10'd28);
    wire in_hp_bg     = (px_d3 >= 10'd16) && (px_d3 <  10'd144) &&
                        (py_d3 >= 10'd16) && (py_d3 <= 10'd26);
    wire [9:0] hp_width = {2'b00, player_hp} << 4;
    wire in_hp_fill   = in_hp_bg && (px_d3 < (10'd16 + hp_width));

    // HUD 3: Minimap มุมขวาล่าง (แสดงครบทั้ง 16 ตัว)
    wire in_mm_border = (px_d3 >= 10'd498) && (px_d3 <= 10'd629) &&
                        (py_d3 >= 10'd338) && (py_d3 <= 10'd469);
    wire in_mm_box    = (px_d3 >= 10'd500) && (px_d3 <  10'd628) &&
                        (py_d3 >= 10'd340) && (py_d3 <  10'd468);

    wire [6:0] mm_x = px_d3 - 10'd500;
    wire [6:0] mm_y = py_d3 - 10'd340;
    wire [6:0] p_mm_x = player_wx[11:4];
    wire [6:0] p_mm_y = player_wy[11:4];
    wire mm_dot_player = in_mm_box &&
                         (mm_x + 7'd1 >= p_mm_x) && (mm_x <= p_mm_x + 7'd1) &&
                         (mm_y + 7'd1 >= p_mm_y) && (mm_y <= p_mm_y + 7'd1);

    wire mm_dot_dna = in_mm_box && dna_active &&
                      (mm_x + 7'd1 >= dna_wx[11:4]) && (mm_x <= dna_wx[11:4] + 7'd1) &&
                      (mm_y + 7'd1 >= dna_wy[11:4]) && (mm_y <= dna_wy[11:4] + 7'd1);

    wire [6:0] boss_mm_x = boss_cx[10:4];
    wire [6:0] boss_mm_y = boss_cy[10:4];
    wire [6:0] bmm_dx = (mm_x >= boss_mm_x) ? (mm_x - boss_mm_x) : (boss_mm_x - mm_x);
    wire [6:0] bmm_dy = (mm_y >= boss_mm_y) ? (mm_y - boss_mm_y) : (boss_mm_y - mm_y);
    wire mm_pin_core  = in_mm_box && boss_active && (bmm_dx <= 7'd1) && (bmm_dy <= 7'd1);
    wire mm_pin_cross = in_mm_box && boss_active &&
                        (((bmm_dx == 7'd0) && (bmm_dy <= 7'd4)) ||
                         ((bmm_dy == 7'd0) && (bmm_dx <= 7'd4)) ||
                         ((bmm_dx == 7'd2) && (bmm_dy == 7'd2)));

    reg mm_dot_enemy_big, mm_dot_enemy_small, mm_dot_rock, mm_dot_rock_dna;
    integer m;
    always @(*) begin
        mm_dot_enemy_big   = 1'b0;
        mm_dot_enemy_small = 1'b0;
        mm_dot_rock        = 1'b0;
        mm_dot_rock_dna    = 1'b0;
        if (in_mm_box) begin
            for (m = 0; m < 16; m = m + 1) begin
                if (enemies_alive[m] &&
                    (mm_x + 7'd1 >= e_x[m][11:4]) && (mm_x <= e_x[m][11:4] + 7'd1) &&
                    (mm_y + 7'd1 >= e_y[m][11:4]) && (mm_y <= e_y[m][11:4] + 7'd1)) begin
                    if (e_sz[m] >= player_size) mm_dot_enemy_big   = 1'b1;
                    else                        mm_dot_enemy_small = 1'b1;
                end
            end
            for (m = 0; m < 8; m = m + 1) begin
                if ((mm_x == r_x[m][11:4]) && (mm_y == r_y[m][11:4])) begin
                    if (rocks_alive[m]) mm_dot_rock = 1'b1;
                    if (rock_dna_active[m]) mm_dot_rock_dna = 1'b1;
                end
            end
        end
    end

    // วงแหวนสกิลรอบตัวผู้เล่น
    wire [11:0] dx = (world_x_d3 > p_cx) ? (world_x_d3 - p_cx) : (p_cx - world_x_d3);
    wire [11:0] dy = (world_y_d3 > p_cy) ? (world_y_d3 - p_cy) : (p_cy - world_y_d3);
    wire [23:0] dist_sq = (dx * dx) + (dy * dy);

    wire [15:0] player_radius = {9'd0, player_size[7:1]};
    wire [15:0] electric_outer = player_radius + 16'd18;
    wire [15:0] electric_inner = electric_outer - 16'd3;
    wire [15:0] poison_outer = player_radius + 16'd12;
    wire [15:0] poison_inner = poison_outer - 16'd3;
    wire in_shock_ring = shock_active && (dist_sq >= electric_inner * electric_inner) &&
                        (dist_sq <= electric_outer * electric_outer);
    wire in_poison_ring = poison_active && (dist_sq >= poison_inner * poison_inner) &&
                         (dist_sq <= poison_outer * poison_outer);

    wire is_grid_line  = (world_x_d3[5:0] == 6'd0) || (world_y_d3[5:0] == 6'd0);
    wire is_world_edge = (world_x_d3 < 12'd16) || (world_x_d3 > 12'd2032) ||
                         (world_y_d3 < 12'd16) || (world_y_d3 > 12'd2032);

    reg [11:0] final_rgb;
    always @(*) begin
        if (!video_on_d3) begin
            final_rgb = 12'h000;
        end else if (game_state_d3 == 2'd0) begin
            final_rgb = ((px_d3 > 160 && px_d3 < 480) && (py_d3 > 180 && py_d3 < 300)) ? 12'h148 : 12'h013;
        end else if (game_state_d3 == 2'd2) begin
            final_rgb = ((px_d3 > 180 && px_d3 < 460) && (py_d3 > 200 && py_d3 < 280)) ? 12'h911 : 12'h400;
        end else if (in_hp_fill) begin
            final_rgb = is_perfect ? 12'hFD0 : (player_hp <= 8'd2 ? 12'hF22 : 12'h2E4);
        end else if (in_hp_bg) begin
            final_rgb = 12'h200;
        end else if (in_hp_border) begin
            final_rgb = 12'hFFF;
        end else if (in_hud_name) begin
            final_rgb = 12'hFED;
        end else if (in_hud_status) begin
            final_rgb = hud_status_color;
        end else if (in_dna_hud_box) begin
            final_rgb = 12'h321;
        end else if (in_boss_alert_text) begin
            final_rgb = 12'hFFF;
        end else if (in_boss_alert_border) begin
            final_rgb = frame_cnt[3] ? 12'hFD2 : 12'hF32;
        end else if (in_boss_alert_box) begin
            final_rgb = 12'h201;
        end else if (mm_dot_player) begin
            final_rgb = is_perfect ? 12'hFF0 : 12'hFFF;
        end else if (mm_pin_core) begin
            final_rgb = frame_cnt[4] ? 12'hFF0 : 12'hF0F;
        end else if (mm_pin_cross) begin
            final_rgb = 12'hF22;
        end else if (mm_dot_enemy_big) begin
            final_rgb = 12'hF11;
        end else if (mm_dot_enemy_small) begin
            final_rgb = 12'hF80;
        end else if (mm_dot_dna || mm_dot_rock_dna) begin
            final_rgb = 12'h2F6;
        end else if (mm_dot_rock) begin
            final_rgb = 12'h99A;
        end else if (in_mm_box) begin
            final_rgb = 12'h012;
        end else if (in_mm_border) begin
            final_rgb = 12'h48C;
        end else if (SHOW_SPIKE != 0 && in_front_spike) begin
            final_rgb = 12'hF31;
        end else if (SHOW_DIR_ARROW != 0 && in_dir_arrow) begin
            final_rgb = 12'hFFF;
        end else if (art_hitA_d3 && (art_dataA != 12'hF0F) && !rock_pick_pipe[2]) begin
            final_rgb = art_dataA;         // egg, player
        end else if (art_hitB_d3 && (art_dataB != 12'hF0F)) begin
            if (boss_hit3) begin
                if (boss_hit_flash)
                    final_rgb = 12'hFFF;
                else if ((boss_state == 3'd1) && frame_cnt[2])
                    final_rgb = 12'hFF4;
                else if (boss_phase2 && (boss_state != 3'd3) && (boss_state != 3'd4))
                    final_rgb = {4'hF, art_dataB[7:4], 1'b0, art_dataB[3:1]};
                else
                    final_rgb = art_dataB;
            end else begin
                final_rgb = art_dataB;     // DNA pickups, enemies, rocks
            end
        end else if (has_sprite_d3 && (rom_data_d3 != 12'hF0F)) begin
            final_rgb = rom_data_d3;       // rocks
        end else if (in_shock_ring) begin
            final_rgb = 12'hB6F;
        end else if (in_poison_ring) begin
            final_rgb = 12'hFD4;
        end else if (in_boss_ring) begin
            final_rgb = boss_ring_color;
        end else if (in_enemy_stun_ring) begin
            final_rgb = 12'hFE4;
        end else if (in_enemy_aura_shock) begin
            final_rgb = 12'hB6F;
        end else if (in_enemy_aura_poison) begin
            final_rgb = 12'hFD4;
        end else if (USE_TILE_MAP == 0 && is_world_edge) begin
            final_rgb = 12'h811;
        end else if (USE_TILE_MAP == 0 && is_grid_line) begin
            final_rgb = 12'h136;
        end else if (rp_on) begin
            final_rgb = rp_color;          // fading wake behind the swimmer
        end else if (USE_TILE_MAP != 0) begin
            final_rgb = tile_data_d3;       // tile map background
        end else begin
            final_rgb = 12'h024;
        end
    end

    assign rgb_out = final_rgb;

endmodule
