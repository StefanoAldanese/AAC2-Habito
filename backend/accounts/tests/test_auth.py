from datetime import timedelta

from django.db import IntegrityError
from django.urls import reverse
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import ROOM_CODE_ALPHABET, Child, Parent, ParentDevice
from config.test_utils import PASSWORD, HabitoTestCase, child_client, create_parent, join, parent_client


class ParentModelTests(HabitoTestCase):
    def test_email_lowercase_and_password_hashed(self):
        parent = Parent.objects.create_user(email="Mom@Example.COM", password=PASSWORD)
        self.assertEqual(parent.email, "mom@example.com")
        self.assertNotEqual(parent.password, PASSWORD)
        self.assertTrue(parent.check_password(PASSWORD))

    def test_room_code_generated_and_unique(self):
        a = create_parent("a@example.com")
        b = create_parent("b@example.com")
        self.assertEqual(len(a.room_code), 6)
        self.assertTrue(set(a.room_code) <= set(ROOM_CODE_ALPHABET))
        self.assertNotEqual(a.room_code, b.room_code)
        for forbidden in "0O1IL":
            self.assertNotIn(forbidden, ROOM_CODE_ALPHABET)

    def test_default_timezone_is_utc(self):
        parent = Parent.objects.create_user(email="a@example.com", password=PASSWORD)
        self.assertEqual(parent.timezone, "UTC")

    def test_email_unique(self):
        create_parent("a@example.com")
        with self.assertRaises(IntegrityError):
            create_parent("A@example.com")


class RegisterTests(HabitoTestCase):
    url = reverse("auth-register")

    def test_register_with_email_and_password_only(self):
        response = self.client.post(self.url, {"email": "Mom@Example.com", "password": PASSWORD})
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["parent"]["email"], "mom@example.com")
        self.assertEqual(len(body["parent"]["room_code"]), 6)
        self.assertEqual(body["parent"]["timezone"], "UTC")
        self.assertNotIn("password", body["parent"])
        self.assertIn("access", body)
        self.assertIn("refresh", body)

    def test_register_with_timezone(self):
        response = self.client.post(self.url, {"email": "a@example.com", "password": PASSWORD, "timezone": "Asia/Tashkent"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["parent"]["timezone"], "Asia/Tashkent")

    def test_bad_timezone(self):
        response = self.client.post(self.url, {"email": "a@example.com", "password": PASSWORD, "timezone": "Mars/Olympus"})
        self.assertError(response, 400, "invalid_input")
        self.assertIn("timezone", response.json()["error"]["fields"])

    def test_duplicate_email(self):
        create_parent("mom@example.com")
        response = self.client.post(self.url, {"email": "MOM@example.com", "password": PASSWORD})
        self.assertError(response, 400, "invalid_input")
        self.assertIn("email", response.json()["error"]["fields"])

    def test_short_password(self):
        response = self.client.post(self.url, {"email": "a@example.com", "password": "short"})
        self.assertError(response, 400, "invalid_input")
        self.assertIn("password", response.json()["error"]["fields"])

    def test_access_token_works(self):
        response = self.client.post(self.url, {"email": "a@example.com", "password": PASSWORD})
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.json()['access']}")
        me = self.client.get(reverse("me"))
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["role"], "parent")
        self.assertEqual(me.json()["parent"]["email"], "a@example.com")


class LoginTests(HabitoTestCase):
    url = reverse("auth-login")

    def setUp(self):
        super().setUp()
        self.parent = create_parent(tz="UTC")

    def test_login_ok(self):
        response = self.client.post(self.url, {"email": "MOM@example.com", "password": PASSWORD})
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["parent"]["id"], str(self.parent.id))
        self.assertEqual(body["parent"]["room_code"], self.parent.room_code)
        self.assertIn("access", body)
        self.assertIn("refresh", body)

    def test_login_updates_timezone(self):
        response = self.client.post(self.url, {"email": "mom@example.com", "password": PASSWORD, "timezone": "Europe/Rome"})
        self.assertEqual(response.status_code, 200, response.content)
        self.parent.refresh_from_db()
        self.assertEqual(self.parent.timezone, "Europe/Rome")

    def test_login_bad_timezone(self):
        response = self.client.post(self.url, {"email": "mom@example.com", "password": PASSWORD, "timezone": "Nope"})
        self.assertError(response, 400, "invalid_input")

    def test_wrong_password(self):
        self.assertError(self.client.post(self.url, {"email": "mom@example.com", "password": "nope-nope"}), 401, "invalid_credentials")

    def test_unknown_email(self):
        self.assertError(self.client.post(self.url, {"email": "ghost@example.com", "password": PASSWORD}), 401, "invalid_credentials")

    def test_rate_limited_per_email(self):
        for _ in range(5):
            self.client.post(self.url, {"email": "mom@example.com", "password": "nope-nope"})
        self.assertError(self.client.post(self.url, {"email": "mom@example.com", "password": PASSWORD}), 429, "too_many_attempts")
        create_parent("dad@example.com")
        self.assertEqual(self.client.post(self.url, {"email": "dad@example.com", "password": PASSWORD}).status_code, 200)


class RefreshTests(HabitoTestCase):
    url = reverse("auth-refresh")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.refresh = str(RefreshToken.for_user(self.parent))

    def test_refresh_rotates(self):
        response = self.client.post(self.url, {"refresh": self.refresh})
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertIn("access", body)
        self.assertNotEqual(body["refresh"], self.refresh)
        self.assertError(self.client.post(self.url, {"refresh": self.refresh}), 401, "invalid_token")
        self.assertEqual(self.client.post(self.url, {"refresh": body["refresh"]}).status_code, 200)

    def test_garbage_and_expired(self):
        self.assertError(self.client.post(self.url, {"refresh": "not-a-token"}), 401, "invalid_token")
        token = RefreshToken.for_user(self.parent)
        token.set_exp(lifetime=-timedelta(seconds=1))
        self.assertError(self.client.post(self.url, {"refresh": str(token)}), 401, "invalid_token")

    def test_lifetimes(self):
        from django.conf import settings

        self.assertEqual(settings.SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"], timedelta(minutes=15))
        self.assertEqual(settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"], timedelta(days=90))


class LogoutTests(HabitoTestCase):
    url = reverse("auth-logout")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)
        self.refresh = str(RefreshToken.for_user(self.parent))

    def test_logout_blacklists_and_removes_device(self):
        ParentDevice.objects.create(parent=self.parent, apns_token="phone-1")
        ParentDevice.objects.create(parent=self.parent, apns_token="phone-2")
        response = self.client.post(self.url, {"refresh": self.refresh, "apns_token": "phone-1"})
        self.assertEqual(response.status_code, 204, response.content)
        self.assertEqual(BlacklistedToken.objects.count(), 1)
        self.assertEqual(list(ParentDevice.objects.values_list("apns_token", flat=True)), ["phone-2"])
        self.assertError(self.client.post(reverse("auth-refresh"), {"refresh": self.refresh}), 401, "invalid_token")

    def test_cannot_logout_someone_elses_token(self):
        other_refresh = str(RefreshToken.for_user(create_parent("dad@example.com")))
        self.assertError(self.client.post(self.url, {"refresh": other_refresh}), 400, "invalid_token")
        self.assertEqual(BlacklistedToken.objects.count(), 0)


class DeleteAccountTests(HabitoTestCase):
    def test_delete_removes_everything(self):
        from tasks.models import Task

        parent = create_parent()
        ParentDevice.objects.create(parent=parent, apns_token="phone-1")
        join(parent)
        Task.objects.create(parent=parent, title="T", repeat="daily")
        RefreshToken.for_user(parent)
        client = parent_client(parent)
        self.assertEqual(client.delete(reverse("auth-account")).status_code, 204)
        self.assertEqual(Parent.objects.count(), 0)
        self.assertEqual(ParentDevice.objects.count(), 0)
        self.assertEqual(Child.objects.count(), 0)
        self.assertEqual(Task.objects.count(), 0)
        self.assertEqual(OutstandingToken.objects.count(), 0)
        self.assertError(client.get(reverse("me")), 401)


class MeTests(HabitoTestCase):
    def test_parent(self):
        parent = create_parent()
        body = parent_client(parent).get(reverse("me")).json()
        self.assertEqual(body["role"], "parent")
        self.assertEqual(body["parent"]["room_code"], parent.room_code)
        self.assertEqual(body["parent"]["timezone"], "Asia/Tashkent")

    def test_child(self):
        parent = create_parent()
        body = child_client(join(parent)).get(reverse("me")).json()
        self.assertEqual(body["role"], "child")
        self.assertEqual(body["child"]["timezone"], "Asia/Tashkent")
        self.assertNotIn("parent", body)

    def test_anonymous_and_bad_token(self):
        self.assertError(self.client.get(reverse("me")), 401, "unauthorized")
        self.client.credentials(HTTP_AUTHORIZATION="Bearer nonsense")
        self.assertError(self.client.get(reverse("me")), 401, "unauthorized")
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + "0" * 64)
        self.assertError(self.client.get(reverse("me")), 401, "unauthorized")


class DeviceTests(HabitoTestCase):
    url = reverse("devices")

    def setUp(self):
        super().setUp()
        self.parent = create_parent()
        self.client = parent_client(self.parent)

    def test_register_device(self):
        response = self.client.post(self.url, {"apns_token": "abc123"})
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(ParentDevice.objects.get().parent, self.parent)

    def test_same_token_twice_is_idempotent(self):
        first = self.client.post(self.url, {"apns_token": "abc123"})
        second = self.client.post(self.url, {"apns_token": "abc123"})
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["id"], second.json()["id"])
        self.assertEqual(ParentDevice.objects.count(), 1)

    def test_token_moves_to_new_parent(self):
        ParentDevice.objects.create(parent=create_parent("dad@example.com"), apns_token="abc123")
        self.assertEqual(self.client.post(self.url, {"apns_token": "abc123"}).status_code, 200)
        self.assertEqual(ParentDevice.objects.get().parent, self.parent)

    def test_missing_token(self):
        self.assertError(self.client.post(self.url, {}), 400, "invalid_input")

    def test_child_forbidden(self):
        self.assertError(child_client(join(self.parent)).post(self.url, {"apns_token": "x"}), 403, "forbidden")
