"""Pytest fixtures for grid-messenger tests.

grid_messenger.py imports ``aiohttp`` (web + ClientSession) and the
``python-telegram-bot`` library at module top level. Tests must run without a
live Telegram bot and, in lean CI environments, without either dependency
installed. This conftest installs minimal in-process stubs for both libraries
*before* the module under test is imported, so that importing the module and
exercising its pure/HTTP logic works regardless of the environment.

The stubs are installed *only* when the real library cannot be imported: if
``aiohttp`` or ``python-telegram-bot`` is actually importable, it is left in
place and the tests exercise the real implementation. Only the symbols that
grid_messenger.py (and the tests) actually touch are stubbed. Anything
requiring a live network or a real bot is out of scope.
"""

from __future__ import annotations

import sys
import types


# ── Stub: `telegram` (python-telegram-bot) ────────────────────────────────────
def _make_telegram_module() -> types.ModuleType:
    telegram = types.ModuleType("telegram")
    telegram.ext = types.ModuleType("telegram.ext")
    # Register as a package so `from telegram.ext import X` resolves both the
    # ``telegram`` and the ``telegram.ext`` submodule imports.
    telegram.ext.__package__ = "telegram.ext"
    telegram.ext.__path__ = []
    telegram.__version__ = "0.0.0-stub"

    # InlineKeyboardButton(text=..., callback_data=...) is a simple data object.
    class InlineKeyboardButton:
        def __init__(self, text, callback_data=None, **kwargs):
            self.text = text
            self.callback_data = callback_data

    # InlineKeyboardMarkup wraps rows of buttons; rows is a list of lists.
    class InlineKeyboardMarkup:
        def __init__(self, keyboard):
            self.inline_keyboard = keyboard

    # Update is used only by Telegram command handlers (not tested without a bot).
    class Update:
        pass

    # Application.builder().token(TOKEN).build() is only called inside _run().
    class _Builder:
        def token(self, _token):
            return self

        def build(self):
            return Application()

    class Application:
        @classmethod
        def builder(cls):
            return _Builder()

    telegram.InlineKeyboardButton = InlineKeyboardButton
    telegram.InlineKeyboardMarkup = InlineKeyboardMarkup
    telegram.Update = Update
    telegram.ext.Application = Application
    telegram.ext.CallbackQueryHandler = lambda *a, **k: object()
    telegram.ext.CommandHandler = lambda *a, **k: object()
    telegram.ext.ContextTypes = types.SimpleNamespace(DEFAULT_TYPE=object())
    telegram.ext.MessageHandler = lambda *a, **k: object()
    telegram.ext.filters = types.SimpleNamespace(TEXT=object(), COMMAND=object())
    return telegram


# ── Stub: `aiohttp` (web Application + ClientSession) ─────────────────────────
def _make_aiohttp_module() -> types.ModuleType:
    aiohttp = types.ModuleType("aiohttp")
    aiohttp.web = types.ModuleType("aiohttp.web")

    # ClientSession/ClientTimeout appear only on network code paths (status/notify
    # callbacks); provide inert stand-ins so those symbols resolve on collection.
    class ClientSession:
        def __init__(self, *a, **k):
            pass

        async def get(self, *a, **k):
            raise NotImplementedError("network disabled in tests")

        async def post(self, *a, **k):
            raise NotImplementedError("network disabled in tests")

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

    class ClientTimeout:
        def __init__(self, total=None):
            self.total = total

    # Minimal stand-in for aiohttp.web.Response. It exposes the same surface the
    # tests touch (``.status`` and ``await .text()``) so handler assertions read
    # identically against the stub and against a real aiohttp install.
    class Response:
        def __init__(self, *, status=200, body=b"", **kwargs):
            self.status = status
            self.body = body

        async def text(self, *a, **k):
            return self.body.decode("utf-8")

    def _json_response(data, **kwargs):
        import json as _json

        status = kwargs.get("status", 200)
        return Response(status=status, body=_json.dumps(data).encode("utf-8"))

    aiohttp.ClientSession = ClientSession
    aiohttp.ClientTimeout = ClientTimeout
    aiohttp.web.Response = Response
    aiohttp.web.json_response = _json_response
    aiohttp.web.Application = lambda *a, **k: {}
    aiohttp.web.AppRunner = object
    aiohttp.web.TCPSite = object
    return aiohttp


def _install_if_missing(name: str, factory) -> None:
    try:
        __import__(name)
    except ImportError:
        sys.modules[name] = factory()


def _install_telegram_if_missing() -> None:
    try:
        __import__("telegram")
        __import__("telegram.ext")
    except ImportError:
        tg = _make_telegram_module()
        sys.modules["telegram"] = tg
        sys.modules["telegram.ext"] = tg.ext


_install_telegram_if_missing()
_install_if_missing("aiohttp", _make_aiohttp_module)
