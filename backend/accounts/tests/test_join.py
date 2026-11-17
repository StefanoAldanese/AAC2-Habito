from django.urls import reverse

from accounts.models import Child, hash_child_token
from config.test_utils import HabitoTestCase, child_client, create_parent, join


class JoinTests(HabitoTestCase):
    url = reverse("join")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()

    def test_join_ok(self):
        response = self.client.post(self.url, {"code": self.parent.room_code})
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(len(body["child_token"]), 64)
        self.assertEqual(body["child"]["timezone"], "Asia/Tashkent")
        child = Child.objects.get()
        self.assertEqual(child.parent, self.parent)
        self.assertEqual(child.device_token_hash, hash_child_token(body["child_token"]))
        self.assertNotEqual(child.device_token_hash, body["child_token"])

        me = child_client(body["child_token"]).get(reverse("me"))
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["role"], "child")

    def test_code_is_case_insensitive_and_ignores_spaces(self):
        code = self.parent.room_code.lower()
        response = self.client.post(self.url, {"code": f" {code[:3]} {code[3:]} "})
        self.assertEqual(response.status_code, 201, response.content)

    def test_unknown_code(self):
        self.assertError(self.client.post(self.url, {"code": "ZZZZZZ"}), 404, "invalid_code")
        self.assertEqual(Child.objects.count(), 0)

    def test_missing_code(self):
        self.assertError(self.client.post(self.url, {}), 400, "invalid_input")

    def test_rejoin_replaces_previous_device(self):
        old = join(self.parent)
        self.assertEqual(child_client(old).get(reverse("me")).status_code, 200)
        response = self.client.post(self.url, {"code": self.parent.room_code})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Child.objects.count(), 1)
        self.assertError(child_client(old).get(reverse("me")), 401)
        self.assertEqual(child_client(response.json()["child_token"]).get(reverse("me")).status_code, 200)

    def test_rate_limited_per_ip(self):
        for _ in range(10):
            self.client.post(self.url, {"code": "ZZZZZZ"})
        self.assertError(self.client.post(self.url, {"code": self.parent.room_code}), 429, "too_many_attempts")
        self.assertEqual(Child.objects.count(), 0)
        other_ip = self.client.post(self.url, {"code": self.parent.room_code}, REMOTE_ADDR="10.0.0.9")
        self.assertEqual(other_ip.status_code, 201, other_ip.content)

    def test_child_cannot_use_parent_endpoints(self):
        client = child_client(join(self.parent))
        self.assertError(client.get(reverse("tasks")), 403, "forbidden")
        self.assertError(client.post(reverse("tasks"), {"title": "x", "repeat": "daily"}), 403, "forbidden")
        self.assertError(client.get(reverse("history")), 403, "forbidden")
        self.assertError(client.delete(reverse("auth-account")), 403, "forbidden")
        self.assertError(client.post(reverse("auth-logout"), {"refresh": "x"}), 403, "forbidden")

    def test_deleting_parent_deletes_child(self):
        join(self.parent)
        self.parent.delete()
        self.assertEqual(Child.objects.count(), 0)
