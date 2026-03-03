# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import ClockCycles

from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from obi.transaction import ObiChATrans, ObiChRTrans

class ObiChARequestDriver(BaseDriver):
    async def drive(self, transaction: ObiChATrans):
        self.io.set("addr", transaction.addr)
        self.io.set("wdata", transaction.wdata)
        self.io.set("we", transaction.we)
        self.io.set("be", transaction.be)

        #print(f"transaction: {transaction.we}, addr:{transaction.addr}, wdata:{transaction.wdata}")

        self.io.set("req", 1)
        await RisingEdge(self.clk)
        while self.io.get("gnt") == 0:
            await RisingEdge(self.clk)
        self.io.set("req", 0)
        await RisingEdge(self.clk)

class ObiChRReadyDriver(BaseDriver):
    async def drive(self, transaction: ObiChRTrans):
        self.io.set("rready", transaction.ready)
        await ClockCycles(self.clk, transaction.cycles)




class ObiChRRequestMonitor(BaseMonitor):
    async def monitor(self, capture):
        while True:
            await RisingEdge(self.clk)
            if self.rst.value == 0:
                continue
            if (self.io.get("rvalid") == True and self.io.get("we") == False and self.io.get("rready") == True):
                capture(
                    ObiChRTrans(
                        rdata = self.io.get("rdata"),
                    )
                )

