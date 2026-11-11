
// Exactly eight binary inputs and eight binary outputs.
// I[0]=R1 I[1]=R2 I[2]=CLK I[3]=RESET I[4]=ENABLE
// I[5]=START I[6]=TEST I[7]=ERR_IN
// O[0]=DATA O[1]=VALID O[2]=DONE O[3]=ERROR O[7:4]=minimum metric.
// Synchronous reset. Sample O[0] on rising I[2] when O[1] was high.
//
// Area notes (rate 1/2, K=4, 8 stages, no tail):
//  - Unreachable states start with metric UNREACHED instead of a flag. They
//    only compete in the first three stages, where any real path is below 8.
//  - In stages 0..2 the only reachable predecessor is the one with D=0, so
//    those decisions are always 0 and are not stored.
//  - The minimum final metric is at most 4 (checked on all 65536 inputs), so
//    only three bits of it reach the pins.
//  - The minimum search is serial (8 cycles, one comparator).
module viterbi8 (
    input wire [7:0] I,
    output wire [7:0] O
);
    localparam [2:0] IDLE=3'd0, RECEIVE=3'd1, SELECT=3'd2,
                     TRACEBACK=3'd3, OUTPUT_BITS=3'd4, DONE=3'd5;
    localparam [4:0] UNREACHED = 5'd8;
    wire clk = I[2];
    wire reset = I[3];
    wire enable = I[4];
    wire [2:0] state, index;
    reg [2:0] next_state, next_index;
    wire initialize = (state == IDLE) && I[5];
    wire receiving = state == RECEIVE;
    wire selecting = state == SELECT;
    wire tracing = state == TRACEBACK;
    wire test_mode;
    wire clear_block = reset || (enable && initialize);

    viterbi_register #(.WIDTH(3)) state_register (
        .clk(clk), .clear(reset), .load(enable), .d(next_state), .q(state)
    );
    // One counter serves every phase: up in RECEIVE, down in TRACEBACK, up in OUTPUT.
    viterbi_register #(.WIDTH(3)) index_counter (
        .clk(clk), .clear(reset), .load(enable), .d(next_index), .q(index)
    );
    viterbi_register #(.WIDTH(1)) test_register (
        .clk(clk), .clear(reset), .load(enable && initialize),
        .d(I[6]), .q(test_mode)
    );

    always @* begin
        next_state = state;
        next_index = index;
        case (state)
            IDLE: begin
                if (I[5]) begin
                    next_state = RECEIVE;
                    next_index = 3'd0;
                end
            end
            RECEIVE: begin
                if (index == 3'd7) begin
                    next_state = SELECT;
                    next_index = 3'd0;
                end else next_index = index + 3'd1;
            end
            SELECT: begin
                if (index == 3'd7) next_state = TRACEBACK;
                else next_index = index + 3'd1;
            end
            TRACEBACK: begin
                if (index == 3'd0) next_state = OUTPUT_BITS;
                else next_index = index - 3'd1;
            end
            OUTPUT_BITS: begin
                if (index == 3'd7) next_state = DONE;
                else next_index = index + 3'd1;
                if (index == 3'd7) next_index = 3'd0;
            end
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Four shared branch distances. R1 is the MSB of each received pair.
    wire [1:0] effective_pair = {I[0] ^ (test_mode & I[7]), I[1]};
    wire [1:0] branch_metric [0:3];
    genvar branch;
    generate
        for (branch = 0; branch < 4; branch = branch + 1) begin: branch_units
            localparam [1:0] EXPECTED = branch;
            viterbi_hamming2 branch_distance (
                .received(effective_pair), .expected(EXPECTED),
                .distance(branch_metric[branch])
            );
        end
    endgenerate

    wire [4:0] metric [0:7];
    wire [4:0] updated_metric [0:7];
    wire [7:0] decisions;
    genvar destination;
    generate
        for (destination = 0; destination < 8; destination = destination + 1) begin: acs_units
            localparam [2:0] DESTINATION = destination;
            localparam integer PREVIOUS0 = (destination & 3) << 1;
            localparam integer PREVIOUS1 = PREVIOUS0 | 1;
            localparam [1:0] EXPECTED0 = {
                DESTINATION[2] ^ DESTINATION[1] ^ DESTINATION[0],
                DESTINATION[2] ^ DESTINATION[0]
            };
            localparam [1:0] EXPECTED1 = EXPECTED0 ^ 2'b11;
            localparam [4:0] INITIAL_METRIC = destination == 0 ? 5'd0 : UNREACHED;
            viterbi_acs acs (
                .metric0(metric[PREVIOUS0]), .metric1(metric[PREVIOUS1]),
                .branch0(branch_metric[EXPECTED0]), .branch1(branch_metric[EXPECTED1]),
                .new_metric(updated_metric[destination]), .decision(decisions[destination])
            );
            viterbi_register #(.WIDTH(5), .CLEAR_VALUE(INITIAL_METRIC)) metric_register (
                .clk(clk), .clear(clear_block), .load(enable && receiving),
                .d(updated_metric[destination]), .q(metric[destination])
            );
        end
    endgenerate

    // Survivor decisions for stages 3..7. Every row is written (once per
    // block) before it is read, so these registers have no reset.
    wire [7:0] survivor [3:7];
    genvar stage;
    generate
        for (stage = 3; stage < 8; stage = stage + 1) begin: survivor_rows
            localparam [2:0] STAGE = stage;
            viterbi_register_nc #(.WIDTH(8)) row_register (
                .clk(clk), .load(enable && receiving && (index == STAGE)),
                .d(decisions), .q(survivor[stage])
            );
        end
    endgenerate

    // Serial minimum search over the final metrics: one state per cycle, in
    // ascending order, using the strict comparison so the smaller state
    // number wins ties. best_metric and traceback_state hold the best so far.
    wire [4:0] best_metric;
    wire [2:0] traceback_state;
    wire [4:0] contender_metric = metric[index];
    wire contender_less;
    viterbi_less compare_best (
        .a(contender_metric), .b(best_metric), .less(contender_less)
    );
    wire take_contender = selecting && (index == 3'd0 || contender_less);

    reg predecessor_decision;
    always @* begin
        case (index)
            3'd3: predecessor_decision = survivor[3][traceback_state];
            3'd4: predecessor_decision = survivor[4][traceback_state];
            3'd5: predecessor_decision = survivor[5][traceback_state];
            3'd6: predecessor_decision = survivor[6][traceback_state];
            3'd7: predecessor_decision = survivor[7][traceback_state];
            default: predecessor_decision = 1'b0;
        endcase
    end
    wire [2:0] previous_traceback_state = {traceback_state[1:0], predecessor_decision};
    viterbi_register #(.WIDTH(5)) best_metric_register (
        .clk(clk), .clear(clear_block), .load(enable && take_contender),
        .d(contender_metric), .q(best_metric)
    );
    viterbi_register_nc #(.WIDTH(3)) traceback_state_register (
        .clk(clk), .load(enable && (take_contender || tracing)),
        .d(selecting ? index : previous_traceback_state),
        .q(traceback_state)
    );

    // Bit x[j] is kept at decoded[7-j]; DATA reads x[0] first.
    wire [7:0] decoded;
    reg [7:0] next_decoded;
    always @* begin
        next_decoded = decoded;
        next_decoded[3'd7 - index] = traceback_state[2];
    end
    viterbi_register_nc #(.WIDTH(8)) decoded_register (
        .clk(clk), .load(enable && tracing), .d(next_decoded), .q(decoded)
    );

    assign O[0] = state == OUTPUT_BITS ? decoded[3'd7 - index] : 1'b0;
    assign O[1] = (state == OUTPUT_BITS) && enable;
    assign O[2] = (state == DONE) && enable;
    // The result is shown once the search is over (not while it is running).
    wire [2:0] final_metric = selecting ? 3'd0 : best_metric[2:0];
    assign O[3] = |final_metric;
    assign O[7:4] = {1'b0, final_metric};
endmodule
