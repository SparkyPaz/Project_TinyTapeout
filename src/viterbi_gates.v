
// Combinational primitives and registers shared by the decoder.
module viterbi_full_adder (
    input wire a, b, carry_in,
    output wire sum, carry_out
);
    wire propagate, generate_carry, propagate_carry;
    xor (propagate, a, b);
    xor (sum, propagate, carry_in);
    and (generate_carry, a, b);
    and (propagate_carry, propagate, carry_in);
    or  (carry_out, generate_carry, propagate_carry);
endmodule

module viterbi_add #(
    parameter WIDTH = 5
) (
    input wire [WIDTH-1:0] a, b,
    output wire [WIDTH-1:0] sum
);
    wire [WIDTH:0] carry;
    assign carry[0] = 1'b0;
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1) begin: bits
            viterbi_full_adder adder (
                .a(a[bit_index]), .b(b[bit_index]),
                .carry_in(carry[bit_index]), .sum(sum[bit_index]),
                .carry_out(carry[bit_index + 1])
            );
        end
    endgenerate
endmodule

// less = (a < b), unsigned.
module viterbi_less #(
    parameter WIDTH = 5
) (
    input wire [WIDTH-1:0] a, b,
    output wire less
);
    wire [WIDTH:0] equal_prefix;
    wire [WIDTH-1:0] equal_bit, not_a, less_term;
    assign equal_prefix[WIDTH] = 1'b1;
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1) begin: bits
            xnor (equal_bit[bit_index], a[bit_index], b[bit_index]);
            and  (equal_prefix[bit_index],
                  equal_prefix[bit_index + 1], equal_bit[bit_index]);
            not  (not_a[bit_index], a[bit_index]);
            and  (less_term[bit_index], equal_prefix[bit_index + 1],
                  not_a[bit_index], b[bit_index]);
        end
    endgenerate
    assign less = |less_term;
endmodule

module viterbi_mux_bit (
    input wire select, zero_value, one_value,
    output wire selected
);
    wire not_select, zero_term, one_term;
    not (not_select, select);
    and (zero_term, not_select, zero_value);
    and (one_term, select, one_value);
    or  (selected, zero_term, one_term);
endmodule

module viterbi_mux #(
    parameter WIDTH = 5
) (
    input wire select,
    input wire [WIDTH-1:0] zero_value, one_value,
    output wire [WIDTH-1:0] selected
);
    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1) begin: bits
            viterbi_mux_bit mux (
                .select(select), .zero_value(zero_value[bit_index]),
                .one_value(one_value[bit_index]), .selected(selected[bit_index])
            );
        end
    endgenerate
endmodule

module viterbi_hamming2 (
    input wire [1:0] received, expected,
    output wire [1:0] distance
);
    wire first_error, second_error;
    xor (first_error, received[1], expected[1]);
    xor (second_error, received[0], expected[0]);
    xor (distance[0], first_error, second_error);
    and (distance[1], first_error, second_error);
endmodule

// Rising-edge register. Synchronous clear has priority over load; without
// load the value is held. CLEAR_VALUE is what clear writes.
module viterbi_register #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] CLEAR_VALUE = {WIDTH{1'b0}}
) (
    input wire clk, clear, load,
    input wire [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    always @(posedge clk) begin
        if (clear) q <= CLEAR_VALUE;
        else if (load) q <= d;
    end
endmodule

// Register without clear, for values always written before they are read.
module viterbi_register_nc #(
    parameter WIDTH = 1
) (
    input wire clk, load,
    input wire [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    always @(posedge clk) begin
        if (load) q <= d;
    end
endmodule
