# Habito Backend — Technical Specification (v1, simplified)

Nov 17, 2026 · @Sanatbek

This replaces the earlier, larger spec (still in git history). v1 is deliberately small: the parent creates tasks and gets notified; the child marks tasks done. Everything else, the caterpillar, apples, butterflies, lives in the app.

## Overview

A parent signs up with an email and a password. That account **is** the room: it has a permanent six-letter room code. The child's device enters that code once and from then on can read today's tasks and mark them done. When a task is marked done, every phone the parent registered gets a push.

The server is responsible for:

- Parent register, login that lasts across launches, logout, account deletion.
- A room code per parent, shown in the parent app.
- Letting a child device join with the code, with no account and no personal data.
- Storing tasks the parent creates: one-time or daily.
- Today's task list with each task's status.
- Recording a done mark and pushing a notification to the parent.
- A history: for each day, how many tasks were due and how many were done.

## Roles

| Role | How they get access | Identified by |
| --- | --- | --- |
| Parent | Register or log in with email and password | JWT access token (15 min) plus refresh token (90 days, rotated on use), both in the Keychain |
| Child | Enters the parent's room code | 64-character device token issued at join, in the Keychain; the server stores only its hash |

One parent is one room with one child device. Joining again with the same code replaces the previous child device.

## Data model

| Entity | Fields |
| --- | --- |
| Parent | id, email (unique, lowercase), password hash, room_code (6 chars, unique, permanent), timezone (IANA, default UTC), created_at |
| ParentDevice | id, parent, apns_token (unique), created_at, last_used_at |
| Child | id, parent (one-to-one), device_token_hash, joined_at |
| Task | id, parent, title (max 80), repeat (`once` or `daily`), due_date (once only; defaults to the day it was created), created_at |
| Completion | id, task (null if the task was deleted), parent, task_title (copied), local_date, done_at. Unique per task and day |

All ids are UUIDs, timestamps are ISO 8601 UTC. "Today" is computed in the parent's timezone, which the parent app sends silently at register and login.

## Task rules

- A **daily** task is due every day from the day it was created. It is `open` today until marked, `done` once marked, and `missed` for any past day with no mark.
- A **one-time** task is due on its `due_date` only: `upcoming` before, `open` on the day, `done` or `missed` after.
- A done mark is final. There is no undo and no parent confirmation.
- Deleting a task keeps its past completions, so history does not change.

## API endpoints

14 endpoints under `/api/v1`. All but register, login, refresh and join need `Authorization: Bearer <token>`.

| Method | Path | Who | What it does |
| --- | --- | --- | --- |
| POST | /auth/register | anyone | `{email, password, timezone?}` → parent (with room_code), access, refresh |
| POST | /auth/login | anyone | `{email, password, timezone?}` → same. 5 tries per email per 15 min |
| POST | /auth/refresh | refresh token | New access and refresh pair; the old refresh token dies |
| POST | /auth/logout | parent | `{refresh, apns_token?}`: revokes the refresh token, removes that phone's push token |
| DELETE | /auth/account | parent | Deletes the parent, phones, child, tasks and completions |
| GET | /me | parent, child | Who is calling. Parent: email, room_code, timezone. Child: timezone |
| POST | /devices | parent | `{apns_token}`: this phone receives pushes |
| POST | /join | anyone | `{code}` → `child_token`. Replaces any previous child device. 10 tries per IP per 15 min |
| GET | /tasks | parent | All tasks with status and done_at (today for daily, the due date for once) |
| POST | /tasks | parent | `{title, repeat, due_date?}` → the task |
| DELETE | /tasks/{task_id} | parent | Deletes the task; completions stay |
| GET | /today | parent, child | `{date, tasks: [...]}`, the tasks due today, each `open` or `done` |
| POST | /tasks/{task_id}/done | child | Marks today's occurrence done, pushes to the parent. 409 if already done or not due today |
| GET | /history?from=&to= | parent | `{days: [{date, total, done}]}` newest first. Default last 7 days, at most 31 |

### Errors

`{ "error": { "code": "...", "message": "..." } }`, with `fields` added on validation errors. Statuses: 400 invalid input, 401 missing or expired token, 403 wrong role, 404 not found or not yours, 409 conflict (`already_done`, `not_due_today`), 429 too many attempts.

## Security and privacy

- HTTPS only outside development.
- Passwords at least 8 characters, hashed with Django's default hasher.
- Child token: 32 random bytes, only the SHA-256 hash stored; revoked when a new device joins or the account is deleted.
- Child data: none. No name, no email.
- The room code is permanent in v1. Anyone who learns it can join and replace the child device. Acceptable for a family app's first version; a "new code" endpoint can be added later without changing the data model.
- Push messages carry only the task title.

## Out of scope for v1

Hourly tasks, editing or pausing tasks, undo, multiple children per parent, rotating the room code, a per-task completed list, password reset by email, any game state on the server.
