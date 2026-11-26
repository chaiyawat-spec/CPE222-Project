`timescale 1ns/1ps
module tb_renderer;
    reg clk = 0;
    always #5 clk = !clk;
    reg [9:0] px = 280, py = 200;
    reg [2:0] direction = 0;
    reg carnivore = 0;
    reg [3:0] skills = 0;
    reg moving = 1;
    reg [8:0] frame = 0;
    wire [11:0] rgb;
    sprite_renderer dut(
        .clk_25m(clk), .video_on(1'b1), .pixel_x(px), .pixel_y(py),
        .cam_x(12'd768), .cam_y(12'd768), .game_state(2'd1), .form_state(3'd1),
        .unlocked_skills(skills), .facing_dir(direction), .is_carnivore(carnivore),
        .egg_taps(4'd0), .egg_fx(1'b0), .player_moving(moving),
        .wake_reset(1'b1), .wake_tick(1'b0), .wake_enabled(1'b0),
        .shock_active(1'b0), .poison_active(1'b0),
        .shock_cd_sec(3'd0), .poison_cd_sec(3'd0), .dash_cd_sec(3'd0),
        .player_hp(8'd8), .player_size(8'd32), .player_wx(12'd1072), .player_wy(12'd992),
        .rocks_wx(96'd0), .rocks_wy(96'd0), .rocks_alive(8'd0), .rocks_cracked(8'd0),
        .rock_dna_active(8'd0), .rock_dna_types(16'd0),
        .enemies_wx(192'd0), .enemies_wy(192'd0), .enemies_alive(16'd0),
        .enemies_sz({16{8'd16}}), .enemies_dna(64'd0), .enemies_stun(16'd0),
        .enemies_e_shock(16'd0), .enemies_e_poison(16'd0),
        .dna_wx(12'd0), .dna_wy(12'd0), .dna_active(1'b0), .dna_type(2'd0),
        .boss_wx(12'd0), .boss_wy(12'd0), .boss_size(8'd180), .boss_active(1'b0),
        .boss_state(3'd0), .boss_phase2(1'b0), .boss_alert(1'b0), .boss_hit_flash(1'b0),
        .rgb_out(rgb));

    reg [6:0] tex_x, tex_y;
    reg [2:0] phase;
    reg [4:0] atlas_index;
    integer d, x, y, a, m, n, expected_x, expected_y, checks = 0;
    integer body, variant, f, file_out, cycle;
    real theta, oracle_x, oracle_y;
    integer dir_x [0:7];
    integer dir_y [0:7];

    task capture;
        begin
            // One pixel per clock, exactly like VGA. Capture after three stages
            // using delayed DUT pixel coordinates to check pipeline alignment.
            file_out = $fopen($sformatf("render_%0d_%0d_%0d_%0d.hex",body,variant,f,d), "w");
            for (cycle=0; cycle<6403; cycle=cycle+1) begin
                @(negedge clk);
                px = 280 + (cycle % 80); py = 200 + (cycle / 80);
                @(posedge clk); #1;
                // Input at cycle c appears after edge c+2 (three registers).
                if (dut.px_d3 >= 280 && dut.px_d3 < 360 &&
                    dut.py_d3 >= 200 && dut.py_d3 < 280 && cycle >= 2 && cycle < 6402) begin
                    if ((^rgb) === 1'bx) $fatal(1, "Unknown VGA pixel");
                    $fdisplay(file_out, "%03h", rgb);
                end
            end
            $fclose(file_out);
        end
    endtask

    initial begin
        force dut.frame_cnt = frame;
        repeat (60) @(negedge clk); // reciprocal dividers settle
        force dut.txA2 = tex_x;
        force dut.tyA2 = tex_y;
        force dut.faceA2 = direction;
        force dut.kA2 = 3'd1;
        force dut.nA2 = atlas_index;
        force dut.anA2 = phase;
        force dut.mvA2 = moving;
        atlas_index = 31;
        for (d=0; d<8; d=d+1) begin
            direction = d;
            theta = (d<4 ? d*90.0 : 45.0+(d-4)*90.0)*3.141592653589793/180.0;
            for (y=0; y<48; y=y+1) begin
                for (x=0; x<48; x=x+1) begin
                    tex_x=x; tex_y=y;
                    oracle_x = 23.5 + (x-23.5)*$cos(theta) + (y-23.5)*$sin(theta);
                    oracle_y = 23.5 - (x-23.5)*$sin(theta) + (y-23.5)*$cos(theta);
                    expected_x = $rtoi($floor(oracle_x+0.5000001));
                    expected_y = $rtoi($floor(oracle_y+0.5000001));
                    #1;
                    if (dut.rot_x < expected_x-1 || dut.rot_x > expected_x+1 ||
                        dut.rot_y < expected_y-1 || dut.rot_y > expected_y+1)
                        $fatal(1, "Rotation differs from geometric oracle: dir=%0d x=%0d y=%0d", d,x,y);
                    if (d<4 && (dut.rot_x != expected_x || dut.rot_y != expected_y))
                        $fatal(1, "Cardinal rotation changed");
                    for (m=0; m<2; m=m+1) begin
                        moving=m;
                        for (a=0; a<8; a=a+1) begin
                            phase=a; #1;
                            if (dut.art_okA && (dut.art_addrA < 31*2304 || dut.art_addrA >= 32*2304))
                                $fatal(1, "Player read escaped its atlas tile");
                            if (!dut.rot_ok && dut.art_okA) $fatal(1, "Outside rotation must be transparent");
                            checks=checks+1;
                        end
                    end
                end
            end
        end
        // Ensure every DNA/body atlas selection stays within its own 48x48 tile.
        tex_x=24; tex_y=24; direction=4; phase=0;
        for (n=0; n<32; n=n+1) begin
            atlas_index=n; #1;
            if (!dut.art_okA || dut.art_addrA < n*2304 || dut.art_addrA >= (n+1)*2304)
                $fatal(1, "Bad body/DNA atlas selection %0d",n);
        end
        release dut.txA2; release dut.tyA2; release dut.faceA2;
        release dut.kA2; release dut.nA2; release dut.anA2; release dut.mvA2;
        moving=1;
        $display("PASS renderer: %0d rotation/sway checks, 32 body/DNA atlas selections", checks);

        // Optional arrow/spike debug geometry must face the same eight directions.
        dir_x[0]=0; dir_y[0]=-1; dir_x[1]=1; dir_y[1]=0;
        dir_x[2]=0; dir_y[2]=1; dir_x[3]=-1; dir_y[3]=0;
        dir_x[4]=1; dir_y[4]=-1; dir_x[5]=1; dir_y[5]=1;
        dir_x[6]=-1; dir_y[6]=1; dir_x[7]=-1; dir_y[7]=-1;
        for (d=0; d<8; d=d+1) begin
            direction=d; skills=0;
            @(negedge clk);
            px=320+dir_x[d]*(d<4?22:16); py=240+dir_y[d]*(d<4?22:16);
            repeat (5) @(negedge clk);
            if (!dut.in_dir_arrow) $fatal(1, "Debug arrow missing in dir %0d",d);
            skills=2; #1;
            if (!dut.in_front_spike) $fatal(1, "Debug spike missing in dir %0d",d);
        end
        $display("PASS renderer: debug arrow and spike all 8 directions");

        // Actual RGB output and actual .coe assets, with the full renderer pipeline.
        for (body=0; body<2; body=body+1) begin
            carnivore=body;
            for (variant=0; variant<2; variant=variant+1) begin
                skills=variant?15:0;
                for (f=0; f<(variant?8:1); f=f+1) begin
                    frame=f*4;
                    for (d=0; d<8; d=d+1) begin
                        direction=d;
                        repeat (5) @(negedge clk);
                        capture;
                    end
                end
            end
        end
        $display("PASS capture: 144 VGA crops, 8 directions, 2 bodies, base/full DNA, 8 swim phases");
        $finish;
    end
    initial begin #100000000; $fatal(1, "Renderer test timeout"); end
endmodule
