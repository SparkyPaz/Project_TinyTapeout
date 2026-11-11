/*
 * Copyright (c) 2026 SparkyPaz
 * SPDX-License-Identifier: Apache-2.0
 */

`timescale 1ns/1ps
`default_nettype none

// Decodificador Viterbi de decisión dura, R=1/2, K=4, ocho estados y bloques
// de ocho bits. Envuelve el núcleo viterbi8 (ocho entradas I y ocho salidas O)
// adaptándolo al pinout de Tiny Tapeout: clk y rst_n son pines dedicados.
module tt_um_sparkypaz_viterbi (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ui[0]=R1 ui[1]=R2 ui[2]=ENABLE ui[3]=START ui[4]=TEST ui[5]=ERR_IN
  // El núcleo espera I = {ERR_IN, TEST, START, ENABLE, RESET, CLK, R2, R1}.
  viterbi8 decoder (
      .I({ui_in[5], ui_in[4], ui_in[3], ui_in[2], ~rst_n, clk, ui_in[1], ui_in[0]}),
      .O(uo_out)
  );

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:6], uio_in, 1'b0};

endmodule

`default_nettype wire
