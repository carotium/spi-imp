# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import ClockCycles

from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from .transaction import ObiChATrans, ObiChRTrans, SpiTrans

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

class SpiRequestDriver(BaseDriver):
    async def drive(self, transaction: SpiTrans):
        binary_str = format(transaction.data, '>08b')

        while self.io.get("ss") == True:
            await FallingEdge(self.clk)
        for bit in binary_str:
            assert self.io.get("ss") == 0, "Slave select must not be deasserted during operation!"
            while self.io.get("sclk") != 1:
                await RisingEdge(self.clk)
            self.io.set("mosi", int(bit))
            while self.io.get("sclk") != 0:
                await RisingEdge(self.clk)
        self.io.set("mosi", 0)


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

class SpiMonitor(BaseMonitor):
    async def monitor(self, capture):
        index = 7
        spi_data = 0
        captured = 0
        while True:
            # wait for reset to deassert
            await RisingEdge(self.clk)
            if(self.rst.value == 0):
                index = 7
                spi_data = 0
                captured = 0
                await RisingEdge(self.clk)

            while(self.io.get("ss") == True):
                index = 7
                spi_data = 0
                captured = 0
                await RisingEdge(self.clk)

            while(self.io.get("ss") == False and index >= 0):
                if(self.io.get("sclk") == True and captured == 0):
                    print(f"{index})mosi={int(self.io.get("mosi"))}")
                    spi_data += (int(self.io.get("mosi")) * 2 ** index)
                    captured = 1
                    index -= 1
                elif(self.io.get("sclk") == False):
                    captured = 0
                
                await RisingEdge(self.clk)

            while(self.io.get("ss") == False):
                await RisingEdge(self.clk)

            capture(
                SpiTrans(
                    data = spi_data
                )
            )
