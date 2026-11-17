"""Error format, OpenAPI docs and the full endpoint list."""

from django.test import override_settings
from django.urls import reverse

from config.test_utils import HabitoTestCase, create_parent, parent_client

ENDPOINTS = {
    ("post", "/api/v1/auth/register"),
    ("post", "/api/v1/auth/login"),
    ("post", "/api/v1/auth/refresh"),
    ("post", "/api/v1/auth/logout"),
    ("delete", "/api/v1/auth/account"),
    ("get", "/api/v1/me"),
    ("post", "/api/v1/devices"),
    ("post", "/api/v1/join"),
    ("get", "/api/v1/tasks"),
    ("post", "/api/v1/tasks"),
    ("delete", "/api/v1/tasks/{task_id}"),
    ("post", "/api/v1/tasks/{task_id}/done"),
    ("get", "/api/v1/today"),
    ("get", "/api/v1/history"),
}


class ErrorFormatTests(HabitoTestCase):
    def test_validation_error_shape(self):
        response = self.client.post(reverse("auth-register"), {"email": "nope"})
        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(set(body), {"error"})
        self.assertEqual(body["error"]["code"], "invalid_input")
        self.assertIn("email", body["error"]["fields"])

    def test_unauthorized_shape(self):
        response = self.client.get(reverse("me"))
        self.assertEqual(response.json(), {"error": {"code": "unauthorized", "message": "Missing or expired token."}})
        self.assertTrue(response.headers.get("WWW-Authenticate"))

    def test_method_not_allowed(self):
        response = parent_client(create_parent()).put(reverse("me"), {})
        self.assertEqual(response.status_code, 405)
        self.assertEqual(response.json()["error"]["code"], "method_not_allowed")

    @override_settings(DEBUG=False)
    def test_unknown_url_is_json_404(self):
        response = self.client.get("/api/v1/nothing-here")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "not_found")

    def test_invalid_json_body(self):
        response = self.client.generic("POST", reverse("auth-login"), data="{not json", content_type="application/json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "invalid_input")


class OpenApiTests(HabitoTestCase):
    def test_docs_page(self):
        response = self.client.get("/api/docs/")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"swagger", response.content.lower())

    def test_schema_lists_exactly_the_14_endpoints(self):
        response = self.client.get("/api/schema/", HTTP_ACCEPT="application/vnd.oai.openapi+json")
        self.assertEqual(response.status_code, 200, response.content[:300])
        paths = response.json()["paths"]
        found = {(method, path) for path, ops in paths.items() for method in ops}
        self.assertEqual(found, ENDPOINTS)
        self.assertEqual(len(ENDPOINTS), 14)
