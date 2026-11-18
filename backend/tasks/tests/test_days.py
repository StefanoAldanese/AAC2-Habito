from datetime import date
from zoneinfo import ZoneInfo

from django.test import TestCase

from config.test_utils import create_parent, create_task, utc
from tasks.days import (
    STATUS_DONE,
    STATUS_MISSED,
    STATUS_OPEN,
    STATUS_UPCOMING,
    current_day,
    is_due_on,
    start_day,
    status_on,
)

TASHKENT = ZoneInfo("Asia/Tashkent")  # UTC+5, no DST


class DailyTests(TestCase):
    def setUp(self):
        self.parent = create_parent()

    def test_starts_on_local_creation_day(self):
        # 22:00 UTC on Nov 10 is already Nov 11 in Tashkent.
        task = create_task(self.parent, repeat="daily", created_at=utc(2026, 11, 10, 22))
        self.assertEqual(start_day(task, TASHKENT), date(2026, 11, 11))
        self.assertFalse(is_due_on(task, date(2026, 11, 10), TASHKENT))
        self.assertTrue(is_due_on(task, date(2026, 11, 11), TASHKENT))
        self.assertTrue(is_due_on(task, date(2027, 1, 1), TASHKENT))

    def test_current_day_is_today(self):
        task = create_task(self.parent, repeat="daily", created_at=utc(2026, 11, 1))
        self.assertEqual(current_day(task, date(2026, 11, 16), TASHKENT), date(2026, 11, 16))


class OnceTests(TestCase):
    def setUp(self):
        self.parent = create_parent()

    def test_due_only_on_due_date(self):
        task = create_task(self.parent, repeat="once", due_date=date(2026, 11, 20), created_at=utc(2026, 11, 1))
        self.assertFalse(is_due_on(task, date(2026, 11, 19), TASHKENT))
        self.assertTrue(is_due_on(task, date(2026, 11, 20), TASHKENT))
        self.assertFalse(is_due_on(task, date(2026, 11, 21), TASHKENT))
        self.assertEqual(current_day(task, date(2026, 11, 16), TASHKENT), date(2026, 11, 20))


class StatusTests(TestCase):
    def test_status(self):
        today = date(2026, 11, 16)
        self.assertEqual(status_on(None, today, today, True), STATUS_DONE)
        self.assertEqual(status_on(None, today, today, False), STATUS_OPEN)
        self.assertEqual(status_on(None, date(2026, 11, 15), today, False), STATUS_MISSED)
        self.assertEqual(status_on(None, date(2026, 11, 17), today, False), STATUS_UPCOMING)
