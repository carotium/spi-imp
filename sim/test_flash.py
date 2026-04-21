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

from spi.io import SpiIO

from spi.requestor import SpiMisoDriver, SpiMonitor

from spi.transaction import SpiTrans

from flash_memory.model import FlashMemoryModel

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

        spi_io = SpiIO(dut, "spi", IORole.INITIATOR, io_style=io_suffix_style)
        
        self.register("spi_monitor", SpiMonitor(self, spi_io, self.clk, self.rst))

        self.register("spi_miso_drv", SpiMisoDriver(self, spi_io, self.clk, self.rst))

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        self.register("obi_r_drv", ObiChRReadyDriver(self, obi_r_io, self.clk, self.rst))

        # Flash Memory
        self.flash_mem = FlashMemoryModel(self.spi_monitor, self.spi_miso_drv, Random(self.random.random()))

    async def initialise(self) -> None:
        await super().initialise()
        self.flash_mem.reset()

@FlashImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=5000, shutdown_delay=1, shutdown_loops=1)
async def read(tb: FlashImpTB, log):
    log.info(f'Send READ command over SPI to Flash')

    # Schedule random ready driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    spi_div = 0x10
    ss = 0x1
    cmd = 0x03

    config = [
        (SPI_DIV_CLK_REG_ADDR, spi_div),    # Set SPI clock divisor
        (TX_DATA_REG_ADDR, cmd),           # Set transfer data
        (SS_REG_ADDR, ss),                  # Set slaves
        (CTRL_REG_ADDR, 0x1),               # Start SPI write transaction
    ]

    for (address, data) in config:
        obiWrite(tb=tb, addr=address, data=data)
        await RisingEdge(tb.dut.obi_rvalid_o)

    await RisingEdge(tb.dut.complete_o)

    # Reference for sent command to Flash
    tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=cmd))

    for i in range(10):
        # Write to transfer data our chosen address
        obiWrite(tb, addr=TX_DATA_REG_ADDR, data=0x0)
        await RisingEdge(tb.dut.obi_rvalid_o)

        # Start SPI read transaction
        obiWrite(tb, addr=CTRL_REG_ADDR, data=0x1)
        await RisingEdge(tb.dut.complete_o)

        # Acknowledge SPI done, clear done bit
        obiWrite(tb=tb, addr=CTRL_REG_ADDR, data=0x0)
        await RisingEdge(tb.dut.obi_rvalid_o)

        # Read from RX data register
        obiRead(tb=tb, addr=RX_DATA_REG_ADDR)
        await RisingEdge(tb.dut.obi_rvalid_o)
        tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
        # Reference for outgoing data on MOSI to be 0x0, because we are receiving on MISO
        tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=0x0))

    # Unselect slave
    obiWrite(tb=tb, addr=SS_REG_ADDR, data=0x0)
    await RisingEdge(tb.dut.obi_rvalid_o)


@FlashImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=2000, shutdown_delay=1, shutdown_loops=1)
async def read_id(tb: FlashImpTB, log):
    log.info(f"Send READ_ID command over SPI to Flash")

    # Schedule random ready driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    spi_div = 0x10
    ss = 0x1
    cmd = 0x9E

    config = [
        (SPI_DIV_CLK_REG_ADDR, spi_div),    # Set SPI clock divisor
        (TX_DATA_REG_ADDR, cmd),           # Set transfer data
        (SS_REG_ADDR, ss),                  # Set slaves
        (CTRL_REG_ADDR, 0x1),               # Start SPI write transaction
    ]

    for (address, data) in config:
        obiWrite(tb=tb, addr=address, data=data)
        await RisingEdge(tb.dut.obi_rvalid_o)

    # Wait for SPI transaction to complete
    await RisingEdge(tb.dut.complete_o)

    # Acknowledge SPI done, clear done bit
    obiWrite(tb=tb, addr=CTRL_REG_ADDR, data=0x0)
    await RisingEdge(tb.dut.obi_rvalid_o)

# START
    # Reference for sent command to Flash
    tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=cmd))

    read_id_data = [
        0x20,
        0xBA,
        0x19,
        0x10,
    ]

    for i in range(4):
        # Start SPI read transaction
        obiWrite(tb, addr=CTRL_REG_ADDR, data=0x2)
        await RisingEdge(tb.dut.complete_o)

        # Acknowledge SPI done, clear done bit
        obiWrite(tb=tb, addr=CTRL_REG_ADDR, data=0x0)
        await RisingEdge(tb.dut.obi_rvalid_o)

        # Read from RX data register
        obiRead(tb=tb, addr=RX_DATA_REG_ADDR)
        await RisingEdge(tb.dut.obi_rvalid_o)
        tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=read_id_data[i]))
        # Reference for outgoing data on MOSI to be 0x0, because we are receiving on MISO
        tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=0x0))

    # Unselect slave
    obiWrite(tb=tb, addr=SS_REG_ADDR, data=0x0)
    await RisingEdge(tb.dut.obi_rvalid_o)

def obiRead(tb, addr):
    trans = [
        ObiChATrans(addr=addr, wdata=addr, we=False, be=0x1)
    ]

    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def obiWrite(tb, addr, data):
    # Add reference to obi monitor for write acknowledge (write to addr with data)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    trans = [
        ObiChATrans(addr=addr, wdata=data, we=True, be=0x1)
    ]

    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def test_flash_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_flash", waves=WAVES)

if __name__ == "__main__":
    test_flash_runner()
