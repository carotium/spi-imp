from random import Random

#from cocotb.log import SimLog
from forastero import MonitorEvent, DriverEvent

from spi.requestor import SpiMisoDriver, SpiMonitor
from spi.transaction import SpiTrans

READ_ID = 0x9E

class FlashMemoryModel:
    def __init__(self,
                 request: SpiMonitor,
                 response: SpiMisoDriver,
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

    def read(self, address: int) -> int:
        if address not in self._memory:
            self._memory[address] = self._random.getrandbits(8)
        return self._memory[address]
    
    def _service(self,
                 component: SpiMonitor,
                 event: MonitorEvent,
                 transaction: SpiTrans) -> None:
        print(f'In service!')
        assert component is self._request
        assert event is MonitorEvent.CAPTURE
        print(f'cmd:{transaction.data}')
        print(f'queue:{self._response.queued}')
        if transaction.data == READ_ID:
            self._response.enqueue(SpiTrans(data=0x20))
        print(f'queue:{self._response.queued}')
