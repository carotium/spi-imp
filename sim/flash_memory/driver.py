from cocotb.triggers import RisingEdge
from forastero import BaseDriver

from .transaction import FlashMemoryResponse
from spi.transaction import SpiTrans

class FlashMemoryResponseDriver(BaseDriver):
    async def drive(self, obj: SpiTrans) -> None:
        bytes = obj.bytes
        index = bytes*8 - 1
        spi_data = obj.data
        sent = 0

        print(f'Sending {spi_data} on SPI')

        while index >= 0:
            while (self.rst == 0):
                await RisingEdge(self.clk)

            while self.io.get("ss") == 0xF:
                print(f'waiting for ss to deassert')
                await RisingEdge(self.clk)

            while (self.io.get("sclk") == 0 and sent == 0):
                sent = 1
                self.io.set("miso", ((spi_data>>index)%2))
                print(f'driver:idx:{index}, miso:{self.io.get("miso")}')
                await RisingEdge(self.clk)

            if(self.io.get("sclk") and sent == 1):
                #self.io.set("miso", ((spi_data>>index)%2))
                print(f'driver:idx:{index}, misoexpected:{(spi_data>>index)%2}, misoreally:{self.io.get("miso")}')
                index -= 1
                sent = 0

            await RisingEdge(self.clk)
