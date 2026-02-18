# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from dataclasses import dataclass

from forastero import BaseTransaction

@dataclass(kw_only=True)
class ObiChATrans(BaseTransaction):
    addr: int = 0
    wdata: int = 0xDEADBEEF
    we: bool = False
    be: int = 0


