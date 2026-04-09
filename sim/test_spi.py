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

TX_DATA_REG_ADDR = 0
RX_DATA_REG_ADDR = 4
SPI_DIV_CLK_REG_ADDR = 8
SS_REG_ADDR = 12
CTRL_REG_ADDR = 16

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        spi_io = SpiIO(dut, "spi", IORole.INITIATOR, io_style=io_suffix_style)

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        self.register("obi_r_drv", ObiChRReadyDriver(self, obi_r_io, self.clk, self.rst))

        self.register("spi_monitor", SpiMonitor(self, spi_io, self.clk, self.rst))

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1)
async def inbetween_send(tb: SpiImpTB, log):
    log.info(f"A single spi transfer and try to write to data reg during spi transfer")
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    spi_transfer(tb, 16, slaves=0x1)

    await RisingEdge(tb.dut.spi_sclk_counter_en)

    for i in range(0, random.randint(1, 8)):
        await RisingEdge(tb.dut.spi_sclk_o)
    trans = [
        ObiChATrans(addr=TX_DATA_REG_ADDR, wdata=0xA, we=True, be=0x1),
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x1, we=True, be=0x1),
    ]
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

    await RisingEdge(tb.dut.complete_o)
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=[ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x0, we=True, be=0x1)]))
    await FallingEdge(tb.dut.complete_o)
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=[ObiChATrans(addr=SS_REG_ADDR, wdata=0x0, we=True, be=0x1)]))

    # Push reference for write acknowledge on OBI
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Push reference to obi monitor for write acknowledge to SS reg
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

@SpiImpTB.testcase( reset_wait_during=2, reset_wait_after=0, timeout=2000, shutdown_delay=1, shutdown_loops=1,)
async def multiple_send(tb: SpiImpTB, log):
    log.info(f"Multiple SPI transfers B2B")
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    num_of_tran = 5

    for i in range(0, num_of_tran):

        spi_transfer(tb, data=i, slaves=0x1)

        await RisingEdge(tb.dut.spi_sclk_counter_en)

        await RisingEdge(tb.dut.complete_o)
        print("Awaited ctrl_complete_bit")

        tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=[ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x0, we=True, be=0x1)]))
        await FallingEdge(tb.dut.complete_o)
        tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=[ObiChATrans(addr=SS_REG_ADDR, wdata=0x0, we=True, be=0x1)]))
        await RisingEdge(tb.dut.clk_i)

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def single_send(tb: SpiImpTB, log):
    log.info(f"Single SPI transaction")
    slaves = 0x1
    # Schedule random ready driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)
    # Start SPI transaction with data (see more in spi_transfer function)
    spi_transfer(tb, data=0xFE, slaves=slaves)

    await RisingEdge(tb.dut.spi_sclk_counter_en)

    # Wait for SPI transaction to complete
    await RisingEdge(tb.dut.complete_o)

    trans = [
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x0, we=True, be=0x1),
        ObiChATrans(addr=SS_REG_ADDR, wdata=0x0, we=True, be=0x1),
    ]
    print("Scheduling write to ctrl reg to acknowledge SPI done transaction")
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def obi_write_read(tb: SpiImpTB, log):
    log.info("Three writes and reads for OBI transaction")

    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)
    
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x1))

    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x2))

    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x3))


    obi_transfer(tb, 0x1)
    await RisingEdge(tb.dut.obi_awe_i)
    obi_transfer(tb, 0x2)
    await RisingEdge(tb.dut.obi_awe_i)
    obi_transfer(tb, 0x3)
    await RisingEdge(tb.dut.obi_awe_i)
    
@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def spi_write_read(tb: SpiImpTB, log):
    log.info("Write and read on SPI")

    # Ready backpressure driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    tb.dut.spi_miso_i.value = 1
    
    spi_transfer(tb, data=0x0, slaves=0x1)
    # Probably schedule MISO driver

    await RisingEdge(tb.dut.spi_sclk_counter_en)

    await RisingEdge(tb.dut.complete_o)
    #await FallingEdge(tb.dut.spi_sclk_o)

    trans = [
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x0, we=True, be=0x1),
        ObiChATrans(addr=SS_REG_ADDR, wdata=0x0, we=True, be=0x1),
    ]

    print("Scheduling write to ctrl reg to acknowledge SPI done transaction")
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

@SpiImpTB.testcase(reset_wait_during=2, reset_wait_after=0, timeout=1000, shutdown_delay=1, shutdown_loops=1,)
async def spi_flash_command(tb: SpiImpTB, log):
    log.info("Send some commands to FLASH using SPI")

    tb.dut.spi_miso_i.value = 1

    # Ready backpressure driver
    tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)

    spi_transfer(tb, data=0x99, slaves=0x1)

    await RisingEdge(tb.dut.spi_sclk_counter_en)

    await RisingEdge(tb.dut.complete_o)

    trans = [
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x0, we=True, be=0x1),
        ObiChATrans(addr=SS_REG_ADDR, wdata=0x0, we=True, be=0x1),
    ]
    print("Scheduling write to ctrl reg to acknowledge SPI done transaction")
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def spi_transfer(tb, data, slaves):
    # Add reference to obi monitor for write acknowledge (write to ctrl reg to acknowledge SPI done transaction)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    # Add reference to obi monitor for write acknowledge (write to SS reg = 1)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    # Add reference to spi monitor for data we want to send
    tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=data))

    # Add reference to obi monitor for write acknowledge (write data to data reg)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Add reference to obi monitor for write acknowledge (write to ctrl reg to start SPI transaction)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))
    # Add reference to obi monitor for write acknowledge (write to SS reg = 0)
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=0x0))

    trans = [
        # Write 0x1 to SS_REG so the first slave is selected
        ObiChATrans(addr=SS_REG_ADDR, wdata=slaves, we=True, be=0x1),
        # Some data we want to send to write to data reg
        ObiChATrans(addr=TX_DATA_REG_ADDR, wdata=data, we=True, be=0x1),
        # Write to ctrl reg to start SPI transaction
        ObiChATrans(addr=CTRL_REG_ADDR, wdata=0x1, we=True, be=0x1),
    ]

    print(f"Scheduling obi write and start SPI transaction")
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def obi_transfer(tb, data):
    #tb.schedule(obi_channel_r_trans(obi_r_drv=tb.obi_r_drv), blocking=False)
    trans = [
        # Write data to data reg
        ObiChATrans(addr=TX_DATA_REG_ADDR, wdata=data, we=True, be=0x1),
        # Read data from data reg
        ObiChATrans(addr=TX_DATA_REG_ADDR, we=False, be=0x1),
    ]
    #tb.dut.obi_rready_i.value = 1
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
