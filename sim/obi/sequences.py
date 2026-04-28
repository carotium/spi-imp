# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import ObiChATrans, ObiChRTrans, ObiChRBackpressureTrans
from .requestor import ObiChARequestDriver, ObiChRReadyDriver

@forastero.sequence(auto_lock=True)
@forastero.requires("obi_a_drv", ObiChARequestDriver)
async def obi_channel_a_trans(
    ctx: SeqContext,
    obi_a_drv: SeqProxy[ObiChARequestDriver],
    trans: list[ObiChATrans]
) -> None:
    for tran in trans:
        await obi_a_drv.enqueue(
            tran,
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()

@forastero.sequence()
@forastero.requires("obi_r_drv", ObiChRReadyDriver)
async def obi_channel_r_trans(
    ctx: SeqContext,
    obi_r_drv: SeqProxy[ObiChRReadyDriver],
) -> None:
    while True:
        async with ctx.lock(obi_r_drv):
            await obi_r_drv.enqueue(
                ObiChRBackpressureTrans(
                    ready = ctx.random.choice((True, False)),
                    cycles = ctx.random.randint(1, 10),
                ),
                wait_for=DriverEvent.PRE_DRIVE
            ).wait()
