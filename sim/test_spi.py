from forastero.io import IORole, io_suffix_style
from forastero.driver import DriverEvent
from forastero import BaseBench

from base import get_test_runner, WAVES
from handshake.io import HandshakeIO
from handshake.requestor import HandshakeRequestMonitor, HandshakeRequestDriver
from handshake.responder import HandshakeResponderDriver
from handshake.sequences import handshake_ready_seq, handshake_rand_data_seq
from handshake.transaction import HandshakeValid

class SpiImpTB(BaseBench):
    def __init__(self, dut):
        super().__init__(dut, clk=dut.clk_i, rst=dut.rstn_i, rst_active_high=False)
        input_io = HandshakeIO(dut, "input", IORole.RESPONDER, io_style=io_suffix_style)
        output_io = HandshakeIO(dut, "output", IORole.INITIATOR, io_style=io_suffix_style)
        self.register("input_driver", HandshakeRequestDriver(self, input_io, self.clk, self.rst))
        self.register("output_driver", HandshakeResponderDriver(self, output_io, self.clk, self.rst, blocking=False))
        self.register("output_monitor", HandshakeRequestMonitor(self, output_io, self.clk, self.rst))

        # Register callback on input driver to push reference to monitor
        self.input_driver.subscribe(DriverEvent.ENQUEUE, self.push_reference)

    def push_reference(self, driver: HandshakeRequestDriver, event: DriverEvent, obj: HandshakeValid) -> None:
        assert driver is self.input_driver
        assert event == DriverEvent.ENQUEUE
        self.scoreboard.channels["output_monitor"].push_reference(obj)

@SpiImpTB.testcase(
    reset_wait_during=2,
    reset_wait_after=0,
    timeout=1000,
    shutdown_delay=1,
    shutdown_loops=1,
)
async def random_raffic(tb: SpiImpTB, log):
    log.info(f"Scheduling random traffic to the SPI input.")
    tb.schedule(handshake_rand_data_seq(input_drv=tb.input_driver, length=100, delay_range=(0, 5)))
    log.info(f"Scheduling random ready backpressure.")
    tb.schedule(handshake_ready_seq(ready_drv=tb.output_driver), blocking=False)

def test_spi_runner():
    runner = get_test_runner("spi_imp")
    runner.test(hdl_toplevel="spi_imp", test_module="test_spi", waves=WAVES)

if __name__ == "__main__":
    test_spi_runner()
