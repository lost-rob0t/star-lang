"""Authority-owned exact JSON numbers beyond the host Decimal representation.

Comparisons use sign, decimal order, and coefficient digits; they never expand
10 ** exponent or convert the value to a float. This is a wire value, not an
arbitrary-precision arithmetic package.

Authority-owned adaptation of the exact wire algorithm independently developed
in starintel-doc SDK commit 5096ab039cb240aae0057fbed8ae6a7667321bbf. This module
imports only Python standard-library modules; it does not depend on an SDK.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from functools import total_ordering
from typing import Any

_NUMBER = re.compile(r"(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?")


def _parts(token: str) -> tuple[int, str, int]:
    match = _NUMBER.fullmatch(token)
    if match is None:
        raise ValueError("invalid JSON number token")
    negative, integer, fraction, exponent = match.groups()
    digits = integer + (fraction or "")
    significant = digits.lstrip("0")
    if not significant:
        return 0, "0", 0
    # The exponent itself is an ordinary integer, not a power to materialize.
    # Decimal-to-int avoids the process-global string conversion digit limit.
    order = int(Decimal(exponent or "0")) + len(integer) - (len(digits) - len(significant))
    return (-1 if negative else 1), significant.rstrip("0"), order


def _other_parts(value: Any) -> tuple[int, str, int] | Any:
    if isinstance(value, RawJsonNumber):
        return value._components
    if isinstance(value, bool):
        return NotImplemented
    if isinstance(value, int):
        return _parts(str(Decimal(value)))
    if isinstance(value, Decimal) and value.is_finite():
        return _parts(str(value))
    if isinstance(value, float) and math.isfinite(value):
        return _parts(str(value))
    return NotImplemented


@total_ordering
@dataclass(frozen=True, eq=False)
class RawJsonNumber:
    """A validated JSON number lexeme with exact comparison and integer tests.

    The reference parser uses Decimal where representable and this value otherwise.
    Serialize with the reference encoder; arithmetic is deliberately not provided.
    """
    token: str
    _components: tuple[int, str, int] = field(init=False, repr=False)
    __hash__ = None

    def __post_init__(self) -> None:
        if not isinstance(self.token, str):
            raise TypeError("JSON number token must be a string")
        object.__setattr__(self, "_components", _parts(self.token))

    def is_integer(self) -> bool:
        sign, digits, order = self._components
        return sign == 0 or order >= len(digits)

    def _compare(self, other: Any) -> int | Any:
        right = _other_parts(other)
        if right is NotImplemented:
            return NotImplemented
        left_sign, left_digits, left_order = self._components
        right_sign, right_digits, right_order = right
        if left_sign != right_sign:
            return (left_sign > right_sign) - (left_sign < right_sign)
        if left_sign == 0:
            return 0
        if left_order != right_order:
            return left_sign * ((left_order > right_order) - (left_order < right_order))
        length = max(len(left_digits), len(right_digits))
        left_digits, right_digits = left_digits.ljust(length, "0"), right_digits.ljust(length, "0")
        return left_sign * ((left_digits > right_digits) - (left_digits < right_digits))

    def __eq__(self, other: Any) -> bool:
        result = self._compare(other)
        return NotImplemented if result is NotImplemented else result == 0

    def __lt__(self, other: Any) -> bool:
        result = self._compare(other)
        return NotImplemented if result is NotImplemented else result < 0


def parse_fraction(token: str) -> Decimal | RawJsonNumber:
    try:
        value = Decimal(token)
        if value.is_finite():
            return value
    except InvalidOperation:
        pass
    return RawJsonNumber(token)
