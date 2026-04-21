from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from cocotb.triggers import RisingEdge, FallingEdge

from base import get_test_runner, WAVES

from random import Random

from obi.io import ObiChAIO, ObiChRIO
from obi.requestor import ObiChARequestDriver, ObiChRRequestMonitor, ObiChRReadyDriver
from obi.transaction import ObiChATrans, ObiChRTrans
from obi.sequences import obi_channel_a_trans, obi_channel_r_trans

from flash_memory.io import FlashMemoryIO

from flash_memory.driver import FlashMemoryRequestDriver, FlashMemoryResponseDriver
from flash_memory.monitor import FlashMemoryRequestMonitor, FlashMemoryResponseMonitor

from flash_memory.transaction import FlashMemoryRequest, FlashMemoryResponse

from flash_memory.model import FlashMemoryModel

from flash_memory.sequences import flash_rsp_trans

TX_DATA_REG_ADDR = 0
RX_DATA_REG_ADDR = 4
SPI_DIV_CLK_REG_ADDR = 8
SS_REG_ADDR = 12
CTRL_REG_ADDR = 16

class FlashImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)

        flash_io = FlashMemoryIO(dut, "spi", IORole.INITIATOR, io_style=io_suffix_style)

        self.register("flash_rsp_drv", FlashMemoryResponseDriver(self, flash_io, self.clk, self.rst))

        self.register("flash_req_monitor", FlashMemoryRequestMonitor(self, flash_io, self.clk, self.rst))

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        self.register("obi_r_drv", ObiChRReadyDriver(self, obi_r_io, self.clk, self.rst))

        # Flash Memory
        self.flash_mem = FlashMemoryModel(self.flash_req_monitor, self.flash_rsp_drv, Random(self.random.random()))

    async def initialise(self) -> None:
        await super().initialise()
        self.flash_mem.reset()

@FlashImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1)
async def flash_cmd(tb: FlashImpTB, log):
    log.info(f"Send single flash CMD over SPI")

    # Schedule random ready driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    spi_div = 0x10
    ss = 0x1
    data = 0x9E

    config = [
        (SPI_DIV_CLK_REG_ADDR, spi_div),
        (TX_DATA_REG_ADDR, data),
        (SS_REG_ADDR, ss),
        (CTRL_REG_ADDR, 0x1),
    ]

    for (address, data) in config:
        obiWrite(tb=tb, addr=address, data=data)
        await RisingEdge(tb.dut.obi_rvalid_o)

    # Set SPI clock divisor
    # obiWrite(tb, addr=SPI_DIV_CLK_REG_ADDR, data=spi_div)
    # await RisingEdge(tb.dut.obi_rvalid_o)

    # Set transfer data
    # obiWrite(tb, addr=TX_DATA_REG_ADDR, data=data)
    # await RisingEdge(tb.dut.obi_rvalid_o)

    # Set slaves
    # obiWrite(tb, addr=SS_REG_ADDR, data=ss)
    # await RisingEdge(tb.dut.obi_rvalid_o)

    # Start SPI write transaction
    # obiWrite(tb, addr=CTRL_REG_ADDR, data=0x1)
    # await RisingEdge(tb.dut.obi_rvalid_o)

    # Wait for SPI transaction to complete
    await RisingEdge(tb.dut.complete_o)

    await RisingEdge(tb.dut.clk_i)

    # Acknowledge SPI done, clear done bit
    obiWrite(tb=tb, addr=CTRL_REG_ADDR, data=0x0)

    #tb.schedule(flash_rsp_trans(flash_rsp_drv=tb.flash_rsp_drv, trans=[FlashMemoryResponse(data=data)]), blocking=False)
    tb.scoreboard.channels["flash_req_monitor"].push_reference(FlashMemoryRequest(cmd=data))

    # Start SPI read transaction
    print(f'Starting SPI Read transaction!')
    obiWrite(tb, addr=CTRL_REG_ADDR, data=0x2)
    
    await RisingEdge(tb.dut.obi_rvalid_o)

    #await tb.flash_mem._response.wait_for(DriverEvent.PRE_DRIVE)
    #await tb.flash_rsp_drv.wait_for(DriverEvent.POST_DRIVE)

    await RisingEdge(tb.dut.complete_o)

    tb.scoreboard.channels["flash_req_monitor"].push_reference(FlashMemoryRequest(cmd=0x20))

    await RisingEdge(tb.dut.clk_i)

    print(f'Acknowledging SPI done')
    # Acknowledge SPI done, clear done bit
    obiWrite(tb=tb, addr=CTRL_REG_ADDR, data=0x0)

    print(f'Unselecting slave')
    # Unselect slave
    obiWrite(tb=tb, addr=SS_REG_ADDR, data=0x0)


def obiWrite(tb, addr, data):
    # Add reference to obi monitor for write acknowledge (write to addr with data)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    trans = [
        ObiChATrans(addr=addr, wdata=data, we=True, be=0x1)
    ]

    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def spiWrite(tb, data, slaves, spi_div):
    # Add reference to obi monitor for write acknowledge (write to ctrl reg to acknowledge SPI done transaction)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    # Add reference to obi monitor for write acknowledge (write to SS reg = 1)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    # Add reference to spi monitor for data we want to send
    #tb.scoreboard.channels["flash_rsp_monitor"].push_reference(FlashMemoryResponse(data=data))

    # tb.scoreboard.channels["flash_req_monitor"].push_reference(FlashMemoryRequest(cmd=data))

    # Add reference to obi monitor for write acknowledge (write data to data reg)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Add reference to obi monitor for write acknowledge (write to ctrl reg to start SPI transaction)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Add reference to obi monitor for write acknowledge (write to SS reg = 0)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Add reference to obi monitor for write acknowledge (write to SPI_DIV_CLK_REG)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    trans = [
        # Set SPI Clock Division Register
        ObiChATrans(addr=SPI_DIV_CLK_REG_ADDR, wdata=spi_div, we=True, be=0x1),
        # Write 0x1 to SS_REG so the first slave is selected
        ObiChATrans(addr=SS_REG_ADDR, wdata=slaves, we=True, be=0x1),
        # Some data we want to send to write to data reg
        ObiChATrans(addr=TX_DATA_REG_ADDR, wdata=data, we=True, be=0x1),
        # Write to ctrl reg to start SPI transaction
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x1, we=True, be=0x1),
    ]

    print(f"Scheduling obi write and start SPI transaction")
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

    # tb.flash_mem.read_id(tb, tb.flash_req_monitor, tb.flash_rsp_drv)

def test_flash_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_flash", waves=WAVES)

if __name__ == "__main__":
    test_flash_runner()
