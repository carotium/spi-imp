from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from cocotb.triggers import RisingEdge, FallingEdge
from base import get_test_runner, WAVES
from obi.io import ObiChAIO, ObiChRIO
from spi.io import SpiIO
from obi.requestor import ObiChARequestDriver, ObiChRRequestMonitor, ObiChRReadyDriver
from spi.requestor import SpiMonitor
from obi.sequences import obi_channel_a_trans, obi_channel_r_trans
from obi.transaction import ObiChATrans, ObiChRTrans
from spi.transaction import SpiTrans

import random

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        spi_io = SpiIO(dut, "spi", IORole.INITIATOR, io_style=io_suffix_style)

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        self.register("obi_r_drv", ObiChRReadyDriver(self, obi_r_io, self.clk, self.rst))

        #self.register("spi_drv", SpiRequestDriver(self, spi_io, self.clk, self.rst))

        self.register("spi_monitor", SpiMonitor(self, spi_io, self.clk, self.rst))

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1)
async def inbetween_send(tb: SpiImpTB, log):
    log.info(f"A single spi transfer and try to write to data reg during spi transfer")

    spi_transfer(tb, 16)
    for i in range(0, random.randint(1, 8)):
        await RisingEdge(tb.dut.spi_sclk_o)
    trans = [
        ObiChATrans(addr=0x0, wdata=0xA, we=True, be=0x1),
        ObiChATrans(addr=0x1, wdata=0x1, we=True, be=0x1),
    ]
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

@SpiImpTB.testcase( reset_wait_during=2, reset_wait_after=0, timeout=2000, shutdown_delay=1, shutdown_loops=1,)
async def multiple_send(tb: SpiImpTB, log):
    log.info(f"Multiple SPI transfers B2B")

    num_of_tran = 5

    for i in range(0, num_of_tran):
        tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=[ObiChATrans(addr=0x1, wdata=0x0, we=True, be=0x1)]))
        spi_transfer(tb, data=i)
        await RisingEdge(tb.dut.spi_done_o)

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def single_send(tb: SpiImpTB, log):
    log.info(f"Single SPI transaction")
    spi_transfer(tb, data=0x21)

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def obi_write_read(tb: SpiImpTB, log):
    log.info("Three writes and reads for OBI transaction")

    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)
    
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x1))

    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x2))

    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x3))


    obi_transfer(tb, 0x1)
    await RisingEdge(tb.dut.obi_we_i)
    obi_transfer(tb, 0x2)
    await RisingEdge(tb.dut.obi_we_i)
    obi_transfer(tb, 0x3)
    await RisingEdge(tb.dut.obi_we_i)
    
def spi_transfer(tb, data):
    tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=data))

    trans = [
        ObiChATrans(addr=0x0, wdata=data, we=True, be=0x1),
        ObiChATrans(addr=0x1, wdata=0x1, we=True, be=0x1),
    ]

    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def obi_transfer(tb, data):
    #tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)
    trans = [
        # Write data to data reg
        ObiChATrans(addr=0x0, wdata=data, we=True, be=0x1),
        # Read data from data reg
        ObiChATrans(addr=0x0, we=False, be=0x1),
    ]
    #tb.dut.obi_rready_i.value = 1
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
