from dataclasses import dataclass

from forastero import BaseTransaction

@dataclass(kw_only=True)
class SpiTrans(BaseTransaction):
    data: int = 0

@dataclass(kw_only=True)
class SpiMisoTrans(BaseTransaction):
    data: int = 0
