# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import ClockCycles

from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from obi.transaction import ObiChATrans, ObiChRTrans, ObiChRBackpressureTrans

class ObiChARequestDriver(BaseDriver):
    async def drive(self, transaction: ObiChATrans):
        self.io.set("aaddr", transaction.addr)
        self.io.set("awdata", transaction.wdata)
        self.io.set("awe", transaction.we)
        self.io.set("abe", transaction.be)

        #print(f"transaction: {transaction.we}, addr:{transaction.addr}, wdata:{transaction.wdata}")

        self.io.set("areq", 1)
        await RisingEdge(self.clk)
        while self.io.get("agnt") == 0:
            await RisingEdge(self.clk)
        self.io.set("areq", 0)
        await RisingEdge(self.clk)

class ObiChRReadyDriver(BaseDriver):
    async def drive(self, transaction: ObiChRBackpressureTrans):
        #print(f"ready={transaction.ready}, cycles={transaction.cycles}")
        self.io.set("rready", transaction.ready)
        await ClockCycles(self.clk, transaction.cycles)

class ObiChRRequestMonitor(BaseMonitor):
    async def monitor(self, capture):
        while True:
            await RisingEdge(self.clk)
            if self.rst.value == 0:
                continue
            if (self.io.get("rvalid") and self.io.get("rready")):
                capture(
                    ObiChRTrans(
                        
                        rdata = self.io.get("rdata"),
                    )
                )
