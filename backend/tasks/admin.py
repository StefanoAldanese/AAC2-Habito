from django.contrib import admin

from .models import Completion, Task


@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display = ["title", "parent", "repeat", "due_date", "created_at"]
    list_filter = ["repeat"]


@admin.register(Completion)
class CompletionAdmin(admin.ModelAdmin):
    list_display = ["task_title", "parent", "local_date", "done_at"]
