module button_debouncer (
    input  wire clk,         // ใช้ Clock 100 MHz หรือ 25 MHz ก็ได้
    input  wire btn_in,
    output reg  btn_state,   // สถานะปุ่มค้าง (สำหรับกดเดินค้าง)
    output wire btn_pulse    // จังหวะกด 1 ครั้ง (สำหรับกดฟักไข่/ใช้สกิล)
);

    reg [19:0] count;
    reg btn_sync_0, btn_sync_1;
    reg btn_prev;

    // 2-Stage Synchronizer ป้องกัน Metastability
    always @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end

    // นับหน่วงเวลา ~10ms - 20ms เพื่อตัดสัญญาณสั่น
    always @(posedge clk) begin
        if (btn_sync_1 == btn_state) begin
            count <= 20'd0;
        end else begin
            count <= count + 20'd1;
            if (count == 20'd500_000) begin // ~20ms ที่ 25MHz
                btn_state <= btn_sync_1;
                count <= 20'd0;
            end
        end
    end

    // สร้าง Single Pulse ตอนจังหวะกดลง (Rising Edge)
    always @(posedge clk) begin
        btn_prev <= btn_state;
    end

    assign btn_pulse = btn_state && ~btn_prev;

endmodule