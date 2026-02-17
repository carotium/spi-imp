# SPDX-License-Identifier: MIT
# Copyright (c) 2023-2024 Vypercore. All Rights Reserved

from dataclasses import dataclass

from forastero import BaseTransaction

@dataclass(kw_only=True)
class HandshakeValid(BaseTransaction):
    data: int = 0
    valid: bool = True

@dataclass(kw_only=True)
class HandshakeReady(BaseTransaction):
    ready: bool = True
    delay: int = 1
