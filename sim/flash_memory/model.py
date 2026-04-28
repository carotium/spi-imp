from random import Random

#from cocotb.log import SimLog
from forastero import MonitorEvent, DriverEvent

from spi.requestor import SpiMisoDriver, SpiMonitor
from spi.transaction import SpiTrans

# Commands
READ_ID = 0x9E
READ = 0x03
PAGE_PROGRAM = 0x02

# Data output
read_id_data = [
    0x20,
    0xBA,
    0x19,
    0x10,
    0x0
]

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

        self._index = 0
        self._address = 0
        self._cmd = 0

        self._memory = [0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA]

        self._request.subscribe(MonitorEvent.CAPTURE, self._service)

    def reset(self) -> None:
        #self._memory.clear()
        self._index = 0

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
        assert component is self._request
        assert event is MonitorEvent.CAPTURE

        if transaction.data == READ_ID:
            self._cmd = READ_ID
            self._response.enqueue(SpiTrans(data=read_id_data[self._index]))
            print(f'Captured READ_ID')
            print(f'idx:{self._index}')
            self._index += 1
        elif self._index < 20 and self._cmd == READ_ID:
            self._response.enqueue(SpiTrans(data=read_id_data[self._index]))
            print(f'Responding to READ_ID')
            print(f'idx:{self._index}')
            self._index += 1

        if transaction.data == READ:
            print(f'Captured READ')
            self._cmd = READ
            # Wait for three bytes of address data
            self._index = 2
            self._address = 0
        elif self._index >= 0 and self._cmd == READ:
            print(f'Responding to READ, data={transaction.data}, idx: {self._index}')
            self._address += transaction.data << (8 * (self._index))
            if(self._index == 0):
                print(f'address={self._address}')
                self._response.enqueue(SpiTrans(data=self._memory[self._address]))
                self._address += 1
            self._index -= 1
        elif self._index == -1 and self._cmd == READ:
            print(f'got address: {self._address}')
            self._response.enqueue(SpiTrans(data=self._memory[self._address]))
            self._address += 1

        if transaction.data == PAGE_PROGRAM:
            print(f'Captured PAGE_PROGRAM')
            self._cmd = PAGE_PROGRAM
            # Wait for three bytes of address data
            self._index = 2
        elif self._index >= 0 and self._cmd == PAGE_PROGRAM:
            print(f'Responding to PAGE_PROGRAM, address[{self._index}]={transaction.data}')
            self._address += transaction.data << (8 * self._index)
            if(self._index == 0):
                print(f'address={self._address}')
            self._index -= 1
        elif self._index == -1 and self._cmd == PAGE_PROGRAM:
            print(f'address: {self._address}, data: {transaction.data}')
            self._memory[self._address] = transaction.data
            self._address += 1

        print(f'memory::{self._memory}')
