from cocotb.triggers import RisingEdge
from forastero import BaseMonitor

from .transaction import FlashMemoryRequest, FlashMemoryResponse

READ_ID = 0x9E

class FlashMemoryRequestMonitor(BaseMonitor):
    async def monitor(self, capture) -> None:
        index = 7
        spi_command = 0
        captured = 0
        while True:
            # wait for reset to deassert
            await RisingEdge(self.clk)
            if(self.rst.value == 0):
                await RisingEdge(self.clk)

            while(self.io.get("ss") == 0xF):
                index = 7
                spi_command = 0
                captured = 0
                await RisingEdge(self.clk)

            while(self.io.get("ss") < 0xF and index >= 0):
                if(self.io.get("sclk") and captured == 0):
                    spi_command += (int(self.io.get("mosi")) << index)
                    #print(f'mosi={index}){self.io.get("mosi")}\n')
                    captured = 1
                    index -= 1
                elif(self.io.get("sclk") == False):
                    captured = 0
                
                await RisingEdge(self.clk)

            while(self.io.get("ss") < 0xF):
                await RisingEdge(self.clk)

            capture(FlashMemoryRequest(cmd=spi_command))



class FlashMemoryResponseMonitor(BaseMonitor):
    async def monitor(self, capture) -> None:
        index = 7
        spi_data = 0
        captured = 0
        while True:
            # wait for reset to deassert
            await RisingEdge(self.clk)
            if(self.rst.value == 0):
                await RisingEdge(self.clk)

            while(self.io.get("ss") == 0xF):
                index = 7
                spi_data = 0
                captured = 0
                await RisingEdge(self.clk)

            while(self.io.get("ss") < 0xF and index >= 0):
                if(self.io.get("sclk") and captured == 0):
                    spi_data += (int(self.io.get("mosi")) << index)
                    #print(f'mosi={index}){self.io.get("mosi")}\n')
                    captured = 1
                    index -= 1
                elif(self.io.get("sclk") == False):
                    captured = 0
                
                await RisingEdge(self.clk)

            while(self.io.get("ss") < 0xF):
                await RisingEdge(self.clk)

            capture(FlashMemoryResponse(data=spi_data))
