"""
Turns every error into the shape the spec promises:

    { "error": { "code": "invalid_code", "message": "..." } }

Validation errors also carry a "fields" map so the app can show which
input was wrong.
"""

from django.core.exceptions import PermissionDenied
from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler


class ApiError(exceptions.APIException):
    """An error with an explicit code, e.g. ApiError("code_expired", "...", 409)."""

    def __init__(self, code: str, message: str, status_code: int = status.HTTP_400_BAD_REQUEST):
        self.status_code = status_code
        self.code = code
        self.detail = message


class Conflict(ApiError):
    def __init__(self, code: str, message: str):
        super().__init__(code, message, status.HTTP_409_CONFLICT)


_DEFAULT_CODES = {
    status.HTTP_400_BAD_REQUEST: "invalid_input",
    status.HTTP_401_UNAUTHORIZED: "unauthorized",
    status.HTTP_403_FORBIDDEN: "forbidden",
    status.HTTP_404_NOT_FOUND: "not_found",
    status.HTTP_405_METHOD_NOT_ALLOWED: "method_not_allowed",
    status.HTTP_409_CONFLICT: "conflict",
    status.HTTP_415_UNSUPPORTED_MEDIA_TYPE: "unsupported_media_type",
    status.HTTP_429_TOO_MANY_REQUESTS: "too_many_attempts",
}


def _flatten(detail):
    """Reduce a DRF error detail (str, list or dict) to one human sentence."""
    if isinstance(detail, dict):
        for value in detail.values():
            text = _flatten(value)
            if text:
                return text
        return ""
    if isinstance(detail, list):
        for value in detail:
            text = _flatten(value)
            if text:
                return text
        return ""
    return str(detail)


def exception_handler(exc, context):
    if isinstance(exc, Http404):
        exc = exceptions.NotFound()
    elif isinstance(exc, PermissionDenied):
        exc = exceptions.PermissionDenied()

    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    status_code = response.status_code
    body = {"code": _DEFAULT_CODES.get(status_code, "error"), "message": ""}

    if isinstance(exc, ApiError):
        body["code"] = exc.code
        body["message"] = str(exc.detail)
    elif isinstance(exc, exceptions.ValidationError):
        body["message"] = _flatten(exc.detail) or "Invalid input."
        if isinstance(exc.detail, dict):
            body["fields"] = exc.detail
    elif isinstance(exc, exceptions.Throttled):
        body["message"] = "Too many attempts. Try again later."
        if exc.wait is not None:
            body["retry_after"] = int(exc.wait)
    elif isinstance(exc, (exceptions.NotAuthenticated, exceptions.AuthenticationFailed)):
        body["message"] = "Missing or expired token."
    else:
        body["message"] = _flatten(exc.detail) if hasattr(exc, "detail") else str(exc)

    return Response({"error": body}, status=status_code, headers=response.headers)
