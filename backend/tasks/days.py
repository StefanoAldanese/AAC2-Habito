"""
Which tasks are due on which local day. Nothing is stored: a daily task is
due every day from the day it was created, a one-time task on its due_date.
"""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

from django.utils import timezone

from .models import Repeat, Task

STATUS_OPEN = "open"  # due today, not done yet
STATUS_DONE = "done"
STATUS_MISSED = "missed"  # the day ended without a mark
STATUS_UPCOMING = "upcoming"  # one-time task with a due date in the future


def now() -> datetime:
    """Single clock so tests can freeze it."""
    return timezone.now()


def local_today(tz: ZoneInfo) -> date:
    return now().astimezone(tz).date()


def start_day(task: Task, tz: ZoneInfo) -> date:
    """The first local day a task is due."""
    if task.repeat == Repeat.ONCE:
        return task.due_date
    return task.created_at.astimezone(tz).date()


def is_due_on(task: Task, day: date, tz: ZoneInfo) -> bool:
    if task.repeat == Repeat.ONCE:
        return task.due_date == day
    return start_day(task, tz) <= day


def status_on(task: Task, day: date, today: date, done: bool) -> str:
    if done:
        return STATUS_DONE
    if day > today:
        return STATUS_UPCOMING
    if day == today:
        return STATUS_OPEN
    return STATUS_MISSED


def current_day(task: Task, today: date, tz: ZoneInfo) -> date:
    """The day whose status the parent cares about: today for daily, due_date for once."""
    if task.repeat == Repeat.ONCE:
        return task.due_date
    return max(today, start_day(task, tz))
