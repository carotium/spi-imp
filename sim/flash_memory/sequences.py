# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

# Common sequences used by testcases in stream
import forastero
from cocotb.triggers import ClockCycles
from forastero.driver import DriverEvent
from forastero.monitor import MonitorEvent
from forastero.sequence import SeqContext, SeqProxy

from .transaction import FlashMemoryResponse
from .driver import FlashMemoryResponseDriver

@forastero.sequence(auto_lock=True)
@forastero.requires("flash_rsp_drv", FlashMemoryResponseDriver)
async def flash_rsp_trans(
    ctx: SeqContext,
    flash_rsp_drv: SeqProxy[FlashMemoryResponseDriver],
    trans: list[FlashMemoryResponse]
) -> None:
    for tran in trans:
        await flash_rsp_drv.enqueue(
            tran,
            wait_for=DriverEvent.POST_DRIVE,
        ).wait()
