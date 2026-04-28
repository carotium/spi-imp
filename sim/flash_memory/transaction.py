from dataclasses import dataclass

from forastero import BaseTransaction

@dataclass(kw_only=True)
class FlashMemoryRequest(BaseTransaction):
    cmd: int = 0
    address: int = 0
    data: int = 0


@dataclass(kw_only=True)
class FlashMemoryResponse(BaseTransaction):
    data: int = 0
    bytes: int = 1
