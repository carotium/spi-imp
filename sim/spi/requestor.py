from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import ClockCycles

from forastero.driver import BaseDriver
from forastero.monitor import BaseMonitor

from spi.transaction import SpiTrans

#import operator

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

            while(self.io.get("ss") == 0xF):
                index = 7
                spi_data = 0
                captured = 0
                await RisingEdge(self.clk)

            while(self.io.get("ss") < 0xF and index >= 0):
                if(self.io.get("sclk") and captured == 0):
                    spi_data += (int(self.io.get("mosi")) << index)
                    print(f'mosi={self.io.get("mosi")}\n')
                    captured = 1
                    index -= 1
                elif(self.io.get("sclk") == False):
                    captured = 0
                
                await RisingEdge(self.clk)

            while(self.io.get("ss") == 0xF):
                await RisingEdge(self.clk)

            capture(
                SpiTrans(
                    data = spi_data
                )
            )
