#!/usr/bin/env python3
"""
grid-messenger — fusionAIze Grid Communication Bridge
Telegram bot + HTTP webhook server for grid-core decision flows.

Decision types
--------------
approve   Binary Approve / Reject (default)
choice    N labelled buttons  — options: ["openclaw","codenomad","claude-cli"]
input     Free-text reply     — user sends a message back to the bot

HTTP endpoints (127.0.0.1:WEBHOOK_PORT)
----------------------------------------
POST /decision/request    Push a decision task from any registered app
POST /notify              Plain notification
GET  /health              Status + pending count
POST /app/register        Register an app (name, display_name, emoji, thread_id)
GET  /app/list            List registered apps

/decision/request payload
--------------------------
{
  "source":       "codenomad",          // registered app name (or free-form)
  "source_id":    "refactor-session-1", // optional sub-agent / task ID
  "description":  "Which approach?",
  "type":         "choice",             // "approve" | "choice" | "input"
  "options":      ["keep","rewrite","skip"],
  "placeholder":  "Enter target dir:",  // input type hint
  "callback_url": "http://n8n.grid/webhook/abc"
}

/app/register payload
----------------------
{
  "name":         "codenomad",
  "display_name": "Codenomad",
  "emoji":        "👨‍💻",
  "thread_id":    null   // Telegram topic thread ID (supergroup with Topics)
}

Callback payload (sent to callback_url)
----------------------------------------
{
  "decision_id": "a1b2c3d4",
  "source":      "codenomad",
  "source_id":   "refactor-session-1",
  "type":        "choice",
  "choice":      "rewrite",    // choice
  "approved":    true,         // approve
  "input":       "...",        // input
  "by":          "tg-username",
  "at":          "2026-..."
}

Config (/etc/grid-messenger/config.env)
---------------------------------------
  TELEGRAM_BOT_TOKEN        BotFather token (required)
  TELEGRAM_ALLOWED_USER_IDS comma-separated Telegram user IDs
  NOTIFY_CHAT_IDS           defaults to TELEGRAM_ALLOWED_USER_IDS
  N8N_BASE_URL              default: http://127.0.0.1:5678
  FAIGATE_URL               default: http://127.0.0.1:8090
  OPENCLAW_URL              default: http://127.0.0.1:18789
  WEBHOOK_PORT              default: 9119
  WEBHOOK_BIND              default: 127.0.0.1
  APPS_FILE                 default: /opt/grid-messenger/apps.json
"""
import json
import os
import uuid
import logging
import asyncio
from datetime import datetime, timezone
from pathlib import Path

import aiohttp
from aiohttp import web
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    ContextTypes,
    filters,
)

# ── Config ────────────────────────────────────────────────────────────────────

TELEGRAM_BOT_TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]

_raw_ids = os.getenv("TELEGRAM_ALLOWED_USER_IDS", "")
ALLOWED_USER_IDS = {
    int(x) for x in _raw_ids.split(",")
    if x.strip().lstrip("-").isdigit()
}

_raw_notify = os.getenv("NOTIFY_CHAT_IDS", _raw_ids)
NOTIFY_CHAT_IDS = {
    int(x) for x in _raw_notify.split(",")
    if x.strip().lstrip("-").isdigit()
}

N8N_BASE_URL  = os.getenv("N8N_BASE_URL",  "http://127.0.0.1:5678")
FAIGATE_URL   = os.getenv("FAIGATE_URL",   "http://127.0.0.1:8090")
OPENCLAW_URL  = os.getenv("OPENCLAW_URL",  "http://127.0.0.1:18789")
WEBHOOK_PORT  = int(os.getenv("WEBHOOK_PORT", "9119"))
WEBHOOK_BIND  = os.getenv("WEBHOOK_BIND",  "127.0.0.1")
APPS_FILE     = Path(os.getenv("APPS_FILE", "/opt/grid-messenger/apps.json"))

log = logging.getLogger("grid-messenger")

# ── App registry ──────────────────────────────────────────────────────────────
# { name: {display_name, emoji, thread_id, registered_at} }
_apps: dict = {}

# Default emoji per well-known app name
_DEFAULT_EMOJI: dict = {
    "codenomad":   "👨‍💻",
    "openclaw":    "🦾",
    "claude-cli":  "🤖",
    "claude":      "🤖",
    "n8n":         "⚡",
    "faigate":     "🚦",
    "deerflow":    "🦌",
    "paperclip":   "📎",
    "shipfaster":  "🚀",
}


def _load_apps() -> None:
    if APPS_FILE.exists():
        try:
            _apps.update(json.loads(APPS_FILE.read_text()))
        except Exception as exc:
            log.warning("Could not load apps registry: %s", exc)


def _save_apps() -> None:
    try:
        APPS_FILE.parent.mkdir(parents=True, exist_ok=True)
        APPS_FILE.write_text(json.dumps(_apps, indent=2))
    except Exception as exc:
        log.warning("Could not save apps registry: %s", exc)


def _app_info(name: str) -> dict:
    """Return registry entry for name, creating a default if unknown."""
    if name in _apps:
        return _apps[name]
    return {
        "display_name": name.capitalize(),
        "emoji":        _DEFAULT_EMOJI.get(name.lower(), "📡"),
        "thread_id":    None,
    }


def _source_line(source: str, source_id: str) -> str:
    info = _app_info(source)
    em   = info.get("emoji", "📡")
    dn   = info.get("display_name", source)
    line = f"{em} *{dn}*"
    if source_id:
        line += f"  ›  `{source_id}`"
    return line


# ── Pending queues ─────────────────────────────────────────────────────────────
# { decision_id: {source, source_id, description, type, options, placeholder,
#                  callback_url, created_at} }
_pending: dict = {}

# { telegram_user_id: decision_id }  — tracks who is typing a text reply
_awaiting_input: dict = {}


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _allowed(update: Update) -> bool:
    uid = update.effective_user.id if update.effective_user else None
    return uid is not None and (not ALLOWED_USER_IDS or uid in ALLOWED_USER_IDS)


def _new_id() -> str:
    return str(uuid.uuid4())[:8]


# ── Keyboard builders ─────────────────────────────────────────────────────────

def _keyboard_approve(did: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("✔ Approve", callback_data=f"approve:{did}"),
        InlineKeyboardButton("✘ Reject",  callback_data=f"reject:{did}"),
    ]])


def _keyboard_choice(did: str, options: list) -> InlineKeyboardMarkup:
    """One button per option; single-column for >4 options."""
    row_size = 1 if len(options) > 4 else 2
    buttons  = [
        InlineKeyboardButton(opt, callback_data=f"choice:{did}:{opt}")
        for opt in options
    ]
    rows = [buttons[i:i + row_size] for i in range(0, len(buttons), row_size)]
    rows.append([InlineKeyboardButton("✘ Cancel", callback_data=f"cancel:{did}")])
    return InlineKeyboardMarkup(rows)


def _keyboard_cancel(did: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("✘ Cancel", callback_data=f"cancel:{did}")
    ]])


def _format_decision(did: str, item: dict) -> str:
    dtype   = item.get("type", "approve")
    icons   = {"approve": "⏳", "choice": "🔀", "input": "✏️"}
    icon    = icons.get(dtype, "⏳")
    source  = item.get("source", "")
    sid     = item.get("source_id", "")
    desc    = item["description"]

    lines = [f"{icon} *{dtype.upper()}*  `{did}`"]
    if source:
        lines.append(_source_line(source, sid))
    lines += ["", desc]

    if dtype == "choice" and item.get("options"):
        lines += ["", "_" + " · ".join(item["options"]) + "_"]
    if dtype == "input" and item.get("placeholder"):
        lines += ["", f"_{item['placeholder']}_"]
    return "\n".join(lines)


# ── Telegram: commands ────────────────────────────────────────────────────────

async def cmd_help(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    await update.message.reply_text(
        "🤖 *grid-messenger*\n\n"
        "*/status*   — grid-core health\n"
        "*/pending*  — open decisions\n"
        "*/apps*     — registered apps\n"
        "*/cancel*   — cancel input prompt\n"
        "*/help*     — this message",
        parse_mode="Markdown",
    )


async def cmd_status(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    checks = [
        ("n8n",      f"{N8N_BASE_URL}/healthz"),
        ("faigate",  f"{FAIGATE_URL}/health"),
        ("openclaw", f"{OPENCLAW_URL}/health"),
    ]
    lines = ["🖥 *grid-core*\n"]
    async with aiohttp.ClientSession() as session:
        for name, url in checks:
            try:
                async with session.get(
                    url, timeout=aiohttp.ClientTimeout(total=3)
                ) as resp:
                    icon = "✔" if resp.status < 400 else "⚠"
                    lines.append(f"{icon} {name}")
            except Exception:
                lines.append(f"✘ {name}")
    if _pending:
        lines.append(f"\n⏳ {len(_pending)} pending — /pending")
    lines.append(f"\n_{_now()}_")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_pending(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    if not _pending:
        await update.message.reply_text("✔ No pending decisions.")
        return
    for did, item in list(_pending.items()):
        dtype = item.get("type", "approve")
        text  = _format_decision(did, item)
        if dtype == "approve":
            kb = _keyboard_approve(did)
        elif dtype == "choice":
            kb = _keyboard_choice(did, item.get("options", []))
        else:
            kb = _keyboard_cancel(did)
        await update.message.reply_text(text, reply_markup=kb, parse_mode="Markdown")


async def cmd_apps(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    if not _apps:
        await update.message.reply_text(
            "No apps registered yet.\n"
            "Register via: `POST /app/register`",
            parse_mode="Markdown",
        )
        return
    lines = ["📱 *Registered apps*\n"]
    for name, info in sorted(_apps.items()):
        em      = info.get("emoji", "📡")
        dn      = info.get("display_name", name)
        tid     = info.get("thread_id")
        thread  = f"  (thread {tid})" if tid else ""
        lines.append(f"{em} *{dn}*  `{name}`{thread}")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_cancel_input(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    uid = update.effective_user.id
    did = _awaiting_input.pop(uid, None)
    if did:
        await update.message.reply_text(
            f"✘ Input prompt `{did}` cancelled.", parse_mode="Markdown"
        )
    else:
        await update.message.reply_text("Nothing to cancel.")


# ── Telegram: free-text input capture ────────────────────────────────────────

async def handle_text_input(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update) or not update.message or not update.message.text:
        return
    uid = update.effective_user.id
    did = _awaiting_input.pop(uid, None)
    if did is None:
        return  # not waiting — ignore

    item = _pending.pop(did, None)
    if item is None:
        await update.message.reply_text(
            f"⚠ Decision `{did}` already resolved.", parse_mode="Markdown"
        )
        return

    user_input = update.message.text.strip()
    by = update.effective_user.username or str(uid)
    await _fire_callback(item, did, {
        "decision_id": did, "source": item.get("source", ""),
        "source_id": item.get("source_id", ""),
        "type": "input", "input": user_input, "by": by, "at": _now(),
    })
    await update.message.reply_text(
        f"✔ Input captured for `{did}`\n\n_{user_input}_",
        parse_mode="Markdown",
    )


async def handle_unknown_cmd(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    await update.message.reply_text("Unknown command. /help")


# ── Telegram: inline button callbacks ────────────────────────────────────────

async def cb_button(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    uid   = query.from_user.id if query.from_user else None
    if uid is None or (ALLOWED_USER_IDS and uid not in ALLOWED_USER_IDS):
        await query.answer("Not authorized.")
        return

    await query.answer()
    data   = query.data or ""
    parts  = data.split(":", 2)
    action = parts[0]
    did    = parts[1] if len(parts) > 1 else ""
    by     = query.from_user.username or str(uid)

    if action == "cancel":
        _pending.pop(did, None)
        _awaiting_input.pop(uid, None)
        await query.edit_message_text(f"✘ Cancelled `{did}`", parse_mode="Markdown")
        return

    item = _pending.pop(did, None)
    if item is None:
        await query.edit_message_text(
            f"⚠ `{did}` already handled or expired.", parse_mode="Markdown"
        )
        return

    source    = item.get("source", "")
    source_id = item.get("source_id", "")

    if action in ("approve", "reject"):
        approved = action == "approve"
        label    = "✔ Approved" if approved else "✘ Rejected"
        payload  = {
            "decision_id": did, "source": source, "source_id": source_id,
            "type": "approve", "approved": approved, "by": by, "at": _now(),
        }
        await _fire_callback(item, did, payload)
        suffix = f"\n{_source_line(source, source_id)}" if source else ""
        await query.edit_message_text(
            f"{label}  `{did}`{suffix}\n\n_{item['description']}_",
            parse_mode="Markdown",
        )

    elif action == "choice":
        chosen  = parts[2] if len(parts) > 2 else ""
        payload = {
            "decision_id": did, "source": source, "source_id": source_id,
            "type": "choice", "choice": chosen, "by": by, "at": _now(),
        }
        await _fire_callback(item, did, payload)
        suffix = f"\n{_source_line(source, source_id)}" if source else ""
        await query.edit_message_text(
            f"🔀 *{chosen}*  `{did}`{suffix}\n\n_{item['description']}_",
            parse_mode="Markdown",
        )


# ── Callback helper ───────────────────────────────────────────────────────────

async def _fire_callback(item: dict, did: str, payload: dict) -> None:
    url = item.get("callback_url", "")
    if not url:
        return
    try:
        async with aiohttp.ClientSession() as session:
            await session.post(
                url, json=payload, timeout=aiohttp.ClientTimeout(total=5)
            )
    except Exception as exc:
        log.warning("callback failed %s: %s", did, exc)


# ── Send to chat (with optional thread routing) ───────────────────────────────

async def _send_to_chats(
    tg_app: Application,
    text: str,
    keyboard: InlineKeyboardMarkup | None,
    source: str,
    follow_up: str | None = None,
) -> list:
    """Send text to all NOTIFY_CHAT_IDS, routing to thread_id if configured."""
    messages = []
    thread_id = _app_info(source).get("thread_id") if source else None

    for chat_id in NOTIFY_CHAT_IDS:
        try:
            kw = {}
            if thread_id:
                kw["message_thread_id"] = thread_id
            if keyboard:
                kw["reply_markup"] = keyboard
            msg = await tg_app.bot.send_message(
                chat_id=chat_id,
                text=text,
                parse_mode="Markdown",
                **kw,
            )
            messages.append(msg)
            if follow_up:
                await tg_app.bot.send_message(
                    chat_id=chat_id,
                    text=follow_up,
                    parse_mode="Markdown",
                    reply_to_message_id=msg.message_id,
                    **({"message_thread_id": thread_id} if thread_id else {}),
                )
        except Exception as exc:
            log.warning("notify failed chat_id=%s: %s", chat_id, exc)
    return messages


# ── HTTP: inbound from apps / n8n ─────────────────────────────────────────────

async def http_health(_req: web.Request) -> web.Response:
    return web.json_response({
        "status": "ok",
        "pending": len(_pending),
        "apps": len(_apps),
    })


async def http_decision_request(req: web.Request) -> web.Response:
    """
    POST /decision/request
    Returns { "decision_id": "..." }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    dtype        = str(body.get("type", "approve"))
    description  = str(body.get("description", "(no description)"))
    options      = list(body.get("options", []))
    placeholder  = str(body.get("placeholder", "Type your reply and send:"))
    callback_url = str(body.get("callback_url", ""))
    source       = str(body.get("source", ""))
    source_id    = str(body.get("source_id", ""))

    if dtype not in ("approve", "choice", "input"):
        return web.json_response({"error": f"unknown type: {dtype}"}, status=400)
    if dtype == "choice" and not options:
        return web.json_response({"error": "choice requires options[]"}, status=400)

    did = _new_id()
    _pending[did] = {
        "source":        source,
        "source_id":     source_id,
        "description":   description,
        "type":          dtype,
        "options":       options,
        "placeholder":   placeholder,
        "callback_url":  callback_url,
        "created_at":    _now(),
    }
    log.info("decision [%s] %s›%s: %s", dtype, source, source_id, description[:80])

    tg_app: Application = req.app["tg_app"]
    text = _format_decision(did, _pending[did])

    if dtype == "approve":
        kb = _keyboard_approve(did)
        follow_up = None
    elif dtype == "choice":
        kb = _keyboard_choice(did, options)
        follow_up = None
    else:
        kb = _keyboard_cancel(did)
        follow_up = f"✏️ {placeholder}\n\n_(Your next message will be captured as reply)_"
        for uid in ALLOWED_USER_IDS:
            _awaiting_input[uid] = did

    await _send_to_chats(tg_app, text, kb, source, follow_up)
    return web.json_response({"decision_id": did})


async def http_notify(req: web.Request) -> web.Response:
    """
    POST /notify
    { "message": "...", "level": "info|warn|error", "source": "...", "source_id": "..." }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    message   = str(body.get("message", ""))
    level     = str(body.get("level", "info"))
    source    = str(body.get("source", ""))
    source_id = str(body.get("source_id", ""))
    icon      = {"info": "ℹ", "warn": "⚠", "error": "🔴"}.get(level, "ℹ")

    lines = [f"{icon} {message}"]
    if source:
        lines = [_source_line(source, source_id), ""] + lines

    tg_app: Application = req.app["tg_app"]
    await _send_to_chats(tg_app, "\n".join(lines), None, source)
    return web.json_response({"ok": True})


async def http_app_register(req: web.Request) -> web.Response:
    """
    POST /app/register
    { "name": "codenomad", "display_name": "Codenomad", "emoji": "👨‍💻", "thread_id": null }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    name = str(body.get("name", "")).strip().lower()
    if not name:
        return web.json_response({"error": "name required"}, status=400)

    _apps[name] = {
        "display_name": str(body.get("display_name", name.capitalize())),
        "emoji":        str(body.get("emoji", _DEFAULT_EMOJI.get(name, "📡"))),
        "thread_id":    body.get("thread_id"),
        "registered_at": _now(),
    }
    _save_apps()
    log.info("app registered: %s", name)
    return web.json_response({"ok": True, "name": name})


async def http_app_list(_req: web.Request) -> web.Response:
    return web.json_response({"apps": _apps})


def _build_http_app(tg_app: Application) -> web.Application:
    app = web.Application()
    app["tg_app"] = tg_app
    app.router.add_get( "/health",            http_health)
    app.router.add_post("/decision/request",  http_decision_request)
    app.router.add_post("/approval/request",  http_decision_request)  # compat alias
    app.router.add_post("/notify",            http_notify)
    app.router.add_post("/app/register",      http_app_register)
    app.router.add_get( "/app/list",          http_app_list)
    return app


# ── Main ──────────────────────────────────────────────────────────────────────

async def _run() -> None:
    _load_apps()

    tg_app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    tg_app.add_handler(CommandHandler(["start", "help"], cmd_help))
    tg_app.add_handler(CommandHandler("status",          cmd_status))
    tg_app.add_handler(CommandHandler(["pending", "approve"], cmd_pending))
    tg_app.add_handler(CommandHandler("apps",            cmd_apps))
    tg_app.add_handler(CommandHandler("cancel",          cmd_cancel_input))
    tg_app.add_handler(CallbackQueryHandler(cb_button))
    tg_app.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND, handle_text_input
    ))
    tg_app.add_handler(MessageHandler(filters.COMMAND, handle_unknown_cmd))

    http_app = _build_http_app(tg_app)
    runner   = web.AppRunner(http_app)
    await runner.setup()
    await web.TCPSite(runner, WEBHOOK_BIND, WEBHOOK_PORT).start()

    async with tg_app:
        await tg_app.start()
        await tg_app.updater.start_polling(drop_pending_updates=True)
        log.info(
            "grid-messenger running | Telegram polling | HTTP %s:%d | apps: %d",
            WEBHOOK_BIND, WEBHOOK_PORT, len(_apps),
        )
        stop_event = asyncio.Event()
        try:
            await stop_event.wait()
        except (KeyboardInterrupt, SystemExit):
            pass
        finally:
            await tg_app.updater.stop()
            await tg_app.stop()

    await runner.cleanup()


def main() -> None:
    logging.basicConfig(
        format="%(asctime)s %(levelname)-8s %(name)s — %(message)s",
        level=logging.INFO,
    )
    if not TELEGRAM_BOT_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN not set")
        raise SystemExit(1)
    if not ALLOWED_USER_IDS:
        log.warning("TELEGRAM_ALLOWED_USER_IDS empty — all users blocked")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
