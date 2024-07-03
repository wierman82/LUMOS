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
    typedef  reg [2:0] {
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

localparam INIT = 2'b00, BEGIN = 2'b01, COMPUTE = 2'b10, FINISH = 2'b11;

reg [1:0] sqrt_current_state, sqrt_next_state;

reg sqrt_initiate;
reg sqrt_active;

reg [WIDTH-1:0] operand_reg, operand_next;
reg [WIDTH-1:0] result_reg, result_next;
reg [WIDTH+1:0] accum, accum_next;
reg [WIDTH+1:0] trial_result;

reg [4:0] step_count = 0;

// State transition for the square root state machine
always @(posedge clk) begin
    if (operation == FPU_SQRT)
        sqrt_current_state <= sqrt_next_state;
    else
        sqrt_current_state <= INIT;
        root_ready <= 0;
end

// Next state logic for the square root state machine
always @(*) begin
    sqrt_next_state = sqrt_current_state;
    case (sqrt_current_state)
        INIT:
            if (operation == FPU_SQRT) begin
                sqrt_next_state = BEGIN;
                sqrt_initiate <= 0;
            end
        BEGIN:
            begin
                sqrt_next_state = COMPUTE;
                sqrt_initiate <= 1;
            end
        COMPUTE:
            begin
                if (step_count == ((WIDTH + FBITS) >> 1) - 1) begin
                    sqrt_next_state = FINISH;
                    sqrt_initiate <= 0;
                end
            end
        FINISH:
            sqrt_next_state = INIT;
    endcase
end

// Combinational logic to perform one iteration of the square root calculation
always @(*) begin
    trial_result = accum - {result_reg, 2'b01};

    if (trial_result[WIDTH + 1] == 0) begin
        {accum_next, operand_next} = {trial_result[WIDTH-1:0], operand_reg, 2'b0};
        result_next = {result_reg[WIDTH-2:0], 1'b1};
    end else begin
        {accum_next, operand_next} = {accum[WIDTH-1:0], operand_reg, 2'b0};
        result_next = result_reg << 1;
    end
end

// Sequential logic to update the square root state machine
always @(posedge clk) begin
    if (sqrt_initiate) begin
        sqrt_active <= 1;
        root_ready <= 0;
        step_count <= 0;
        result_reg <= 0;
        {accum, operand_reg} <= {{WIDTH{1'b0}}, operand_1, 2'b0};
    end else if (sqrt_active) begin
        if (step_count == ((WIDTH + FBITS) >> 1) - 1) begin
            sqrt_active <= 0;
            root_ready <= 1;
            root <= result_next;
        end else begin
            step_count <= step_count + 1;
            operand_reg <= operand_next;
            accum <= accum_next;
            result_reg <= result_next;
            root_ready <= 0;
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