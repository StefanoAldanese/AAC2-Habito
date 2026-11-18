from django.urls import path

from . import views

urlpatterns = [
    path("auth/register", views.RegisterView.as_view(), name="auth-register"),
    path("auth/login", views.LoginView.as_view(), name="auth-login"),
    path("auth/refresh", views.RefreshView.as_view(), name="auth-refresh"),
    path("auth/logout", views.LogoutView.as_view(), name="auth-logout"),
    path("auth/account", views.AccountView.as_view(), name="auth-account"),
    path("me", views.MeView.as_view(), name="me"),
    path("devices", views.DeviceView.as_view(), name="devices"),
    path("join", views.JoinView.as_view(), name="join"),
]
