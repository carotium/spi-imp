from collections.abc import Callable

from cocotb.handle import HierarchyObject
from forastero import BaseIO, IORole


class FlashMemoryIO(BaseIO):
    def __init__(
            self,
            dut: HierarchyObject,
            name: str,
            role: IORole,
            io_style: Callable[[str | None, str, IORole, IORole], str] | None = None,
    ):
        super().__init__(
            dut,
            name,
            role,
            ["ss", "sclk", "mosi"],
            ["miso"],
            io_style
        )
