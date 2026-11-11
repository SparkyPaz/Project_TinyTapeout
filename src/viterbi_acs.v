`timescale 1ns/1ps

// Add-compare-select for one destination state. Metrics are 5 bits (a valid
// path distance in 8 stages is at most 16). Unreachable states start with a
// larger metric instead of a reachability flag, so no masking is needed.
module viterbi_acs (
    input wire [4:0] metric0, metric1,
    input wire [1:0] branch0, branch1,
    output wire [4:0] new_metric,
    output wire decision
);
    wire [4:0] sum0, sum1;
    viterbi_add add0 (.a(metric0), .b({3'b000, branch0}), .sum(sum0));
    viterbi_add add1 (.a(metric1), .b({3'b000, branch1}), .sum(sum1));
    // Strict comparison: ties keep predecessor 0.
    viterbi_less compare (.a(sum1), .b(sum0), .less(decision));
    viterbi_mux choose_metric (
        .select(decision), .zero_value(sum0), .one_value(sum1),
        .selected(new_metric)
    );
endmodule
