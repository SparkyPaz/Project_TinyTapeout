<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Hard-decision Viterbi decoder for a rate 1/2 convolutional code with constraint
length K=4 (8 states), generators G1=1111 and G2=1011 (taps ordered
[X,Q1,Q2,Q3]). Blocks carry 8 information bits, with no tail bits; the encoder
and decoder both start in state 000.

The design has four shared branch-distance units and eight add-compare-select
(ACS) units built from adders, a comparator and multiplexers. Path metrics are
5 bits. Survivor decisions are stored in five rows of eight flip-flops (stages
0 to 2 always choose predecessor 0, so they are not stored), and a traceback
walks them back to recover the message. 106 flip-flops in total, no RAM, ROM or
processor. It is sized to fit a single 1x1 tile.

Operation, one transmitted bit pair per clock edge:

1. Hold `rst_n` low for at least one clock edge, then release it with `ENABLE=1`.
2. Raise `START` for one clock edge (this edge only initialises; no pair is read).
3. Present 8 pairs `R1,R2`, one before each rising edge. The first coded bit is `R1`.
4. The decoder spends 8 cycles on SELECT (a serial search for the best final state, lowest state number wins ties) and 8 on TRACEBACK.
5. Read `DATA` on each rising edge where `VALID=1`, 8 times: `x[0]` first, `x[7]` last.
6. `DONE` is high for one enabled cycle after the last bit; then the decoder returns to idle.

`ERROR` is high when the best path still differs from the received word
(`MET` != 0). `ERROR=1` can come with a correct message (errors corrected);
`ERROR=0` can come with a wrong message if the errors form another valid code word.
`MET[2:0]` is the Hamming distance to the chosen code word (0 to 4 for any input);
`MET3` (`uo[7]`) is always 0. `ERROR` and `MET` read 0 until the search finishes.

`ENABLE=0` freezes everything and silences `VALID`/`DONE`. `START` is ignored
while a block is in progress. With `TEST=1` captured at the `START` edge,
`ERR_IN=1` during a pair flips `R1` of that pair, to inject errors from outside.
The minimum distance of the code for 8-bit blocks without tail is 2, so an error
in the last pair can be ambiguous.

## How to test

Drive `ui[5:0]` as in the table below and sample `uo[7:0]`. Example for the message
10110010: after START send the pairs 11 10 00 10 01 00 00 10 and read the bits back.

| Pin | Name | Use |
|---|---|---|
| ui[0] | R1 | First received bit of the pair |
| ui[1] | R2 | Second received bit of the pair |
| ui[2] | ENABLE | Allows the decoder to advance |
| ui[3] | START | Initialise a new block (idle only) |
| ui[4] | TEST | Allow error injection, captured at START |
| ui[5] | ERR_IN | Flip R1 of the current pair if TEST was captured |
| uo[0] | DATA | Recovered bit |
| uo[1] | VALID | DATA is valid, sample on next rising edge |
| uo[2] | DONE | Block finished |
| uo[3] | ERROR | Final metric is not zero |
| uo[7:4] | MET0..MET3 | Final path metric (MET3 is always 0) |

`ui[6]`, `ui[7]` and all `uio` pins are unused.

The design was also compared against the brute-force oracle on all 65536 possible
received words (message and metric). The cocotb tests in `test/test.py` check all 256 noiseless messages, 300 random
received words against an independent brute-force oracle, one error at each of
the 16 bit positions, error injection, pausing, START during operation and reset.

## External hardware

None. Any microcontroller or switches/LEDs on the demo board can drive the pins.
