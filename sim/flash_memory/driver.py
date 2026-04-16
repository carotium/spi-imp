from cocotb.triggers import RisingEdge
from forastero import BaseDriver

from .transaction import FlashMemoryRequest, FlashMemoryResponse


class FlashMemoryRequestDriver(BaseDriver):

    async def drive(self, obj: FlashMemoryRequest) -> None:
        index = 0
        spi_data = obj.data
        sent = 0
        while index <= 7:
            while (self.rst == 0):
                await RisingEdge(self.clk)

            while (self.io.get("sclk") == 0 and sent == 0):
                sent = 1
                self.io.set("miso", ((spi_data>>index)%2))
                await RisingEdge(self.clk)

            if(self.io.get("sclk") and sent == 1):
                #self.io.set("miso", ((spi_data>>index)%2))
                #print(f'idx:{index}, misoexpected:{(spi_data>>index)%2}, misoreally:{self.io.get("miso")}')
                index += 1
                sent = 0

            await RisingEdge(self.clk)

class FlashMemoryResponseDriver(BaseDriver):
    async def drive(self, obj: FlashMemoryResponse) -> None:
        bytes = obj.bytes
        index = 0
        spi_data = obj.data
        sent = 0
        while index <= (bytes*8 - 1):
            while (self.rst == 0):
                await RisingEdge(self.clk)

            while (self.io.get("sclk") == 0 and sent == 0):
                sent = 1
                self.io.set("miso", ((spi_data>>index)%2))
                await RisingEdge(self.clk)

            if(self.io.get("sclk") and sent == 1):
                #self.io.set("miso", ((spi_data>>index)%2))
                #print(f'idx:{index}, misoexpected:{(spi_data>>index)%2}, misoreally:{self.io.get("miso")}')
                index += 1
                sent = 0

            await RisingEdge(self.clk)
