from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import ClockCycles

from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from spi.transaction import SpiTrans

class SpiMonitor(BaseMonitor):
    async def monitor(self, capture) -> None:
        while True:
            spi_command = 0
            while((self.rst.value == 0) or (self.io.get("ss") == 0xF)):
                await RisingEdge(self.clk)

            for index in reversed(range(8)):
                await RisingEdge(self.io.dut.spi_sclk_o)
                spi_command += (int(self.io.get("mosi")) << index)
                assert self.io.get("ss") != 0xF, "ERROR: SS raised during transaction."

            print(f'Captured SPI transaction')
            capture(SpiTrans(data=spi_command))

class SpiMisoDriver(BaseDriver):
    async def drive(self, obj: SpiTrans) -> None:
        # bytes = obj.bytes
        bytes = 1
        index = bytes*8 - 1
        spi_data = obj.data
        sent = 0

        #print(f'Sending {spi_data} on SPI')

        while index >= 0:
            while (self.rst == 0):
                await RisingEdge(self.clk)

            while self.io.get("ss") == 0xF:
                # print(f'waiting for ss to deassert')
                await RisingEdge(self.clk)

            while (self.io.get("sclk") == 0 and sent == 0):
                sent = 1
                self.io.set("miso", ((spi_data>>index)%2))
                # print(f'driver:idx:{index}, miso:{self.io.get("miso")}')
                await RisingEdge(self.clk)

            if(self.io.get("sclk") and sent == 1):
                #self.io.set("miso", ((spi_data>>index)%2))
                # print(f'driver:idx:{index}, misoexpected:{(spi_data>>index)%2}, misoreally:{self.io.get("miso")}')
                index -= 1
                sent = 0

            await RisingEdge(self.clk)
