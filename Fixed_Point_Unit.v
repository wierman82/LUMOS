`include "Defines.vh"

module Fixed_Point_Unit 
#(
    parameter WIDTH = 32,
    parameter FBITS = 10
)
(
    input wire clk,
    input wire reset,
    
    input wire [WIDTH - 1 : 0] operand_1,
    input wire [WIDTH - 1 : 0] operand_2,
    
    input wire [ 1 : 0] operation,

    output reg [WIDTH - 1 : 0] result,
    output reg ready
);

    // State definitions
    typedef enum reg [2:0] {
        IDLE = 3'b000,
        MUL_P1 = 3'b001,
        MUL_P2 = 3'b010,
        MUL_P3 = 3'b011,
        MUL_P4 = 3'b100,
        FINISH = 3'b101
    } state_t;
    
    state_t state, next_state;
    
    reg [31:0] partialProduct1, partialProduct2, partialProduct3, partialProduct4;
    reg [63:0] product;
    reg product_ready;
    
    wire [15:0] A1 = operand_1[15:0];
    wire [15:0] A2 = operand_1[31:16];
    wire [15:0] B1 = operand_2[15:0];
    wire [15:0] B2 = operand_2[31:16];
    
    wire [31:0] P;
    
    reg [15:0] mul_op1, mul_op2;
    
    Multiplier multiplier (
        .operand_1(mul_op1),
        .operand_2(mul_op2),
        .product(P)
    );

    // State transition logic
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // Next state logic
    always @(*) begin
        case (state)
            IDLE: next_state = (operation == `FPU_MUL) ? MUL_P1 : IDLE;
            MUL_P1: next_state = MUL_P2;
            MUL_P2: next_state = MUL_P3;
            MUL_P3: next_state = MUL_P4;
            MUL_P4: next_state = FINISH;
            FINISH: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Output and operation logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ready <= 0;
            result <= 0;
            partialProduct1 <= 0;
            partialProduct2 <= 0;
            partialProduct3 <= 0;
            partialProduct4 <= 0;
            product <= 0;
            product_ready <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    product_ready <= 0;
                end
                MUL_P1: begin
                    mul_op1 <= A1;
                    mul_op2 <= B1;
                    partialProduct1 <= P;
                end
                MUL_P2: begin
                    mul_op1 <= A1;
                    mul_op2 <= B2;
                    partialProduct2 <= P << 16;
                end
                MUL_P3: begin
                    mul_op1 <= A2;
                    mul_op2 <= B1;
                    partialProduct3 <= P << 16;
                end
                MUL_P4: begin
                    mul_op1 <= A2;
                    mul_op2 <= B2;
                    partialProduct4 <= P << 32;
                end
                FINISH: begin
                    product <= partialProduct1 + partialProduct2 + partialProduct3 + partialProduct4;
                    product_ready <= 1;
                    result <= product[WIDTH + FBITS - 1 : FBITS];
                    ready <= 1;
                end
            endcase
        end
    end

    // Handling other operations
    always @(*) begin
        if (operation != `FPU_MUL) begin
            case (operation)
                `FPU_ADD: begin result = operand_1 + operand_2; ready = 1; end
                `FPU_SUB: begin result = operand_1 - operand_2; ready = 1; end
                `FPU_SQRT: begin result = root; ready = root_ready; end
                default: begin result = 'bz; ready = 0; end
            endcase
        end
    end

    // Square Root Circuit (to be implemented)
    reg [WIDTH - 1 : 0] root;
    reg root_ready;

reg [2:0] sqrt_state;
reg [WIDTH - 1 : 0] radicand;
reg [WIDTH - 1 : 0] res;
reg [WIDTH - 1 : 0] iteration;
reg [WIDTH - 1 : 0] temp;
reg [WIDTH - 1 : 0] reminder;
reg [WIDTH - 1 : 0] op1;
reg [1 : 0] bits;

always @(posedge clk or posedge reset)
begin
    if (reset) begin
        sqrt_state <= 0;
        root <= 0;
        root_ready <= 0;
        op1 <= operand_1;
    end else if (operation == `FPU_SQRT) begin
        case (sqrt_state)
            0: begin 
                radicand <= operand_1[WIDTH - 1: WIDTH - 2];
                res <= 0;
                temp <= 2'b01;
                iteration <= (WIDTH + FBITS) / 2;
                sqrt_state <= 1;
            end
            1: begin 
                if(iteration > 0) begin
                    reminder <= radicand - temp;
                    if(reminder < 0) begin
                        res <= (res << 1);
                    end else begin
                        res <= (res << 1) + 1;
                    end
                    op1 <= (op1 << 2);
                    bits <= op1[WIDTH - 1 : WIDTH - 2];
                    radicand <= (radicand << 2) + bits;
                    temp <= (res << 2) + 1 ;    
                    iteration <= iteration - 1;
                end else begin 
                    sqrt_state <= 2;
                end
            end
            2: begin 
                root <= res;
                root_ready <= 1;
                sqrt_state <= 0;
            end
        endcase
    end    
end

endmodule

module Multiplier
(
    input wire [15 : 0] operand_1,
    input wire [15 : 0] operand_2,
    
    output reg [31 : 0] product
);

    always @(*)
    begin
        product <= operand_1 * operand_2;
    end
endmodule
