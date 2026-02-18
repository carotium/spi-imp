# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from cocotb.triggers import RisingEdge
from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from .transaction import ObiChATrans

class ObiChARequestDriver(BaseDriver):
    async def drive(self, transaction: ObiChATrans):
        self.io.set("addr", transaction.addr)
        self.io.set("wdata", transaction.wdata)
        self.io.set("we", transaction.we)
        self.io.set("be", transaction.be)

        self.io.set("req", 1)
        await RisingEdge(self.clk)
        while self.io.get("gnt") == 0:
            await RisingEdge(self.clk)
        self.io.set("req", 0)
