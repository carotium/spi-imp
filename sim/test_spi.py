from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from base import get_test_runner, WAVES
from handshake.io import ObiChAIO, ObiChRIO
from handshake.requestor import ObiChARequestDriver
from handshake.sequences import obi_channel_a_write_trans

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        # Register callback on input driver to push reference to monitor
        #self.input_driver.subscribe(DriverEvent.ENQUEUE, self.push_reference)

@SpiImpTB.testcase(
    reset_wait_during=2,
    reset_wait_after=0,
    timeout=1000,
    shutdown_delay=1,
    shutdown_loops=1,
)
async def random_raffic(tb: SpiImpTB, log):
    log.info(f"Scheduling random traffic to the SPI input.")
    tb.schedule(obi_channel_a_write_trans(obi_a_drv=tb.obi_a_drv, address=0x0010, data=123))
    tb.schedule(obi_channel_a_write_trans(obi_a_drv=tb.obi_a_drv, address=0x0100, data=456))


def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
