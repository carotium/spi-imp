from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from base import get_test_runner, WAVES
from handshake.io import ObiChAIO, ObiChRIO, SpiIO
from handshake.requestor import ObiChARequestDriver, ObiChRRequestMonitor, SpiMonitor
from handshake.sequences import obi_channel_a_trans
from handshake.transaction import ObiChATrans, ObiChRTrans, SpiTrans

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        spi_io = SpiIO(dut, "spi", IORole.INITIATOR, io_style=io_suffix_style)

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        #self.register("spi_drv", SpiRequestDriver(self, spi_io, self.clk, self.rst))

        self.register("spi_monitor", SpiMonitor(self, spi_io, self.clk, self.rst))


@SpiImpTB.testcase(
    reset_wait_during=2,
    reset_wait_after=0,
    timeout=1000,
    shutdown_delay=1,
    shutdown_loops=1,
)
async def random_traffic(tb: SpiImpTB, log):
    log.info(f"Some traffic")

    # Write to data reg and read from it
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=87))

    # Read from spi MISO, we expect same data we pushed in data reg
    tb.scoreboard.channels["spi_monitor"].push_reference(SpiTrans(data=0x21))

    trans = [
        # Write 87 to data_reg
        ObiChATrans(addr=0x0000, wdata=87, we=True, be=0x1),
        # Read from data_reg
        ObiChATrans(addr=0x0000, we=False, be=0x1),

        # Write some spi data to send to data_reg
        ObiChATrans(addr=0x0000, wdata=0x21, we=True, be=0x1),
        # Write to control reg to start spi transaction
        ObiChATrans(addr=0x0001, wdata=0x1, we=True, be=0x1),
    ]

    # First write to data_reg and read from it. Then write to data_reg
    # data we want to send over SPI, then run SPI transfer.
    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))

def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
