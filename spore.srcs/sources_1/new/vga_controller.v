module vga_controller (
    input  wire       clk_25m,     // Pixel Clock 25.175 MHz
    input  wire       reset,
    output wire       hsync,
    output wire       vsync,
    output wire       video_on,    // 1 เมื่ออยู่ในพื้นที่แสดงผล 640x480
    output wire [9:0] pixel_x,     // พิกัด X (0 - 639)
    output wire [9:0] pixel_y,     // พิกัด Y (0 - 479)
    output wire       frame_tick   // Pulse 1 จังหวะทุกครั้งที่ขึ้นเฟรมใหม่ (60Hz)
);

    // ค่ามาตรฐาน VGA 640x480 @ 60Hz
    localparam HD = 640; // Horizontal Display
    localparam HF = 16;  // Front Porch
    localparam HB = 48;  // Back Porch
    localparam HR = 96;  // Sync Pulse
    localparam H_MAX = HD + HF + HB + HR - 1; // 799

    localparam VD = 480; // Vertical Display
    localparam VF = 10;  // Front Porch
    localparam VB = 33;  // Back Porch
    localparam VR = 2;   // Sync Pulse
    localparam V_MAX = VD + VF + VB + VR - 1; // 524

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk_25m or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_MAX) begin
                h_count <= 10'd0;
                if (v_count == V_MAX)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Sync signals (Active Low)
    assign hsync = ~((h_count >= (HD + HF)) && (h_count <= (HD + HF + HR - 1)));
    assign vsync = ~((v_count >= (VD + VF)) && (v_count <= (VD + VF + VR - 1)));

    // Active Video Region
    assign video_on = (h_count < HD) && (v_count < VD);
    assign pixel_x  = h_count;
    assign pixel_y  = v_count;

    // ส่งสัญญาณอัปเดตเกมเพลย์ 1 ครั้งต่อเฟรม (ตอนจบเส้นสแกนสุดท้าย)
    assign frame_tick = (h_count == 10'd0) && (v_count == VD);

endmodule