# SPDX-FileCopyrightText: © 2026 SparkyPaz
# SPDX-License-Identifier: Apache-2.0

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

# ui_in: [0]=R1 [1]=R2 [2]=ENABLE [3]=START [4]=TEST [5]=ERR_IN
# uo_out: [0]=DATA [1]=VALID [2]=DONE [3]=ERROR [7:4]=MET[3:0]
R1, R2, ENABLE, START, TEST, ERR_IN = 1, 2, 4, 8, 16, 32


def encode(msg):
    """Mensaje x[0..7] -> pares (Y1,Y2). G1=1111, G2=1011, estado inicial 000."""
    x = lambda t: msg[t] if t >= 0 else 0
    return [
        (x(t) ^ x(t - 1) ^ x(t - 2) ^ x(t - 3), x(t) ^ x(t - 2) ^ x(t - 3))
        for t in range(8)
    ]


def distance(a, b):
    return sum((p[0] ^ q[0]) + (p[1] ^ q[1]) for p, q in zip(a, b))


def reference(rx):
    """Oráculo: enumera los 256 mensajes. Empates: menor (x7,x6,...,x0)."""
    best = None
    for n in range(256):
        msg = [(n >> t) & 1 for t in range(8)]
        key = (distance(encode(msg), rx), msg[::-1])
        if best is None or key < best[0]:
            best = (key, msg)
    return best[1], best[0][0]


def bits(n):
    return [(n >> t) & 1 for t in range(8)]


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)


async def decode(dut, rx, err_mask=0, test=0, pause_at=None):
    """Una transmisión completa. Devuelve (mensaje, métrica, ERROR, ciclos)."""
    base = ENABLE | (TEST if test else 0)
    dut.ui_in.value = base | START
    await FallingEdge(dut.clk)  # el flanco intermedio acepta START
    for t, (a, b) in enumerate(rx):
        err = ERR_IN if (err_mask >> t) & 1 else 0
        dut.ui_in.value = base | (R1 if a else 0) | (R2 if b else 0) | err
        await FallingEdge(dut.clk)
    dut.ui_in.value = base

    data, met, error = [], 0, 0
    for cycle in range(60):
        out = int(dut.uo_out.value)
        if out & 2:  # VALID
            data.append(out & 1)
            if pause_at == len(data):
                data.pop()  # el bit no se consume: se vuelve a presentar al reanudar
                dut.ui_in.value = base & ~ENABLE
                await ClockCycles(dut.clk, 3)
                assert int(dut.uo_out.value) & 2 == 0, "VALID debe callar con ENABLE=0"
                assert int(dut.uo_out.value) & 1 == out & 1, "DATA se mantiene en pausa"
                dut.ui_in.value = base
                pause_at = None
        if out & 4:  # DONE
            met, error = out >> 4, (out >> 3) & 1
            await FallingEdge(dut.clk)
            return data, met, error, cycle
        await FallingEdge(dut.clk)
    raise AssertionError("DONE no apareció")


@cocotb.test()
async def test_reset_and_idle(dut):
    await reset(dut)
    assert int(dut.uo_out.value) == 0, "tras RESET todas las salidas deben ser 0"
    assert int(dut.uio_oe.value) == 0 and int(dut.uio_out.value) == 0


@cocotb.test()
async def test_noiseless_all_messages(dut):
    """Los 256 mensajes sin ruido: recupera el mensaje y la métrica es 0."""
    await reset(dut)
    for n in range(256):
        msg = bits(n)
        data, met, error, _ = await decode(dut, encode(msg))
        assert data == msg, f"mensaje {n:08b}: {data} != {msg}"
        assert met == 0 and error == 0


@cocotb.test()
async def test_random_noise_vs_oracle(dut):
    """Recepciones aleatorias contra el oráculo (mensaje y métrica mínima)."""
    await reset(dut)
    rnd = random.Random(1)
    for _ in range(300):
        rx = [(rnd.getrandbits(1), rnd.getrandbits(1)) for _ in range(8)]
        want, wmet = reference(rx)
        data, met, error, _ = await decode(dut, rx)
        assert data == want, f"rx={rx}: {data} != {want}"
        assert met == wmet and error == (wmet != 0)


@cocotb.test()
async def test_single_error_each_position(dut):
    """Un error en cada uno de los 16 bits de una trama."""
    await reset(dut)
    msg = [1, 0, 1, 1, 0, 0, 1, 0]
    clean = encode(msg)
    for pos in range(16):
        rx = [list(p) for p in clean]
        rx[pos // 2][pos % 2] ^= 1
        rx = [tuple(p) for p in rx]
        want, wmet = reference(rx)
        data, met, _, _ = await decode(dut, rx)
        assert data == want and met == wmet, f"pos {pos}"
        if pos < 14:  # el último par puede ser ambiguo (sin bits de cola)
            assert data == msg, f"pos {pos} debería corregirse"


@cocotb.test()
async def test_err_in_injection(dut):
    """TEST=1 + ERR_IN invierte R1 de esa etapa; con TEST=0 no hace nada."""
    await reset(dut)
    msg = [0, 1, 1, 0, 1, 0, 0, 1]
    clean = encode(msg)
    data, met, _, _ = await decode(dut, clean, err_mask=0b00000100, test=1)
    rx = list(clean)
    rx[2] = (rx[2][0] ^ 1, rx[2][1])
    want, wmet = reference(rx)
    assert data == want == msg and met == wmet == 1
    data, met, error, _ = await decode(dut, clean, err_mask=0b00000100, test=0)
    assert data == msg and met == 0 and error == 0


@cocotb.test()
async def test_enable_pause_and_start_ignored(dut):
    await reset(dut)
    msg = [1, 1, 0, 1, 0, 1, 1, 0]
    data, met, _, _ = await decode(dut, encode(msg), pause_at=3)
    assert data == msg and met == 0
    # START durante una operación se ignora: se decodifica igual
    base = ENABLE
    dut.ui_in.value = base | START
    await FallingEdge(dut.clk)
    for a, b in encode(msg):
        dut.ui_in.value = base | START | (R1 if a else 0) | (R2 if b else 0)
        await FallingEdge(dut.clk)
    dut.ui_in.value = base
    out = []
    for _ in range(40):
        o = int(dut.uo_out.value)
        if o & 2:
            out.append(o & 1)
        if o & 4:
            break
        await FallingEdge(dut.clk)
    assert out == msg


@cocotb.test()
async def test_reset_mid_operation(dut):
    await reset(dut)
    dut.ui_in.value = ENABLE | START
    await ClockCycles(dut.clk, 6)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    await FallingEdge(dut.clk)
    assert int(dut.uo_out.value) == 0
    msg = [0, 0, 1, 0, 1, 1, 0, 1]
    data, met, _, _ = await decode(dut, encode(msg))
    assert data == msg and met == 0
