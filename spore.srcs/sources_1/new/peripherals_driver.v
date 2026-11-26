module peripherals_driver (
    input  wire        clk,
    input  wire        reset,
    input  wire [2:0]  form_state,      // 0:EGG, 1:BABY, 2:HERB, 3:CARN, 4:PERFECT
    input  wire        is_god_mode,
    input  wire [3:0]  unlocked_skills, // [0]:Dash(SW2), [1]:Swift, [2]:Electric(SW0), [3]:Poison(SW1)
    input  wire [13:0] score,           // คะแนน 0 - 9999
    input  wire [7:0]  player_hp,
    output wire [15:0] LED,
    output reg         LED16_R, LED16_G, LED16_B,
    output reg         CA, CB, CC, CD, CE, CF, CG,
    output wire        DP,
    output reg  [7:0]  AN
);

    assign DP = 1'b1; // ปิดจุดทศนิยม (Active Low)

    // 1. LED 16 ดวง:
    //    LED[7:0]   = หลอดเลือดผู้เล่น (HP 8 ขีด)
    //    LED[15:12] = ไฟบอกสถานะสกิลที่กดใช้ได้จริง:
    //                 LED[12] = Electric (SW0)
    //                 LED[13] = Poison   (SW1)
    //                 LED[14] = Dash     (SW2)
    //                 LED[15] = Swift    (ว่ายไวติดตัว)
    wire [7:0] hp_bar    = (8'hFF >> (8 - player_hp));
    wire [3:0] skill_led = {unlocked_skills[1], unlocked_skills[0], unlocked_skills[3], unlocked_skills[2]};
    assign LED = {skill_led, 4'b0000, hp_bar};

    // 2. RGB LED (PWM หรี่แสง + เปลี่ยนสีตามสายวิวัฒนาการ)
    reg [19:0] pwm_cnt;
    always @(posedge clk) pwm_cnt <= pwm_cnt + 20'd1;
    wire pwm_dim = (pwm_cnt[3:0] == 4'd0);

    always @(*) begin
        LED16_R = 1'b0; LED16_G = 1'b0; LED16_B = 1'b0;
        if (pwm_dim) begin
            case (form_state)
                3'd0: begin LED16_R = 1; LED16_G = 1; LED16_B = 1; end // ขาว = ไข่
                3'd1: begin LED16_R = 0; LED16_G = 1; LED16_B = 1; end // ฟ้า = Baby Cell
                3'd2: begin LED16_R = 0; LED16_G = 1; LED16_B = 0; end // เขียว = Herbivore
                3'd3: begin LED16_R = 1; LED16_G = 0; LED16_B = 0; end // แดง = Carnivore
                3'd4: begin // กะพริบสลับสีรุ้ง = Perfect Cell
                    LED16_R = pwm_cnt[19];
                    LED16_G = pwm_cnt[18];
                    LED16_B = ~pwm_cnt[19];
                end
            endcase
        end
    end

    // 3. แยกหลักคะแนน Score (0000 - 9999)
    wire [3:0] sc_thousands = (score / 14'd1000) % 14'd10;
    wire [3:0] sc_hundreds  = (score / 14'd100)  % 14'd10;
    wire [3:0] sc_tens      = (score / 14'd10)   % 14'd10;
    wire [3:0] sc_ones      =  score             % 14'd10;

    // 4. Time-Multiplexing สแกน 7-Segment ทั้ง 8 หลัก
    //    4 หลักซ้าย (AN7..AN4): โชว์คำว่า "SCOr" (หรือ "PErF" ตอนเป็น Perfect Cell)
    //    4 หลักขวา (AN3..AN0): โชว์แต้มคะแนน 4 หลัก (0000 - 9999)
    reg [4:0] char_code;
    // รหัสตัวอักษร: 0-9 = ตัวเลข, 10=P, 11=E, 12=r, 13=F, 14=S, 15=C, 16=O, 31=Blank
    always @(*) begin
        AN = 8'b1111_1111;
        char_code = 5'd31;
        case (pwm_cnt[17:15])
            3'd0: begin AN = 8'b1111_1110; char_code = {1'b0, sc_ones}; end
            3'd1: begin AN = 8'b1111_1101; char_code = {1'b0, sc_tens}; end
            3'd2: begin AN = 8'b1111_1011; char_code = {1'b0, sc_hundreds}; end
            3'd3: begin AN = 8'b1111_0111; char_code = {1'b0, sc_thousands}; end
            3'd4: begin AN = 8'b1110_1111; char_code = is_god_mode ? 5'd13 : 5'd12; end // 'F' / 'r'
            3'd5: begin AN = 8'b1101_1111; char_code = is_god_mode ? 5'd12 : 5'd16; end // 'r' / 'O'
            3'd6: begin AN = 8'b1011_1111; char_code = is_god_mode ? 5'd11 : 5'd15; end // 'E' / 'C'
            3'd7: begin AN = 8'b0111_1111; char_code = is_god_mode ? 5'd10 : 5'd14; end // 'P' / 'S'
        endcase
    end

    // ถอดรหัส Cathode (Active Low: 0 = ติด, 1 = ดับ)
    always @(*) begin
        case (char_code)
            5'd0:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0000001; // 0
            5'd1:  {CA,CB,CC,CD,CE,CF,CG} = 7'b1001111; // 1
            5'd2:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0010010; // 2
            5'd3:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0000110; // 3
            5'd4:  {CA,CB,CC,CD,CE,CF,CG} = 7'b1001100; // 4
            5'd5:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0100100; // 5
            5'd6:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0100000; // 6
            5'd7:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0001111; // 7
            5'd8:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0000000; // 8
            5'd9:  {CA,CB,CC,CD,CE,CF,CG} = 7'b0000100; // 9
            5'd10: {CA,CB,CC,CD,CE,CF,CG} = 7'b0011000; // P
            5'd11: {CA,CB,CC,CD,CE,CF,CG} = 7'b0110000; // E
            5'd12: {CA,CB,CC,CD,CE,CF,CG} = 7'b1111010; // r
            5'd13: {CA,CB,CC,CD,CE,CF,CG} = 7'b0111000; // F
            5'd14: {CA,CB,CC,CD,CE,CF,CG} = 7'b0100100; // S
            5'd15: {CA,CB,CC,CD,CE,CF,CG} = 7'b0110001; // C
            5'd16: {CA,CB,CC,CD,CE,CF,CG} = 7'b0000001; // O
            default: {CA,CB,CC,CD,CE,CF,CG} = 7'b1111111; // ดับ
        endcase
    end

endmodule