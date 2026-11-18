"""
Every endpoint against every caller: parent, child, nobody.

Expected: "ok" (2xx), 401 (not signed in), 403 (wrong role) or 404 (a task
that belongs to another parent).
"""

from django.urls import reverse
from rest_framework.test import APIClient

from config.test_utils import HabitoTestCase, child_client, create_parent, create_task, frozen_now, join, parent_client, utc

NOW = utc(2026, 11, 16, 10)  # 15:00 in Asia/Tashkent


class PermissionMatrixTests(HabitoTestCase):
    def setUp(self):
        super().setUp()
        self.parent = create_parent("mom@example.com")
        self.task = create_task(self.parent, "Brush teeth", "daily", created_at=utc(2026, 11, 1))
        self.stranger = create_parent("stranger@example.com")
        self.other_task = create_task(self.stranger, "Theirs", "daily", created_at=utc(2026, 11, 1))
        self.clients = {
            "parent": parent_client(self.parent),
            "child": child_client(join(self.parent)),
            "anon": APIClient(),
        }

    def check(self, who, method, url, expected, data=None):
        with frozen_now(NOW), self.captureOnCommitCallbacks(execute=True):
            response = getattr(self.clients[who], method)(url, data)
        if expected == "ok":
            self.assertEqual(response.status_code // 100, 2, f"{who} {method} {url}: {response.content}")
        else:
            self.assertEqual(response.status_code, expected, f"{who} {method} {url}: {response.content}")
            self.assertIn("error", response.json())

    def test_devices(self):
        self.check("child", "post", reverse("devices"), 403, {"apns_token": "t"})
        self.check("anon", "post", reverse("devices"), 401, {"apns_token": "t"})
        self.check("parent", "post", reverse("devices"), "ok", {"apns_token": "t"})

    def test_tasks_list_and_create(self):
        for method, data in (("get", None), ("post", {"title": "T", "repeat": "daily"})):
            self.check("child", method, reverse("tasks"), 403, data)
            self.check("anon", method, reverse("tasks"), 401, data)
            self.check("parent", method, reverse("tasks"), "ok", data)

    def test_task_delete(self):
        self.check("child", "delete", reverse("task-detail", args=[self.task.id]), 403)
        self.check("anon", "delete", reverse("task-detail", args=[self.task.id]), 401)
        self.check("parent", "delete", reverse("task-detail", args=[self.other_task.id]), 404)
        self.check("parent", "delete", reverse("task-detail", args=[self.task.id]), "ok")

    def test_today(self):
        self.check("anon", "get", reverse("today"), 401)
        self.check("parent", "get", reverse("today"), "ok")
        self.check("child", "get", reverse("today"), "ok")

    def test_done(self):
        url = reverse("task-done", args=[self.task.id])
        self.check("parent", "post", url, 403)
        self.check("anon", "post", url, 401)
        self.check("child", "post", reverse("task-done", args=[self.other_task.id]), 404)
        self.check("child", "post", url, "ok")
        self.check("child", "delete", url, 405)  # no undo

    def test_history(self):
        self.check("child", "get", reverse("history"), 403)
        self.check("anon", "get", reverse("history"), 401)
        self.check("parent", "get", reverse("history"), "ok")

    def test_me(self):
        self.check("anon", "get", reverse("me"), 401)
        self.check("parent", "get", reverse("me"), "ok")
        self.check("child", "get", reverse("me"), "ok")

    def test_logout_and_delete_account(self):
        self.check("child", "delete", reverse("auth-account"), 403)
        self.check("anon", "delete", reverse("auth-account"), 401)
        self.check("child", "post", reverse("auth-logout"), 403, {"refresh": "x"})
        self.check("parent", "delete", reverse("auth-account"), "ok")

    def test_join_needs_no_token(self):
        self.check("anon", "post", reverse("join"), 404, {"code": "ZZZZZZ"})
        self.check("anon", "post", reverse("join"), "ok", {"code": self.parent.room_code})
