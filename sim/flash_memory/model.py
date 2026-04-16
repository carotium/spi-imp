from random import Random

#from cocotb.log import SimLog
from forastero import MonitorEvent

from .driver import FlashMemoryResponseDriver
from .monitor import FlashMemoryRequestMonitor
from .transaction import FlashMemoryRequest, FlashMemoryResponse

READ_ID = 0x9E

class FlashMemoryModel:
    def __init__(self,
                 request: FlashMemoryRequestMonitor,
                 response: FlashMemoryResponseDriver,
                 random: Random) -> None:
        
        # References
        self._request = request
        self._response = response
        self._random = random
        #self._log = log

        self._memory = {}

        self._request.subscribe(MonitorEvent.CAPTURE, self._service)

    def reset(self) -> None:
        self._memory.clear()

    def write(self, address: int, data: int) -> None:
        self._memory[address] = data

    def read_id(self, tb, req_mon: FlashMemoryRequestMonitor, rsp_drv: FlashMemoryResponseDriver) -> None:
        tb.scoreboard.channels["flash_req_monitor"].push_reference(FlashMemoryRequest(cmd=READ_ID))


    def read(self, address: int) -> int:
        if address not in self._memory:
            self._memory[address] = self._random.getrandbits(8)
        return self._memory[address]
    
    def _service(self,
                 component: FlashMemoryRequestMonitor,
                 event: MonitorEvent,
                 transaction: FlashMemoryRequest) -> None:
        assert component is self._request
        assert event is MonitorEvent.CAPTURE
        if transaction.cmd == READ_ID:
            self.data = 0x20BA1910
            self._response.enqueue(FlashMemoryResponse())
