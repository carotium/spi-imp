# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import ObiChATrans, ObiChRTrans, SpiTransferTrans
from .requestor import ObiChARequestDriver, ObiChRRequestMonitor, SpiRequestDriver

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

@forastero.sequence(auto_lock=True)
@forastero.requires("spi_drv", SpiRequestDriver)
async def spi_trans(
    ctx: SeqContext,
    spi_drv: SeqProxy[SpiRequestDriver],
    trans: list[SpiTransferTrans]
) -> None:
    for tran in trans:
        await spi_drv.enqueue(
            tran,
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()
