module top_phase1 (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN, // ปุ่มรีเซ็ตบน Nexys A7 (Active Low!)
    input  wire        BTNU, BTND, BTNL, BTNR, BTNC,
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [4:0]  LED         // ไฟเช็กสถานะปุ่มกด
);

    wire reset = ~CPU_RESETN; // แปลงเป็น Active High
    wire clk_25m;
    wire locked;

    // 1. สร้าง Pixel Clock 25.175 MHz
    clk_wiz_0 u_clk_wiz (
        .clk_in1(CLK100MHZ),
        .reset(reset),
        .clk_out1(clk_25m),
        .locked(locked)
    );

    // 2. VGA Controller
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

    // 3. Debouncer สำหรับปุ่มทั้ง 5
    wire up_s, down_s, left_s, right_s, center_s;
    wire center_pulse;

    button_debouncer db_u (.clk(clk_25m), .btn_in(BTNU), .btn_state(up_s),     .btn_pulse());
    button_debouncer db_d (.clk(clk_25m), .btn_in(BTND), .btn_state(down_s),   .btn_pulse());
    button_debouncer db_l (.clk(clk_25m), .btn_in(BTNL), .btn_state(left_s),   .btn_pulse());
    button_debouncer db_r (.clk(clk_25m), .btn_in(BTNR), .btn_state(right_s),  .btn_pulse());
    button_debouncer db_c (.clk(clk_25m), .btn_in(BTNC), .btn_state(center_s), .btn_pulse(center_pulse));

    // โชว์ไฟ LED เวลากดปุ่ม (เอาไว้เช็กว่าปุ่มทำงานชัวร์)
    assign LED = {center_s, right_s, left_s, down_s, up_s};

    // 4. ทดสอบขยับสี่เหลี่ยม (จำลองตัวผู้เล่นขนาด 24x24)
    localparam BOX_SIZE = 10'd24;
    localparam SPEED    = 10'd3;
    reg [9:0] player_x;
    reg [9:0] player_y;

    always @(posedge clk_25m or posedge reset) begin
        if (reset) begin
            player_x <= 10'd308; // กลางจอ X
            player_y <= 10'd228; // กลางจอ Y
        end else if (frame_tick) begin
            if (up_s    && player_y > SPEED)                player_y <= player_y - SPEED;
            if (down_s  && player_y < 480 - BOX_SIZE - SPEED) player_y <= player_y + SPEED;
            if (left_s  && player_x > SPEED)                player_x <= player_x - SPEED;
            if (right_s && player_x < 640 - BOX_SIZE - SPEED) player_x <= player_x + SPEED;
        end
    end

    // 5. วาดภาพลงจอ (Renderer ทดสอบ)
    wire is_player = (pixel_x >= player_x) && (pixel_x < player_x + BOX_SIZE) &&
                     (pixel_y >= player_y) && (pixel_y < player_y + BOX_SIZE);

    reg [11:0] rgb_next;
    always @(*) begin
        if (!video_on) begin
            rgb_next = 12'h000; // นอกพื้นที่แสดงผลต้องเป็นสีดำเสมอ
        end else if (is_player) begin
            rgb_next = center_s ? 12'h0F0 : 12'hFFF; // กดปุ่มกลางเปลี่ยนเป็นสีเขียว ปกติสีขาว
        end else begin
            rgb_next = 12'h025; // พื้นหลังสีน้ำเงินเข้ม (ใต้ทะเล)
        end
    end

    assign VGA_R = rgb_next[11:8];
    assign VGA_G = rgb_next[7:4];
    assign VGA_B = rgb_next[3:0];

endmodule