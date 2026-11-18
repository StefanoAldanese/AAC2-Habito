"""
Real APNs delivery through django-push-notifications' aioapns client, using
the token-based (.p8) key from PUSH_NOTIFICATIONS_SETTINGS.

The library's public helpers raise on the first failed token and hide the
per-token results, so this backend calls its request coroutine directly to
learn which tokens Apple rejected for good.
"""

from __future__ import annotations

import asyncio
import logging

from django.conf import settings
from push_notifications.apns_async import Alert, _send_bulk_request

from .backends import BaseBackend, Message

log = logging.getLogger(__name__)

# Apple's reasons that mean "this token will never work again".
_DEAD_TOKEN_REASONS = {"Unregistered", "BadDeviceToken", "DeviceTokenNotForTopic"}


class ApnsBackend(BaseBackend):
    def __init__(self) -> None:
        conf = settings.PUSH_NOTIFICATIONS_SETTINGS
        missing = [k for k in ("APNS_AUTH_KEY_PATH", "APNS_AUTH_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC") if not conf.get(k)]
        if missing:
            raise RuntimeError(f"HABITO_PUSH_BACKEND=apns needs these settings: {', '.join(missing)}")

    def send(self, message: Message) -> list[str]:
        alert = Alert(title=message.title, body=message.body)
        responses = asyncio.run(
            _send_bulk_request(
                registration_ids=message.tokens,
                alert=alert,
                extra=message.data or None,
                sound="default",
            )
        )
        invalid: list[str] = []
        for token, result in responses:
            if result.is_successful:
                continue
            if result.description in _DEAD_TOKEN_REASONS:
                invalid.append(token)
            else:
                log.warning("APNs send failed (%s) for one device", result.description)
        return invalid
