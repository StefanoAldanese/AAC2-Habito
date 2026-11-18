"""Helpers shared by the test suites of every app."""

from contextlib import contextmanager
from datetime import datetime, timezone as dt_timezone
from unittest import mock

from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APIClient, APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import Child, Parent, generate_child_token, hash_child_token

PASSWORD = "correct-horse-battery"


def create_parent(email: str = "mom@example.com", tz: str = "Asia/Tashkent", password: str = PASSWORD) -> Parent:
    return Parent.objects.create_user(email=email, password=password, timezone=tz)


def parent_client(parent: Parent) -> APIClient:
    client = APIClient()
    access = str(RefreshToken.for_user(parent).access_token)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    return client


def join(parent: Parent) -> str:
    """Creates the child directly and returns the raw device token."""
    token = generate_child_token()
    Child.objects.filter(parent=parent).delete()
    Child.objects.create(parent=parent, device_token_hash=hash_child_token(token))
    return token


def child_client(token: str) -> APIClient:
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


def utc(year, month, day, hour=0, minute=0, second=0) -> datetime:
    return datetime(year, month, day, hour, minute, second, tzinfo=dt_timezone.utc)


@contextmanager
def frozen_now(at: datetime):
    """Freeze the clock used by views and Django's timezone.now()."""
    with mock.patch("django.utils.timezone.now", return_value=at), mock.patch("tasks.days.now", return_value=at):
        yield


def create_task(parent, title="Brush teeth", repeat="daily", created_at=None, **fields):
    from tasks.models import Task

    task = Task.objects.create(parent=parent, title=title, repeat=repeat, **fields)
    if created_at is not None:  # auto_now_add ignores the given value
        Task.objects.filter(pk=task.pk).update(created_at=created_at)
        task.refresh_from_db()
    return task


@override_settings(HABITO_PUSH_BACKEND="memory")
class HabitoTestCase(APITestCase):
    """Clears the throttle cache and sent pushes so nothing leaks between tests."""

    def setUp(self):
        super().setUp()
        cache.clear()
        from notifications.backends import MemoryBackend

        MemoryBackend.clear()

    @property
    def sent_pushes(self):
        from notifications.backends import MemoryBackend

        return MemoryBackend.sent

    def assertError(self, response, status_code: int, code: str | None = None):
        self.assertEqual(response.status_code, status_code, response.content)
        self.assertIn("error", response.json())
        if code is not None:
            self.assertEqual(response.json()["error"]["code"], code, response.content)
