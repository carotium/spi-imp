# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import ObiChATrans
from .requestor import ObiChARequestDriver

@forastero.sequence(auto_lock=True)
@forastero.requires("obi_a_drv", ObiChARequestDriver)
async def obi_channel_a_write_trans(
    ctx: SeqContext,
    obi_a_drv: SeqProxy[ObiChARequestDriver],
    address: int,
    data: int,
) -> None:
    await obi_a_drv.enqueue(
        ObiChATrans(addr=address, wdata=data, we=True, be=0b1111),
        wait_for=DriverEvent.POST_DRIVE,
    ).wait()
