from datetime import date, timedelta

from django.db import IntegrityError, transaction
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsChild, IsParent, IsParentOrChild
from config.exceptions import ApiError, Conflict
from notifications.service import notify_task_done_after_commit

from .days import current_day, is_due_on, local_today, now, status_on
from .models import Completion, Task
from .serializers import (
    CompletionSerializer,
    HistorySerializer,
    TaskSerializer,
    TaskWriteSerializer,
    TodaySerializer,
)

MAX_RANGE_DAYS = 31
DEFAULT_RANGE_DAYS = 7


def _parent_of(user):
    """The parent whose room the caller is in."""
    return user if user.is_parent else user.parent


def _task_for(user, task_id) -> Task:
    task = Task.objects.filter(pk=task_id, parent=_parent_of(user)).first()
    if task is None:
        raise ApiError("not_found", "Task not found.", status.HTTP_404_NOT_FOUND)
    return task


def _with_status(parent, tasks, day_of) -> list[dict]:
    """Serialize tasks with the status of the day `day_of(task)` returns."""
    today = local_today(parent.tzinfo)
    pairs = [(task, day_of(task)) for task in tasks]
    done = {
        (c.task_id, c.local_date): c.done_at
        for c in Completion.objects.filter(parent=parent, task_id__in=[t.id for t in tasks])
    }
    result = []
    for task, day in pairs:
        done_at = done.get((task.id, day))
        task.status = status_on(task, day, today, done_at is not None)
        task.done_at = done_at
        result.append(task)
    return TaskSerializer(result, many=True).data


def _parse_range(request, tz) -> tuple[date, date]:
    today = local_today(tz)
    try:
        to_day = date.fromisoformat(request.query_params["to"]) if "to" in request.query_params else today
        from_day = (
            date.fromisoformat(request.query_params["from"])
            if "from" in request.query_params
            else to_day - timedelta(days=DEFAULT_RANGE_DAYS - 1)
        )
    except ValueError:
        raise ApiError("invalid_input", "from and to must be dates like 2026-11-17.")
    if from_day > to_day:
        raise ApiError("invalid_input", "from must not be after to.")
    if (to_day - from_day).days + 1 > MAX_RANGE_DAYS:
        raise ApiError("invalid_input", f"The range may cover at most {MAX_RANGE_DAYS} days.")
    return from_day, to_day


class TaskListView(APIView):
    """Parent: every task, each with the status of today (daily) or its due date (once)."""

    permission_classes = [IsParent]

    @extend_schema(responses={200: TaskSerializer(many=True)}, tags=["tasks"])
    def get(self, request):
        parent = request.user
        tz = parent.tzinfo
        today = local_today(tz)
        tasks = list(parent.tasks.all())
        return Response(_with_status(parent, tasks, lambda t: current_day(t, today, tz)))

    @extend_schema(request=TaskWriteSerializer, responses={201: TaskSerializer}, tags=["tasks"])
    def post(self, request):
        serializer = TaskWriteSerializer(data=request.data, context={"parent": request.user})
        serializer.is_valid(raise_exception=True)
        task = serializer.save()
        tz = request.user.tzinfo
        today = local_today(tz)
        data = _with_status(request.user, [task], lambda t: current_day(t, today, tz))[0]
        return Response(data, status=status.HTTP_201_CREATED)


class TaskDetailView(APIView):
    permission_classes = [IsParent]

    @extend_schema(responses={204: None}, tags=["tasks"])
    def delete(self, request, task_id):
        task = _task_for(request.user, task_id)
        task.delete()  # completions survive with task=null
        return Response(status=status.HTTP_204_NO_CONTENT)


class TodayView(APIView):
    """Both roles: the tasks due today, each open or done."""

    permission_classes = [IsParentOrChild]

    @extend_schema(responses={200: TodaySerializer}, tags=["tasks"])
    def get(self, request):
        parent = _parent_of(request.user)
        tz = parent.tzinfo
        today = local_today(tz)
        tasks = [t for t in parent.tasks.all() if is_due_on(t, today, tz)]
        return Response({"date": today, "tasks": _with_status(parent, tasks, lambda t: today)})


class TaskDoneView(APIView):
    """Child: marks today's occurrence done. A mark is final."""

    permission_classes = [IsChild]

    @extend_schema(request=None, responses={201: CompletionSerializer}, tags=["tasks"])
    def post(self, request, task_id):
        task = _task_for(request.user, task_id)
        parent = task.parent
        at = now()
        today = at.astimezone(parent.tzinfo).date()
        if not is_due_on(task, today, parent.tzinfo):
            raise Conflict("not_due_today", "This task is not due today.")
        try:
            with transaction.atomic():
                completion = Completion.objects.create(
                    task=task, parent=parent, task_title=task.title, local_date=today, done_at=at
                )
                notify_task_done_after_commit(completion)
        except IntegrityError:
            raise Conflict("already_done", "This task is already marked done today.")
        return Response(CompletionSerializer(completion).data, status=status.HTTP_201_CREATED)


_RANGE_PARAMS = [
    OpenApiParameter("from", str, description="First day, YYYY-MM-DD. Default: 6 days before `to`."),
    OpenApiParameter("to", str, description="Last day, YYYY-MM-DD. Default: today in the parent's timezone."),
]


class HistoryView(APIView):
    """Parent: for each day, newest first, how many tasks were due and how many were done."""

    permission_classes = [IsParent]

    @extend_schema(parameters=_RANGE_PARAMS, responses={200: HistorySerializer}, tags=["tasks"])
    def get(self, request):
        parent = request.user
        tz = parent.tzinfo
        from_day, to_day = _parse_range(request, tz)
        tasks = list(parent.tasks.all())
        completions = Completion.objects.filter(parent=parent, local_date__gte=from_day, local_date__lte=to_day)
        done_by_day: dict[date, list[Completion]] = {}
        for c in completions:
            done_by_day.setdefault(c.local_date, []).append(c)

        days = []
        day = to_day
        while day >= from_day:
            due_ids = {t.id for t in tasks if is_due_on(t, day, tz)}
            done = done_by_day.get(day, [])
            # A completion of a since-deleted task still counts as a task that day.
            extra = sum(1 for c in done if c.task_id not in due_ids)
            days.append({"date": day, "total": len(due_ids) + extra, "done": len(done)})
            day -= timedelta(days=1)
        return Response(HistorySerializer({"from_date": from_day, "to_date": to_day, "days": days}).data)
