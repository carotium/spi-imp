# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .requestor import HandshakeRequestMonitor, HandshakeRequestDriver
from .responder import HandshakeResponderDriver
from .transaction import HandshakeReady, HandshakeValid

@forastero.sequence(auto_lock=True)
@forastero.requires("ready_drv", HandshakeResponderDriver)
async def handshake_ready_seq(
    ctx: SeqContext,
    ready_drv: SeqProxy[HandshakeResponderDriver],
    delay_range: tuple[int, int] = (1, 1),
) -> None:
    min_delay, max_delay = min(delay_range), max(delay_range)
    while True:
        await ready_drv.enqueue(
            HandshakeReady(ready=True, delay=ctx.random.randint(min_delay, max_delay)),
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()

@forastero.sequence(auto_lock=True)
@forastero.requires("ready_drv", HandshakeResponderDriver)
async def handshake_independent_ready_seq(
    ctx: SeqContext,
    ready_drv: SeqProxy[HandshakeResponderDriver],
    delay_range: tuple[int, int] = (1, 1),
) -> None:
    min_delay, max_delay = min(delay_range), max(delay_range)
    while True:
        await ready_drv.enqueue(
            HandshakeReady(ready=True, delay=ctx.random.randint(min_delay, max_delay)),
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()

@forastero.sequence(auto_lock=True)
@forastero.requires("input_drv", HandshakeRequestDriver)
async def handshake_rand_data_seq(
    ctx: SeqContext,
    input_drv: SeqProxy[HandshakeRequestDriver],
    length: int = 1,
    delay_range: tuple[int, int] = (0, 0)
) -> None:
    min_delay, max_delay = min(delay_range), max(delay_range)
    for _ in range(length):
        delay = ctx.random.randint(min_delay, max_delay)
        await ClockCycles(ctx.clk, delay)
        await input_drv.enqueue(
            HandshakeValid(data=ctx.random.randint(0, (2**32)-1), valid=True),
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()
