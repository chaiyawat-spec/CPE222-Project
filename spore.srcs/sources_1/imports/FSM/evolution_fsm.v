module evolution_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       clear,
    input  wire [3:0] got_dna,
    output wire [1:0] form,
    output wire       secret_form,
    output wire [3:0] dna_mask
);
    localparam FORM1 = 2'd0;
    localparam FORM2 = 2'd1;
    localparam FORM3 = 2'd2;

    reg [1:0] state, next_state;
    reg [3:0] mask;

    wire [3:0] mask_next = mask | got_dna;

    always @(posedge clk or posedge rst) begin
        if (rst)        mask <= 4'b0000;
        else if (clear) mask <= 4'b0000;
        else            mask <= mask_next;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) state <= FORM1;
        else     state <= next_state;
    end

    always @(*) begin
        next_state = state;
        if (clear) next_state = FORM1;
        else begin
            case (state)
                FORM1: begin
                    if      (mask_next == 4'b1111) next_state = FORM3;
                    else if (mask_next != 4'b0000) next_state = FORM2;
                end
                FORM2: if (mask_next == 4'b1111)   next_state = FORM3;
                FORM3: ;
                default: next_state = FORM1;
            endcase
        end
    end

    assign form        = state;
    assign secret_form = (state == FORM3);
    assign dna_mask    = mask;
endmodule
