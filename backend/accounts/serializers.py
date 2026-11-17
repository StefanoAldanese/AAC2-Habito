from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

from .models import Child, Parent, ParentDevice, validate_timezone


class ParentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Parent
        fields = ["id", "email", "room_code", "timezone", "created_at"]
        read_only_fields = fields


class TokenPairSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class AuthResponseSerializer(serializers.Serializer):
    """Returned by register and login."""

    parent = ParentSerializer()
    access = serializers.CharField()
    refresh = serializers.CharField()


def issue_tokens(parent: Parent) -> dict:
    refresh = RefreshToken.for_user(parent)
    return {"access": str(refresh.access_token), "refresh": str(refresh)}


class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    password = serializers.CharField(write_only=True, min_length=8, max_length=128)
    # Sent silently by the app (TimeZone.current.identifier); decides when a day starts.
    timezone = serializers.CharField(max_length=64, required=False, validators=[validate_timezone])

    def validate_email(self, value: str) -> str:
        value = value.strip().lower()
        if Parent.objects.filter(email=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_password(self, value: str) -> str:
        validate_password(value)
        return value

    def create(self, validated_data: dict) -> Parent:
        return Parent.objects.create_user(**validated_data)


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    password = serializers.CharField(write_only=True, max_length=128)
    timezone = serializers.CharField(max_length=64, required=False, validators=[validate_timezone])

    def validate(self, attrs: dict) -> dict:
        email = attrs["email"].strip().lower()
        parent = authenticate(self.context.get("request"), username=email, password=attrs["password"])
        if parent is None:
            raise serializers.ValidationError("Email or password is wrong.")
        attrs["parent"] = parent
        return attrs


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()
    apns_token = serializers.CharField(max_length=255, required=False, allow_blank=True)


class ChildSerializer(serializers.ModelSerializer):
    timezone = serializers.CharField(source="parent.timezone", read_only=True)

    class Meta:
        model = Child
        fields = ["id", "timezone", "joined_at"]
        read_only_fields = fields


class MeResponseSerializer(serializers.Serializer):
    """`parent` is set for a parent token, `child` for a child token."""

    role = serializers.ChoiceField(choices=["parent", "child"])
    parent = ParentSerializer(required=False)
    child = ChildSerializer(required=False)


class ParentDeviceSerializer(serializers.ModelSerializer):
    # Declared explicitly so the model's unique check does not reject a phone
    # registering the same token again; the view handles that case.
    apns_token = serializers.CharField(max_length=255)

    class Meta:
        model = ParentDevice
        fields = ["id", "apns_token", "created_at", "last_used_at"]
        read_only_fields = ["id", "created_at", "last_used_at"]


class JoinSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=16)

    def validate_code(self, value: str) -> str:
        return value.strip().upper().replace(" ", "").replace("-", "")


class JoinResponseSerializer(serializers.Serializer):
    child_token = serializers.CharField()
    child = ChildSerializer()
