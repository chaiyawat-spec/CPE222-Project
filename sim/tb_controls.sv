`timescale 1ns/1ps
module tb_controls;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst = 1, tick = 0;
    reg [1:0] run = 1;
    reg up = 0, down = 0, left = 0, right = 0;
    top_game dut(.CLK100MHZ(clk), .CPU_RESETN(1'b1),
        .BTNU(1'b0), .BTND(1'b0), .BTNL(1'b0), .BTNR(1'b0), .BTNC(1'b0),
        .UART_TXD_IN(1'b1), .SW(6'd0));

    integer mask, expected, xdir, ydir, previous;
    integer d, size, sx, sy, cx, cy, offset, ex, ey;
    integer dir_x [0:7];
    integer dir_y [0:7];

    task step;
        begin @(negedge clk); tick = 1; @(negedge clk); tick = 0; #1; end
    endtask

    initial begin
        // Bypass real-time debounce/frame dividers while exercising the actual
        // top_game sequential block and all of its real module connections.
        force dut.game_rst = rst;
        force dut.run_state = run;
        force dut.frame_tick = tick;
        force dut.up_s = up;
        force dut.down_s = down;
        force dut.left_s = left;
        force dut.right_s = right;
        repeat (4) @(negedge clk);
        if (dut.facing_dir !== 3'd1) $fatal(1, "Reset must face E");
        rst = 0;
        previous = 1;
        for (mask = 0; mask < 16; mask = mask + 1) begin
            {up, down, left, right} = mask[3:0];
            xdir = right - left;
            ydir = down - up;
            expected = previous;
            if (ydir < 0 && xdir == 0) expected = 0;
            if (ydir == 0 && xdir > 0) expected = 1;
            if (ydir > 0 && xdir == 0) expected = 2;
            if (ydir == 0 && xdir < 0) expected = 3;
            if (ydir < 0 && xdir > 0) expected = 4;
            if (ydir > 0 && xdir > 0) expected = 5;
            if (ydir > 0 && xdir < 0) expected = 6;
            if (ydir < 0 && xdir < 0) expected = 7;
            step;
            if (dut.facing_dir !== expected[2:0])
                $fatal(1, "Buttons %b: expected %0d, got %0d", mask[3:0], expected, dut.facing_dir);
            previous = expected;
        end
        {up, down, left, right} = 4'b1001;
        step;
        if (dut.facing_dir !== 4) $fatal(1, "Up+Right must face NE");
        {up, down, left, right} = 0;
        repeat (4) step;
        if (dut.facing_dir !== 4) $fatal(1, "Release must retain NE");
        run = 2; {up, down, left, right} = 4'b0110;
        step;
        if (dut.facing_dir !== 4) $fatal(1, "Pause must freeze facing");
        run = 1;
        repeat (4) @(negedge clk);
        if (dut.facing_dir !== 4) $fatal(1, "No frame tick must freeze facing");
        step;
        if (dut.facing_dir !== 6) $fatal(1, "Resume must face SW");
        run = 0; step;
        if (dut.facing_dir !== 1) $fatal(1, "Menu must reset facing E");
        run = 1; rst = 1; step; rst = 0;
        {up, down, left, right} = 4'b1001;
        step; step;
        if (!(dut.vx > 0 && dut.vy < 0)) $fatal(1, "NE velocity signs incorrect");
        rst = 1; step; rst = 0;
        {up, down, left, right} = 4'b1111;
        step;
        if (dut.vx !== 0 || dut.vy !== 0) $fatal(1, "Opposite buttons must cancel movement");

        // Test real collision geometry at every gameplay size and all directions.
        dir_x[0]=0; dir_y[0]=-1; dir_x[1]=1; dir_y[1]=0;
        dir_x[2]=0; dir_y[2]=1; dir_x[3]=-1; dir_y[3]=0;
        dir_x[4]=1; dir_y[4]=-1; dir_x[5]=1; dir_y[5]=1;
        dir_x[6]=-1; dir_y[6]=1; dir_x[7]=-1; dir_y[7]=-1;
        force dut.player_size = size;
        force dut.facing_dir = d;
        force dut.player_wx = 12'd1000;
        force dut.player_wy = 12'd1000;
        force dut.u_eco.spike_unlocked = 1'b1;
        for (size=16; size<=160; size=size+2) begin
            for (d=0; d<8; d=d+1) begin
                #1;
                // Independent geometric oracle: midpoint of the forward spike.
                offset = $rtoi((size / 2.0 + (size / 2.0 + 8.0) / 2.0) * (d < 4 ? 1.0 : 0.70710678118));
                cx = 1000 + size/2 + dir_x[d]*offset;
                cy = 1000 + size/2 + dir_y[d]*offset;
                if (!dut.u_eco.check_aabb_rect(dut.u_eco.spk_x, dut.u_eco.spk_y,
                    dut.u_eco.spk_w, dut.u_eco.spk_h, cx-1, cy-1, 8'd2))
                    $fatal(1, "Spike misses its nose: size=%0d dir=%0d", size, d);
                ex = 1000 + size/2 - dir_x[d]*(size+32);
                ey = 1000 + size/2 - dir_y[d]*(size+32);
                if (dut.u_eco.check_aabb_rect(dut.u_eco.spk_x, dut.u_eco.spk_y,
                    dut.u_eco.spk_w, dut.u_eco.spk_h, ex, ey, 8'd2))
                    $fatal(1, "Spike points backwards: size=%0d dir=%0d", size, d);
                if (d == 0 && (dut.u_eco.spk_w !== size/2 || dut.u_eco.spk_h !== size/2+8))
                    $fatal(1, "Cardinal spike dimensions changed");
            end
        end
        force dut.player_wx = 12'd16;
        force dut.player_wy = 12'd16;
        size = 160;
        for (d=0; d<8; d=d+1) begin
            #1;
            if (dut.u_eco.spk_x > 400 || dut.u_eco.spk_y > 400)
                $fatal(1, "Spike wrapped at world edge");
        end
        $display("PASS controls: all 16 button combinations, NE movement, release, pause, reset, frame gating");
        $display("PASS collision: 73 sizes x 8 directions, front/back checks and world-edge clamping");
        $finish;
    end
    initial begin #100000; $fatal(1, "Control test timeout"); end
endmodule
