from django.urls import path

from . import views

urlpatterns = [
    path("tasks", views.TaskListView.as_view(), name="tasks"),
    path("tasks/<uuid:task_id>", views.TaskDetailView.as_view(), name="task-detail"),
    path("tasks/<uuid:task_id>/done", views.TaskDoneView.as_view(), name="task-done"),
    path("today", views.TodayView.as_view(), name="today"),
    path("history", views.HistoryView.as_view(), name="history"),
]
