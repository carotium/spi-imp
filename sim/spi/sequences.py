# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import SpiTrans
from .requestor import SpiMisoDriver

@forastero.sequence(auto_lock=True)
@forastero.requires("spi_miso_drv", SpiMisoDriver)
async def spi_miso_trans(
    ctx: SeqContext,
    spi_miso_drv: SeqProxy[SpiMisoDriver],
    data: int
) -> None:
    while True:
        await spi_miso_drv.enqueue(
            SpiTrans(
                data = data,
            ),
            wait_for=DriverEvent.POST_DRIVE
        ).wait()
