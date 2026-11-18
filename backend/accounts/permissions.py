from rest_framework.permissions import BasePermission


class IsParent(BasePermission):
    """The request carries a parent access token."""

    def has_permission(self, request, view) -> bool:
        user = request.user
        return bool(user and user.is_authenticated and getattr(user, "is_parent", False))


class IsChild(BasePermission):
    """The request carries a child device token."""

    def has_permission(self, request, view) -> bool:
        user = request.user
        return bool(user and user.is_authenticated and getattr(user, "is_child", False))


class IsParentOrChild(BasePermission):
    def has_permission(self, request, view) -> bool:
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and (getattr(user, "is_parent", False) or getattr(user, "is_child", False))
        )
