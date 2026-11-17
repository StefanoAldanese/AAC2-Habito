"""Builds and sends the "task done" push to the parent's phones."""

from __future__ import annotations

import logging

from django.db import transaction
from django.utils import timezone

from accounts.models import ParentDevice
from tasks.models import Completion

from .backends import Message, get_backend

log = logging.getLogger(__name__)


def notify_task_done(completion_id) -> None:
    """
    Sends one push per registered phone of the parent. The message carries
    only the task title. Failures are logged and never remove the completion.
    """
    completion = Completion.objects.filter(pk=completion_id).first()
    if completion is None:
        return
    devices = list(ParentDevice.objects.filter(parent_id=completion.parent_id))
    if not devices:
        return

    message = Message(
        tokens=[d.apns_token for d in devices],
        title="Task done",
        body=completion.task_title,
        data={"type": "task_done", "task_id": str(completion.task_id), "completion_id": str(completion.id)},
    )
    try:
        invalid = get_backend().send(message)
    except Exception:  # noqa: BLE001 - a push failure must not break the request
        log.exception("push notification failed for completion %s", completion.id)
        return

    if invalid:
        ParentDevice.objects.filter(apns_token__in=invalid).delete()
    ParentDevice.objects.filter(pk__in=[d.pk for d in devices]).exclude(apns_token__in=invalid).update(
        last_used_at=timezone.now()
    )


def notify_task_done_after_commit(completion: Completion) -> None:
    """Schedule the push for after the current transaction commits."""
    transaction.on_commit(lambda: notify_task_done(completion.pk))
