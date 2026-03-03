from dataclasses import dataclass

from forastero import BaseTransaction

@dataclass(kw_only=True)
class SpiTrans(BaseTransaction):
    index: int = 0
    data: int = 0
