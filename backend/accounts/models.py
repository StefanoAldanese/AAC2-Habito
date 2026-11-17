import hashlib
import secrets
import uuid
import zoneinfo

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.core.exceptions import ValidationError
from django.db import models

# No 0/O, 1/I/L so a code read aloud or written down cannot be misread.
ROOM_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
ROOM_CODE_LENGTH = 6
CHILD_TOKEN_BYTES = 32


def validate_timezone(value: str) -> None:
    try:
        zoneinfo.ZoneInfo(value)
    except (zoneinfo.ZoneInfoNotFoundError, ValueError, IsADirectoryError):
        raise ValidationError(f"'{value}' is not a known IANA timezone.")


def generate_room_code() -> str:
    return "".join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LENGTH))


def generate_child_token() -> str:
    return secrets.token_hex(CHILD_TOKEN_BYTES)


def hash_child_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class ParentManager(BaseUserManager):
    use_in_migrations = True

    def _create(self, email: str, password: str | None, **extra):
        if not email:
            raise ValueError("An email address is required")
        email = self.normalize_email(email).lower()
        parent = self.model(email=email, **extra)
        parent.set_password(password)
        if not parent.room_code:
            parent.room_code = self._free_room_code()
        parent.save(using=self._db)
        return parent

    def _free_room_code(self) -> str:
        for _ in range(20):
            code = generate_room_code()
            if not self.model.objects.filter(room_code=code).exists():
                return code
        raise RuntimeError("could not find a free room code")  # pragma: no cover

    def create_user(self, email: str, password: str | None = None, **extra):
        extra.setdefault("is_staff", False)
        extra.setdefault("is_superuser", False)
        return self._create(email, password, **extra)

    def create_superuser(self, email: str, password: str | None = None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self._create(email, password, **extra)


class Parent(AbstractBaseUser, PermissionsMixin):
    """
    A parent account. Logs in with email and password; the hash lives in the
    `password` column Django manages and is never returned by the API.

    Each parent is one room: a permanent room code the child joins with, and
    the timezone that decides when a day starts for daily tasks.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(max_length=254, unique=True)
    room_code = models.CharField(max_length=ROOM_CODE_LENGTH, unique=True)
    timezone = models.CharField(max_length=64, default="UTC", validators=[validate_timezone])
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    objects = ParentManager()

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        verbose_name = "parent"

    def __str__(self) -> str:
        return self.email

    @property
    def tzinfo(self) -> zoneinfo.ZoneInfo:
        return zoneinfo.ZoneInfo(self.timezone)

    @property
    def is_parent(self) -> bool:
        return True

    @property
    def is_child(self) -> bool:
        return False


class ParentDevice(models.Model):
    """One row per parent phone that allowed notifications."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    parent = models.ForeignKey(Parent, on_delete=models.CASCADE, related_name="devices")
    apns_token = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self) -> str:
        return f"device {self.id} of {self.parent_id}"


class Child(models.Model):
    """The child device joined to a parent's room. Holds no personal data."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    parent = models.OneToOneField(Parent, on_delete=models.CASCADE, related_name="child")
    device_token_hash = models.CharField(max_length=64, unique=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"child of {self.parent_id}"

    # Lets views treat a child like request.user without it being a Django user.
    @property
    def is_authenticated(self) -> bool:
        return True

    @property
    def is_anonymous(self) -> bool:
        return False

    @property
    def is_parent(self) -> bool:
        return False

    @property
    def is_child(self) -> bool:
        return True
