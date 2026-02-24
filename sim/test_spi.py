from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from base import get_test_runner, WAVES
from handshake.io import ObiChAIO, ObiChRIO, SpiIO
from handshake.requestor import ObiChARequestDriver, ObiChRRequestMonitor, SpiRequestDriver
from handshake.sequences import obi_channel_a_trans, spi_trans
from handshake.transaction import ObiChATrans, ObiChRTrans, SpiTransferTrans

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        obi_a_io = ObiChAIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        obi_r_io = ObiChRIO(dut, "obi", IORole.RESPONDER, io_style=io_suffix_style)
        spi_io = SpiIO(dut, "spi", IORole.RESPONDER, io_style=io_suffix_style)

        self.register("obi_a_drv", ObiChARequestDriver(self, obi_a_io, self.clk, self.rst))

        self.register("obi_r_monitor", ObiChRRequestMonitor(self, obi_r_io, self.clk, self.rst))

        self.register("spi_drv", SpiRequestDriver(self, spi_io, self.clk, self.rst))


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

    # Write to data reg and read from ctrl reg
    tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=2))

    #tb.scoreboard.channels["obi_r_monitor"].push_reference(ObiChRTrans(rdata=1))


    trans = [
        ObiChATrans(addr=0x0000, wdata=87, we=True, be=0x1),
        ObiChATrans(addr=0x0000, we=False, be=0x1),

        ObiChATrans(addr=0x0001, wdata=0x1, we=True, be=0x1),
        ObiChATrans(addr=0x0001, we=False, be=0x1),

        #ObiChATrans(addr=0x0001, wdata=0, we=True, be=1),
    ]

    tran_spi = [
        SpiTransferTrans(miso=True),
    ]

    tb.schedule(obi_channel_a_trans(obi_a_drv=tb.obi_a_drv, trans=trans))
    #tb.schedule(spi_trans(spi_drv=tb.spi_drv, trans=tran_spi))

def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
