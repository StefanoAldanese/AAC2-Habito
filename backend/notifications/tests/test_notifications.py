from datetime import date
from unittest import mock

from django.test import SimpleTestCase, override_settings

from accounts.models import ParentDevice
from config.test_utils import HabitoTestCase, create_parent, create_task, utc
from notifications import service
from notifications.backends import ConsoleBackend, MemoryBackend, Message, get_backend
from tasks.models import Completion


class BackendSelectionTests(SimpleTestCase):
    def test_memory_and_console(self):
        with override_settings(HABITO_PUSH_BACKEND="memory"):
            self.assertIsInstance(get_backend(), MemoryBackend)
        with override_settings(HABITO_PUSH_BACKEND="console"):
            self.assertIsInstance(get_backend(), ConsoleBackend)

    def test_console_logs_without_tokens(self):
        with self.assertLogs("notifications.backends", level="INFO") as logs:
            ConsoleBackend().send(Message(tokens=["secret-token"], title="T", body="B"))
        self.assertNotIn("secret-token", "\n".join(logs.output))

    def test_apns_requires_settings(self):
        with override_settings(
            HABITO_PUSH_BACKEND="apns",
            PUSH_NOTIFICATIONS_SETTINGS={"APNS_AUTH_KEY_PATH": None, "APNS_AUTH_KEY_ID": None, "APNS_TEAM_ID": None, "APNS_TOPIC": None},
        ):
            with self.assertRaises(RuntimeError):
                get_backend()


class _Result:
    def __init__(self, ok: bool, description: str = ""):
        self.is_successful = ok
        self.description = description


_APNS_SETTINGS = {
    "APNS_AUTH_KEY_PATH": "/keys/AuthKey.p8",
    "APNS_AUTH_KEY_ID": "ABC123",
    "APNS_TEAM_ID": "TEAM1",
    "APNS_TOPIC": "uz.habito.app",
    "APNS_USE_SANDBOX": True,
}


class ApnsBackendTests(SimpleTestCase):
    @override_settings(PUSH_NOTIFICATIONS_SETTINGS=_APNS_SETTINGS)
    def test_reports_dead_tokens_only(self):
        from notifications.apns import ApnsBackend

        async def fake_send(registration_ids, alert, **kwargs):
            self.assertEqual(alert.title, "Task done")
            self.assertEqual(alert.body, "Brush teeth")
            return [
                ("good", _Result(True)),
                ("gone", _Result(False, "Unregistered")),
                ("bad", _Result(False, "BadDeviceToken")),
                ("flaky", _Result(False, "TimeoutError")),
            ]

        with mock.patch("notifications.apns._send_bulk_request", side_effect=fake_send):
            invalid = ApnsBackend().send(Message(tokens=["good", "gone", "bad", "flaky"], title="Task done", body="Brush teeth"))
        self.assertEqual(sorted(invalid), ["bad", "gone"])


class ServiceTests(HabitoTestCase):
    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        task = create_task(self.parent, "Brush teeth", "daily")
        self.completion = Completion.objects.create(
            task=task, parent=self.parent, task_title="Brush teeth", local_date=date(2026, 11, 16), done_at=utc(2026, 11, 16, 8)
        )

    def test_invalid_tokens_are_deleted(self):
        ParentDevice.objects.create(parent=self.parent, apns_token="good")
        ParentDevice.objects.create(parent=self.parent, apns_token="gone")

        class Backend:
            def send(self, message):
                return ["gone"]

        with mock.patch("notifications.service.get_backend", return_value=Backend()):
            service.notify_task_done(self.completion.pk)
        self.assertEqual(list(ParentDevice.objects.values_list("apns_token", flat=True)), ["good"])
        self.assertIsNotNone(ParentDevice.objects.get().last_used_at)

    def test_backend_failure_is_logged_not_raised(self):
        ParentDevice.objects.create(parent=self.parent, apns_token="good")

        class Backend:
            def send(self, message):
                raise ConnectionError("apns down")

        with mock.patch("notifications.service.get_backend", return_value=Backend()):
            with self.assertLogs("notifications.service", level="ERROR"):
                service.notify_task_done(self.completion.pk)
        self.assertEqual(ParentDevice.objects.count(), 1)

    def test_missing_completion_is_ignored(self):
        service.notify_task_done("00000000-0000-4000-8000-000000000000")
        self.assertEqual(self.sent_pushes, [])
