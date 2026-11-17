"""
DRF's SimpleRateThrottle understands "5/m" but not "5/15m". This base class
accepts both, so the spec's "per 15 minutes" limits can be written as such.
"""

import re

from rest_framework.throttling import SimpleRateThrottle

_RATE = re.compile(r"^\s*(\d+)\s*/\s*(\d*)\s*([smhd])\s*$")
_SECONDS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


class WindowRateThrottle(SimpleRateThrottle):
    def parse_rate(self, rate):
        if rate is None:
            return (None, None)
        match = _RATE.match(rate)
        if not match:
            raise ValueError(f"Bad throttle rate {rate!r}; expected e.g. '10/15m'")
        num, count, unit = match.groups()
        return int(num), int(count or 1) * _SECONDS[unit]
