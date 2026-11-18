from rest_framework import serializers

from .days import local_today
from .models import Completion, Repeat, Task


class TaskSerializer(serializers.ModelSerializer):
    """A task with the status of the day that matters (today, or its due date)."""

    status = serializers.CharField(read_only=True)
    done_at = serializers.DateTimeField(read_only=True, allow_null=True)

    class Meta:
        model = Task
        fields = ["id", "title", "repeat", "due_date", "status", "done_at", "created_at"]
        read_only_fields = fields


class TaskWriteSerializer(serializers.ModelSerializer):
    title = serializers.CharField(max_length=80)

    class Meta:
        model = Task
        fields = ["title", "repeat", "due_date"]

    def validate(self, attrs):
        if attrs["repeat"] == Repeat.DAILY and attrs.get("due_date") is not None:
            raise serializers.ValidationError({"due_date": "A daily task has no due date."})
        return attrs

    def create(self, validated_data):
        parent = self.context["parent"]
        if validated_data["repeat"] == Repeat.ONCE and validated_data.get("due_date") is None:
            validated_data["due_date"] = local_today(parent.tzinfo)
        return Task.objects.create(parent=parent, **validated_data)


class TodaySerializer(serializers.Serializer):
    date = serializers.DateField()
    tasks = TaskSerializer(many=True)


class CompletionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Completion
        fields = ["id", "task", "task_title", "local_date", "done_at"]
        read_only_fields = fields


class HistoryDaySerializer(serializers.Serializer):
    date = serializers.DateField()
    total = serializers.IntegerField()
    done = serializers.IntegerField()


class HistorySerializer(serializers.Serializer):
    from_date = serializers.DateField()
    to_date = serializers.DateField()
    days = HistoryDaySerializer(many=True)
