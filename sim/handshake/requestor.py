# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from cocotb.triggers import RisingEdge
from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from .transaction import ObiChATrans, ObiChRTrans, SpiTransferTrans

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

class SpiRequestDriver(BaseDriver):
    async def drive(self, transaction: SpiTransferTrans):
        self.io.set("ss", transaction.ss)
        self.io.set("sclk", transaction.sclk)
        self.io.set("mosi", transaction.mosi)
        #self.io.set("miso", transaction.miso)

        self.io.set("miso", True)
        while self.io.get("ss") == True:
            await RisingEdge(self.clk)
        await RisingEdge(self.clk)


class ObiChRRequestMonitor(BaseMonitor):
    async def monitor(self, capture):
        while True:
            await RisingEdge(self.clk)
            if self.rst.value == 0:
                continue
            if (self.io.get("rvalid") == True and self.io.get("we") == False):
                capture(
                    ObiChRTrans(
                        rdata = self.io.get("rdata"),
                    )
                )
