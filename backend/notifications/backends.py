"""
How a notification leaves the server. Chosen by HABITO_PUSH_BACKEND:

    memory  - appended to `sent` for tests to inspect
    console - printed to the log
    apns    - Apple Push Notification service (needs the .p8 key settings)

Each backend's send() returns the list of device tokens Apple reported as
invalid, so the caller can delete them.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from django.conf import settings
from django.utils.module_loading import import_string

log = logging.getLogger(__name__)


@dataclass
class Message:
    tokens: list[str]
    title: str
    body: str
    data: dict = field(default_factory=dict)


class BaseBackend:
    def send(self, message: Message) -> list[str]:
        raise NotImplementedError


class MemoryBackend(BaseBackend):
    sent: list[Message] = []

    def send(self, message: Message) -> list[str]:
        MemoryBackend.sent.append(message)
        return []

    @classmethod
    def clear(cls) -> None:
        cls.sent = []


class ConsoleBackend(BaseBackend):
    def send(self, message: Message) -> list[str]:
        log.info("push to %d device(s): %s - %s", len(message.tokens), message.title, message.body)
        return []


_BACKENDS = {
    "memory": "notifications.backends.MemoryBackend",
    "console": "notifications.backends.ConsoleBackend",
    "apns": "notifications.apns.ApnsBackend",
}


def get_backend() -> BaseBackend:
    name = getattr(settings, "HABITO_PUSH_BACKEND", "console")
    path = _BACKENDS.get(name, name)
    return import_string(path)()
