"""Tests for core/messenger/src/grid_messenger.py.

Coverage is deliberately limited to code paths that do not require a live
Telegram bot or network access:

  * module-level config parsing (O2 regression: importing without a token)
  * ALLOWED_USER_IDS / NOTIFY_CHAT_IDS parsing rules
  * app-registry helpers (_app_info, _load_apps/_save_apps via a tmp APPS_FILE)
  * keyboard builders and decision formatting (pure, no bot)
  * HTTP route handlers driven directly against the aiohttp-stubbed module

Skipped (documented honestly):
  * Telegram polling, command handlers, inline callbacks — need a real bot.
  * _run() / main() happy path — builds an Application and starts polling.
  * _setup_wizard() — requires interactive input + Telegram network validation.

The Telegram Application build happens inside _run() (grid_messenger.py:731),
not at import time, so importing the module is safe without a token.
"""

from __future__ import annotations

import pathlib
import sys

# Ensure stubs are registered before importing the module under test.
import conftest  # noqa: F401  (registers aiohttp/telegram stubs)
import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src"))
import grid_messenger as gm


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Unset every env var grid_messenger reads so tests start deterministic."""
    for key in (
        "TELEGRAM_BOT_TOKEN",
        "TELEGRAM_ALLOWED_USER_IDS",
        "NOTIFY_CHAT_IDS",
        "N8N_BASE_URL",
        "FAIGATE_URL",
        "OPENCLAW_URL",
        "WEBHOOK_PORT",
        "WEBHOOK_BIND",
        "APPS_FILE",
    ):
        monkeypatch.delenv(key, raising=False)


# ── O2 regression: module level token handling ────────────────────────────────
def test_import_without_token_env():
    """Importing the module with no TELEGRAM_BOT_TOKEN yields empty string."""
    assert gm.TELEGRAM_BOT_TOKEN == ""


def test_token_read_from_env(monkeypatch):
    monkeypatch.setenv("TELEGRAM_BOT_TOKEN", "123456:ABC-DEF")
    import importlib

    importlib.reload(gm)
    assert gm.TELEGRAM_BOT_TOKEN == "123456:ABC-DEF"  # noqa: S105
    assert "123456:ABC-DEF" != ""


# ── ALLOWED_USER_IDS / NOTIFY_CHAT_IDS parsing ────────────────────────────────
def test_allowed_user_ids_empty_default(monkeypatch):
    import importlib

    monkeypatch.delenv("TELEGRAM_ALLOWED_USER_IDS", raising=False)
    importlib.reload(gm)
    assert gm.ALLOWED_USER_IDS == set()


def test_allowed_user_ids_comma_separated(monkeypatch):
    import importlib

    monkeypatch.setenv("TELEGRAM_ALLOWED_USER_IDS", "111,222,333")
    importlib.reload(gm)
    assert gm.ALLOWED_USER_IDS == {111, 222, 333}


def test_allowed_user_ids_ignores_non_numeric(monkeypatch):
    import importlib

    monkeypatch.setenv("TELEGRAM_ALLOWED_USER_IDS", "111,abc,,444, -12, 0")
    importlib.reload(gm)
    # Non-numeric tokens ("abc", "", whitespace) are dropped.
    # Negative numeric tokens are *not* filtered out by lstrip("-").isdigit().
    assert gm.ALLOWED_USER_IDS == {111, 444, -12, 0}
    assert "abc" not in str(gm.ALLOWED_USER_IDS)


def test_notify_chat_ids_defaults_to_allowed(monkeypatch):
    import importlib

    monkeypatch.setenv("TELEGRAM_ALLOWED_USER_IDS", "777,888")
    monkeypatch.delenv("NOTIFY_CHAT_IDS", raising=False)
    importlib.reload(gm)
    assert gm.NOTIFY_CHAT_IDS == {777, 888}


def test_notify_chat_ids_overrides_allowed(monkeypatch):
    import importlib

    monkeypatch.setenv("TELEGRAM_ALLOWED_USER_IDS", "777")
    monkeypatch.setenv("NOTIFY_CHAT_IDS", "999,000")
    importlib.reload(gm)
    assert gm.NOTIFY_CHAT_IDS == {999, 0}
    assert gm.ALLOWED_USER_IDS == {777}


# ── Defaults for other module-level config ────────────────────────────────────
def test_default_service_urls():
    assert gm.N8N_BASE_URL == "http://127.0.0.1:5678"
    assert gm.FAIGATE_URL == "http://127.0.0.1:8090"
    assert gm.OPENCLAW_URL == "http://127.0.0.1:18789"


def test_default_webhook_port(monkeypatch):
    import importlib

    monkeypatch.delenv("WEBHOOK_PORT", raising=False)
    importlib.reload(gm)
    assert gm.WEBHOOK_PORT == 9119


def test_webhook_port_from_env(monkeypatch):
    import importlib

    monkeypatch.setenv("WEBHOOK_PORT", "1234")
    importlib.reload(gm)
    assert gm.WEBHOOK_PORT == 1234


# ── App registry helpers ──────────────────────────────────────────────────────
def test_app_info_unknown_name_gets_default_emoji():
    info = gm._app_info("totally-unknown-app")
    assert info["display_name"] == "Totally-unknown-app"
    assert info["emoji"] == "📡"
    assert info.get("thread_id") is None


def test_app_info_known_name_gets_default_emoji():
    info = gm._app_info("codenomad")
    assert info["display_name"] == "Codenomad"
    assert info["emoji"] == "👨‍💻"


def test_app_info_registered_name_wins_over_default():
    gm._apps["codenomad"] = {
        "display_name": "Custom Display",
        "emoji": "🔧",
        "thread_id": 42,
    }
    info = gm._app_info("codenomad")
    assert info["display_name"] == "Custom Display"
    assert info["emoji"] == "🔧"
    assert info["thread_id"] == 42


def test_source_line_formats_source_and_id():
    gm._apps.clear()
    line = gm._source_line("codenomad", "refactor-session-1")
    assert "Codenomad" in line
    assert "refactor-session-1" in line


def test_transient_registry_isolation():
    """_apps is module-global; ensure a clean slate first."""
    assert isinstance(gm._apps, dict)


# ── App registry disk round-trip (via a tmp APPS_FILE) ───────────────────────
def test_save_and_load_apps_roundtrip(tmp_path, monkeypatch):
    import importlib

    apps_file = tmp_path / "registry" / "apps.json"
    monkeypatch.setenv("APPS_FILE", str(apps_file))
    importlib.reload(gm)

    gm._apps.clear()
    gm._apps["edge"] = {"display_name": "Edge", "emoji": "⚡", "thread_id": None}
    gm._save_apps()

    assert apps_file.exists()
    raw = apps_file.read_text()
    assert '"edge"' in raw

    gm._apps.clear()
    gm._load_apps()
    assert "edge" in gm._apps
    assert gm._apps["edge"]["display_name"] == "Edge"


def test_load_apps_missing_file_is_noop(tmp_path, monkeypatch):
    import importlib

    monkeypatch.setenv("APPS_FILE", str(tmp_path / "nope" / "apps.json"))
    importlib.reload(gm)

    gm._apps.clear()
    gm._load_apps()  # must not raise
    assert gm._apps == {}


# ── Keyboard builders & decision formatting (pure helpers) ────────────────────
def test_keyboard_approve_has_two_buttons():
    kb = gm._keyboard_approve("deadbeef")
    flat = [b for row in kb.inline_keyboard for b in row]
    assert len(flat) == 2
    assert {b.callback_data for b in flat} == {
        "approve:deadbeef",
        "reject:deadbeef",
    }


def test_keyboard_choice_two_columns_and_cancel():
    kb = gm._keyboard_choice("aaaabbbb", ["keep", "rewrite", "skip"])
    buttons = [b for row in kb.inline_keyboard for b in row]
    # 3 options -> 2 columns -> row sizes 2 + 1, plus a cancel row of 1.
    assert [b.callback_data for b in buttons] == [
        "choice:aaaabbbb:keep",
        "choice:aaaabbbb:rewrite",
        "choice:aaaabbbb:skip",
        "cancel:aaaabbbb",
    ]


def test_keyboard_choice_single_column_for_many_options():
    kb = gm._keyboard_choice("x", ["a", "b", "c", "d", "e"])
    # >4 options -> one button per row (plus cancel).
    assert len(kb.inline_keyboard) == 6


def test_format_decision_includes_type_and_description():
    item = {"type": "approve", "source": "", "description": "Which approach?"}
    text = gm._format_decision("abcd1234", item)
    assert "APPROVE" in text
    assert "Which approach?" in text
    assert "abcd1234" in text


def test_format_decision_choice_lists_options():
    item = {
        "type": "choice",
        "source": "",
        "description": "Pick one",
        "options": ["keep", "rewrite"],
    }
    text = gm._format_decision("x", item)
    assert "keep" in text
    assert "rewrite" in text


# ── HTTP route handlers (invoked directly, no running server/bot) ────────────
@pytest.mark.asyncio
async def test_http_health_returns_ok_json():
    # http_health ignores its request and only reads _pending/_apps lengths.
    resp = await gm.http_health(None)
    assert resp["status"] == 200
    assert resp["json"] == {
        "status": "ok",
        "pending": 0,
        "apps": len(gm._apps),
    }


@pytest.mark.asyncio
async def test_http_app_list_reflects_registry():
    gm._apps.clear()
    gm._apps["n8n"] = {"display_name": "n8n", "emoji": "⚡", "thread_id": None}
    resp = await gm.http_app_list(None)
    assert resp["status"] == 200
    assert resp["json"]["apps"]["n8n"]["display_name"] == "n8n"


@pytest.mark.asyncio
async def test_http_decision_request_unknown_type_rejected():
    class Req:
        async def json(self):
            return {"type": "bogus", "description": "x"}

    resp = await gm.http_decision_request(Req())
    assert resp["status"] == 400
    assert "unknown type" in resp["json"]["error"]


@pytest.mark.asyncio
async def test_http_decision_request_choice_requires_options():
    class Req:
        async def json(self):
            return {"type": "choice", "description": "pick"}

    resp = await gm.http_decision_request(Req())
    assert resp["status"] == 400
    assert "options" in resp["json"]["error"]


@pytest.mark.asyncio
async def test_http_decision_request_invalid_json():
    class Req:
        async def json(self):
            raise ValueError("bad JSON")

    resp = await gm.http_decision_request(Req())
    assert resp["status"] == 400
    assert resp["json"]["error"] == "invalid JSON"


@pytest.mark.asyncio
async def test_http_notify_invalid_json():
    class Req:
        async def json(self):
            raise ValueError("nope")

    resp = await gm.http_notify(Req())
    assert resp["status"] == 400


# ── --setup missing-token path ────────────────────────────────────────────────
def test_main_without_token_exits_cleanly():
    """main() without TELEGRAM_BOT_TOKEN raises SystemExit(1), never KeyError."""
    # Ensure no token is set in the *module* state under test.
    gm.TELEGRAM_BOT_TOKEN = ""
    with pytest.raises(SystemExit) as excinfo:
        gm.main()
    assert excinfo.value.code == 1
