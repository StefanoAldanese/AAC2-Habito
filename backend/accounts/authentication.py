"""
Authenticates a child device.

The child's token is 32 random bytes as 64 hex characters. Only its SHA-256
hash is stored. This class runs before JWT authentication: a 64-hex token is
looked up here, anything else is left for the JWT class.
"""

import re

from rest_framework import exceptions
from rest_framework.authentication import BaseAuthentication, get_authorization_header

from .models import Child, hash_child_token

_HEX_TOKEN = re.compile(r"^[0-9a-f]{64}$")


class ChildTokenAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        header = get_authorization_header(request).split()
        if len(header) != 2 or header[0].lower() != self.keyword.lower().encode():
            return None
        try:
            token = header[1].decode()
        except UnicodeError:
            return None
        if not _HEX_TOKEN.match(token):
            return None  # Probably a parent JWT; let the next class try.

        child = Child.objects.select_related("parent").filter(device_token_hash=hash_child_token(token)).first()
        if child is None:
            raise exceptions.AuthenticationFailed("Child token is invalid or revoked.")
        return (child, token)

    def authenticate_header(self, request):
        return self.keyword


try:  # Tell drf-spectacular how this scheme shows up in the OpenAPI file.
    from drf_spectacular.extensions import OpenApiAuthenticationExtension

    class ChildTokenScheme(OpenApiAuthenticationExtension):
        target_class = "accounts.authentication.ChildTokenAuthentication"
        name = "childToken"

        def get_security_definition(self, auto_schema):
            return {
                "type": "http",
                "scheme": "bearer",
                "description": "The 64-character child_token returned by POST /join.",
            }

except ImportError:  # pragma: no cover
    pass
