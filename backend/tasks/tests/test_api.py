from datetime import date

from django.urls import reverse

from accounts.models import ParentDevice
from config.test_utils import (
    HabitoTestCase,
    child_client,
    create_parent,
    create_task,
    frozen_now,
    join,
    parent_client,
    utc,
)
from tasks.models import Completion, Task

# Asia/Tashkent is UTC+5 all year: local midnight is 19:00 UTC the day before.
NOON = utc(2026, 11, 16, 7)  # 12:00 on Nov 16 in Tashkent


class CreateTaskTests(HabitoTestCase):
    url = reverse("tasks")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)

    def test_create_daily(self):
        with frozen_now(NOON):
            response = self.client.post(self.url, {"title": "Brush teeth", "repeat": "daily"})
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["title"], "Brush teeth")
        self.assertEqual(body["repeat"], "daily")
        self.assertIsNone(body["due_date"])
        self.assertEqual(body["status"], "open")
        self.assertIsNone(body["done_at"])

    def test_create_once_with_due_date(self):
        with frozen_now(NOON):
            response = self.client.post(self.url, {"title": "Dentist", "repeat": "once", "due_date": "2026-11-20"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["due_date"], "2026-11-20")
        self.assertEqual(response.json()["status"], "upcoming")

    def test_create_once_defaults_to_local_today(self):
        with frozen_now(utc(2026, 11, 16, 22)):  # already Nov 17 in Tashkent
            response = self.client.post(self.url, {"title": "Dentist", "repeat": "once"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["due_date"], "2026-11-17")
        self.assertEqual(response.json()["status"], "open")

    def test_daily_cannot_have_due_date(self):
        response = self.client.post(self.url, {"title": "X", "repeat": "daily", "due_date": "2026-11-20"})
        self.assertError(response, 400, "invalid_input")
        self.assertIn("due_date", response.json()["error"]["fields"])

    def test_validation(self):
        self.assertError(self.client.post(self.url, {"title": "X"}), 400, "invalid_input")
        self.assertError(self.client.post(self.url, {"title": "X", "repeat": "hourly"}), 400, "invalid_input")
        self.assertError(self.client.post(self.url, {"title": "", "repeat": "daily"}), 400, "invalid_input")
        self.assertError(self.client.post(self.url, {"title": "x" * 81, "repeat": "daily"}), 400, "invalid_input")

    def test_child_and_anonymous_forbidden(self):
        self.assertError(child_client(join(self.parent)).post(self.url, {"title": "x", "repeat": "daily"}), 403)
        self.assertError(self.client.__class__().post(self.url, {"title": "x", "repeat": "daily"}), 401)
        self.assertEqual(Task.objects.count(), 0)


class ListTasksTests(HabitoTestCase):
    url = reverse("tasks")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)
        self.daily = create_task(self.parent, "Brush teeth", "daily", created_at=utc(2026, 11, 1))
        self.past = create_task(self.parent, "Old chore", "once", due_date=date(2026, 11, 10), created_at=utc(2026, 11, 1))
        self.future = create_task(self.parent, "Dentist", "once", due_date=date(2026, 11, 20), created_at=utc(2026, 11, 1))
        create_task(create_parent("dad@example.com"), "Theirs", "daily")

    def test_list_with_statuses(self):
        Completion.objects.create(task=self.daily, parent=self.parent, task_title="Brush teeth", local_date=date(2026, 11, 16), done_at=utc(2026, 11, 16, 3))
        with frozen_now(NOON):
            response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(
            [(t["title"], t["status"]) for t in response.json()],
            [("Brush teeth", "done"), ("Old chore", "missed"), ("Dentist", "upcoming")],
        )
        self.assertEqual(response.json()[0]["done_at"], "2026-11-16T03:00:00Z")

    def test_daily_status_resets_each_day(self):
        Completion.objects.create(task=self.daily, parent=self.parent, task_title="Brush teeth", local_date=date(2026, 11, 16), done_at=utc(2026, 11, 16, 3))
        with frozen_now(utc(2026, 11, 16, 19)):  # 00:00 Nov 17 local
            body = self.client.get(self.url).json()
        self.assertEqual(body[0]["status"], "open")

    def test_only_own_tasks(self):
        with frozen_now(NOON):
            titles = [t["title"] for t in self.client.get(self.url).json()]
        self.assertNotIn("Theirs", titles)

    def test_child_forbidden(self):
        self.assertError(child_client(join(self.parent)).get(self.url), 403, "forbidden")


class DeleteTaskTests(HabitoTestCase):
    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)
        self.task = create_task(self.parent, "Brush teeth", "daily")

    def test_delete_keeps_completions(self):
        Completion.objects.create(task=self.task, parent=self.parent, task_title="Brush teeth", local_date=date(2026, 11, 16), done_at=utc(2026, 11, 16, 3))
        response = self.client.delete(reverse("task-detail", args=[self.task.id]))
        self.assertEqual(response.status_code, 204)
        self.assertEqual(Task.objects.count(), 0)
        completion = Completion.objects.get()
        self.assertIsNone(completion.task)
        self.assertEqual(completion.task_title, "Brush teeth")

    def test_other_parents_task_404(self):
        other = create_task(create_parent("dad@example.com"), "Theirs", "daily")
        self.assertError(self.client.delete(reverse("task-detail", args=[other.id])), 404, "not_found")
        self.assertEqual(Task.objects.count(), 2)

    def test_child_forbidden(self):
        self.assertError(child_client(join(self.parent)).delete(reverse("task-detail", args=[self.task.id])), 403)
        self.assertEqual(Task.objects.count(), 1)


class TodayTests(HabitoTestCase):
    url = reverse("today")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.token = join(self.parent)
        self.daily = create_task(self.parent, "Brush teeth", "daily", created_at=utc(2026, 11, 1))
        create_task(self.parent, "Make the bed", "daily", created_at=utc(2026, 11, 1))
        create_task(self.parent, "Dentist today", "once", due_date=date(2026, 11, 16), created_at=utc(2026, 11, 1))
        create_task(self.parent, "Dentist later", "once", due_date=date(2026, 11, 20), created_at=utc(2026, 11, 1))
        create_task(self.parent, "Future daily", "daily", created_at=utc(2026, 11, 20))

    def test_child_sees_todays_tasks(self):
        Completion.objects.create(task=self.daily, parent=self.parent, task_title="Brush teeth", local_date=date(2026, 11, 16), done_at=utc(2026, 11, 16, 3))
        with frozen_now(NOON):
            response = child_client(self.token).get(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["date"], "2026-11-16")
        self.assertEqual(
            [(t["title"], t["status"]) for t in body["tasks"]],
            [("Brush teeth", "done"), ("Make the bed", "open"), ("Dentist today", "open")],
        )

    def test_parent_sees_the_same(self):
        with frozen_now(NOON):
            body = parent_client(self.parent).get(self.url).json()
        self.assertEqual(len(body["tasks"]), 3)

    def test_today_uses_parent_timezone(self):
        with frozen_now(utc(2026, 11, 16, 20)):  # 01:00 Nov 17 in Tashkent
            body = child_client(self.token).get(self.url).json()
        self.assertEqual(body["date"], "2026-11-17")
        self.assertNotIn("Dentist today", [t["title"] for t in body["tasks"]])

    def test_anonymous(self):
        self.assertError(self.client.get(self.url), 401)


class DoneTests(HabitoTestCase):
    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.child = child_client(join(self.parent))
        self.daily = create_task(self.parent, "Brush teeth", "daily", created_at=utc(2026, 11, 1))
        self.once = create_task(self.parent, "Dentist", "once", due_date=date(2026, 11, 17), created_at=utc(2026, 11, 1))

    def done(self, task, at):
        with frozen_now(at), self.captureOnCommitCallbacks(execute=True):
            return self.child.post(reverse("task-done", args=[task.id]))

    def test_done_just_before_local_midnight(self):
        response = self.done(self.daily, utc(2026, 11, 16, 18, 59))  # 23:59 Nov 16 local
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["local_date"], "2026-11-16")
        self.assertEqual(response.json()["task_title"], "Brush teeth")

    def test_new_day_after_local_midnight(self):
        self.done(self.daily, utc(2026, 11, 16, 18, 59))
        response = self.done(self.daily, utc(2026, 11, 16, 19))  # 00:00 Nov 17 local
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["local_date"], "2026-11-17")
        self.assertEqual(Completion.objects.count(), 2)

    def test_already_done_today(self):
        self.done(self.daily, utc(2026, 11, 16, 10))
        self.assertError(self.done(self.daily, utc(2026, 11, 16, 11)), 409, "already_done")
        self.assertEqual(Completion.objects.count(), 1)

    def test_once_only_on_due_date(self):
        self.assertError(self.done(self.once, utc(2026, 11, 16, 18, 59)), 409, "not_due_today")
        self.assertEqual(self.done(self.once, utc(2026, 11, 16, 19)).status_code, 201)
        self.assertError(self.done(self.once, utc(2026, 11, 17, 19)), 409, "not_due_today")

    def test_daily_not_before_creation_day(self):
        self.assertError(self.done(self.daily, utc(2026, 10, 20)), 409, "not_due_today")

    def test_no_undo(self):
        self.done(self.daily, utc(2026, 11, 16, 10))
        with frozen_now(utc(2026, 11, 16, 11)):
            response = self.child.delete(reverse("task-done", args=[self.daily.id]))
        self.assertError(response, 405, "method_not_allowed")
        self.assertEqual(Completion.objects.count(), 1)

    def test_parent_cannot_mark_done(self):
        with frozen_now(NOON):
            response = parent_client(self.parent).post(reverse("task-done", args=[self.daily.id]))
        self.assertError(response, 403, "forbidden")

    def test_other_parents_task_404(self):
        other = create_task(create_parent("dad@example.com"), "Theirs", "daily", created_at=utc(2026, 11, 1))
        self.assertError(self.done(other, NOON), 404, "not_found")

    def test_push_to_every_parent_phone(self):
        ParentDevice.objects.create(parent=self.parent, apns_token="phone-1")
        ParentDevice.objects.create(parent=self.parent, apns_token="phone-2")
        ParentDevice.objects.create(parent=create_parent("dad@example.com"), apns_token="someone-else")
        self.done(self.daily, NOON)
        self.assertEqual(len(self.sent_pushes), 1)
        push = self.sent_pushes[0]
        self.assertEqual(sorted(push.tokens), ["phone-1", "phone-2"])
        self.assertEqual(push.title, "Task done")
        self.assertEqual(push.body, "Brush teeth")
        self.assertEqual(push.data["task_id"], str(self.daily.id))
        self.assertIsNotNone(ParentDevice.objects.get(apns_token="phone-1").last_used_at)

    def test_no_push_without_devices_or_on_failure(self):
        self.done(self.daily, NOON)
        self.assertEqual(self.sent_pushes, [])
        ParentDevice.objects.create(parent=self.parent, apns_token="phone-1")
        self.done(self.daily, utc(2026, 11, 16, 8))  # already done
        self.assertEqual(self.sent_pushes, [])


class HistoryTests(HabitoTestCase):
    url = reverse("history")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)
        self.teeth = create_task(self.parent, "Brush teeth", "daily", created_at=utc(2026, 11, 1))
        self.bed = create_task(self.parent, "Make the bed", "daily", created_at=utc(2026, 11, 15, 10))  # from Nov 15
        create_task(self.parent, "Dentist", "once", due_date=date(2026, 11, 15), created_at=utc(2026, 11, 1))
        self._done(self.teeth, date(2026, 11, 14))
        self._done(self.teeth, date(2026, 11, 15))
        self._done(self.bed, date(2026, 11, 15))
        self._done(self.teeth, date(2026, 11, 16))

    def _done(self, task, day):
        Completion.objects.create(task=task, parent=self.parent, task_title=task.title, local_date=day, done_at=utc(day.year, day.month, day.day, 10))

    def test_days_newest_first_with_counts(self):
        with frozen_now(NOON):
            response = self.client.get(self.url, {"from": "2026-11-14", "to": "2026-11-16"})
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["from_date"], "2026-11-14")
        self.assertEqual(body["to_date"], "2026-11-16")
        self.assertEqual(
            body["days"],
            [
                {"date": "2026-11-16", "total": 2, "done": 1},
                {"date": "2026-11-15", "total": 3, "done": 2},
                {"date": "2026-11-14", "total": 1, "done": 1},
            ],
        )

    def test_default_range_is_last_7_days(self):
        with frozen_now(NOON):
            body = self.client.get(self.url).json()
        self.assertEqual(body["from_date"], "2026-11-10")
        self.assertEqual(body["to_date"], "2026-11-16")
        self.assertEqual(len(body["days"]), 7)
        self.assertEqual(body["days"][0]["date"], "2026-11-16")

    def test_deleted_task_still_counts(self):
        self.bed.delete()
        with frozen_now(NOON):
            body = self.client.get(self.url, {"from": "2026-11-15", "to": "2026-11-15"}).json()
        self.assertEqual(body["days"], [{"date": "2026-11-15", "total": 3, "done": 2}])

    def test_bad_ranges(self):
        self.assertError(self.client.get(self.url, {"from": "yesterday"}), 400, "invalid_input")
        self.assertError(self.client.get(self.url, {"from": "2026-11-17", "to": "2026-11-16"}), 400, "invalid_input")
        self.assertError(self.client.get(self.url, {"from": "2026-10-01", "to": "2026-11-17"}), 400, "invalid_input")
        self.assertEqual(self.client.get(self.url, {"from": "2026-10-18", "to": "2026-11-17"}).status_code, 200)

    def test_child_forbidden(self):
        self.assertError(child_client(join(self.parent)).get(self.url), 403, "forbidden")
