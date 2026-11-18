"""JSON error pages for requests that never reach a DRF view."""

from django.http import JsonResponse


def not_found(request, exception=None):
    return JsonResponse({"error": {"code": "not_found", "message": "Not found."}}, status=404)


def server_error(request):
    return JsonResponse({"error": {"code": "server_error", "message": "Something went wrong."}}, status=500)


def bad_request(request, exception=None):
    return JsonResponse({"error": {"code": "invalid_input", "message": "Bad request."}}, status=400)


def permission_denied(request, exception=None):
    return JsonResponse({"error": {"code": "forbidden", "message": "Forbidden."}}, status=403)
