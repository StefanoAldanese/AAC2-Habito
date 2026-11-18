from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import Child, Parent, ParentDevice


@admin.register(Parent)
class ParentAdmin(UserAdmin):
    ordering = ["email"]
    list_display = ["email", "room_code", "timezone", "is_staff", "created_at"]
    search_fields = ["email", "room_code"]
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Room", {"fields": ("room_code", "timezone")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
    )
    add_fieldsets = ((None, {"classes": ("wide",), "fields": ("email", "password1", "password2")}),)


@admin.register(ParentDevice)
class ParentDeviceAdmin(admin.ModelAdmin):
    list_display = ["id", "parent", "created_at", "last_used_at"]


@admin.register(Child)
class ChildAdmin(admin.ModelAdmin):
    list_display = ["id", "parent", "joined_at"]
