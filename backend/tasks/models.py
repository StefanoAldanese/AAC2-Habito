import uuid

from django.conf import settings
from django.db import models


class Repeat(models.TextChoices):
    ONCE = "once", "Once"
    DAILY = "daily", "Daily"


class Task(models.Model):
    """
    A task the parent set. A daily task is due every day from the day it was
    created; a one-time task is due on its due_date only.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    parent = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tasks")
    title = models.CharField(max_length=80)
    repeat = models.CharField(max_length=10, choices=Repeat.choices)
    due_date = models.DateField(null=True, blank=True)  # once only; defaults to the day it was created
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self) -> str:
        return self.title


class Completion(models.Model):
    """
    One row per task per local day the child marked done. A mark is final.
    Survives the task being deleted, so history stays correct.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    task = models.ForeignKey(Task, on_delete=models.SET_NULL, null=True, blank=True, related_name="completions")
    parent = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="completions")
    task_title = models.CharField(max_length=80)
    local_date = models.DateField()  # the day in the parent's timezone
    done_at = models.DateTimeField()

    class Meta:
        ordering = ["-done_at"]
        constraints = [
            models.UniqueConstraint(fields=["task", "local_date"], name="completion_task_day_unique"),
        ]
        indexes = [
            models.Index(fields=["parent", "local_date"]),
        ]

    def __str__(self) -> str:
        return f"{self.task_title} on {self.local_date}"
