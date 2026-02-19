# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import ObiChATrans
from .requestor import ObiChARequestWriteDriver

@forastero.sequence(auto_lock=True)
@forastero.requires("obi_a_drv", ObiChARequestWriteDriver)
async def obi_channel_a_write_trans(
    ctx: SeqContext,
    obi_a_drv: SeqProxy[ObiChARequestWriteDriver],
    address: int,
    data: int,
) -> None:
    await obi_a_drv.enqueue(
        ObiChATrans(addr=address, wdata=data, we=True, be=0b1111),
        wait_for=DriverEvent.POST_DRIVE,
    ).wait()
