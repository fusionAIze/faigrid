#!/usr/bin/env python3
"""
grid-messenger — fusionAIze Grid Communication Bridge
Telegram bot + HTTP webhook server for grid-core decision flows.

Decision types
--------------
approve  Binary Approve / Reject (default)
choice   N labelled buttons  — options: ["openclaw","codenomad","claude-cli"]
input    Free-text reply     — user sends a message back to the bot

HTTP endpoints (127.0.0.1:WEBHOOK_PORT)
----------------------------------------
POST /decision/request    Push a decision task from n8n
POST /notify              Plain notification to all NOTIFY_CHAT_IDS
GET  /health              Status + pending count

/decision/request payload
--------------------------
{
  "description": "Which agent should handle the refactoring?",
  "type":        "choice",                    // "approve" | "choice" | "input"
  "options":     ["openclaw","codenomad","claude-cli"],  // choice only
  "placeholder": "Enter target directory:",  // input only (shown as hint)
  "callback_url": "http://n8n.grid/webhook/abc"
}

Callback payload (sent to callback_url on resolution)
------------------------------------------------------
{
  "decision_id": "a1b2c3d4",
  "type":        "choice",
  "choice":      "openclaw",    // choice type
  "approved":    true,          // approve type
  "input":       "...",         // input type
  "by":          "username",
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
"""
import os
import uuid
import logging
import asyncio
from datetime import datetime, timezone

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

log = logging.getLogger("grid-messenger")

# ── State ─────────────────────────────────────────────────────────────────────

# Active decision requests
# { decision_id: {description, type, options, placeholder, callback_url, created_at} }
_pending: dict = {}

# Tracks which decision_id a user is expected to reply to (input type)
# { telegram_user_id: decision_id }
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
    """One button per option, arranged in rows of up to 2."""
    buttons = [
        InlineKeyboardButton(opt, callback_data=f"choice:{did}:{opt}")
        for opt in options
    ]
    # Group into rows of 2 (single column for > 4 options for readability)
    row_size = 1 if len(options) > 4 else 2
    rows = [buttons[i:i + row_size] for i in range(0, len(buttons), row_size)]
    rows.append([InlineKeyboardButton("✘ Cancel", callback_data=f"cancel:{did}")])
    return InlineKeyboardMarkup(rows)


def _keyboard_cancel(did: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("✘ Cancel", callback_data=f"cancel:{did}")
    ]])


def _format_pending(did: str, item: dict) -> str:
    dtype = item.get("type", "approve")
    desc  = item["description"]
    icons = {"approve": "⏳", "choice": "🔀", "input": "✏️"}
    icon  = icons.get(dtype, "⏳")
    lines = [f"{icon} *{dtype.upper()}*  `{did}`", "", desc]
    if dtype == "choice" and item.get("options"):
        lines += ["", "_Options: " + " · ".join(item["options"]) + "_"]
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
        "*/pending*  — list open decisions\n"
        "*/cancel*   — cancel your active input prompt\n"
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
        lines.append(f"\n⏳ {len(_pending)} pending decision(s) — /pending")
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
        text  = _format_pending(did, item)
        if dtype == "approve":
            kb = _keyboard_approve(did)
        elif dtype == "choice":
            kb = _keyboard_choice(did, item.get("options", []))
        else:  # input
            kb = _keyboard_cancel(did)
        await update.message.reply_text(text, reply_markup=kb, parse_mode="Markdown")


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


# ── Telegram: free-text input replies ────────────────────────────────────────

async def handle_text_input(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    """Handles plain text messages when a user has an open 'input' decision."""
    if not _allowed(update) or not update.message or not update.message.text:
        return
    uid = update.effective_user.id
    did = _awaiting_input.pop(uid, None)
    if did is None:
        # Not waiting for anything — silently ignore
        return

    item = _pending.pop(did, None)
    if item is None:
        await update.message.reply_text(
            f"⚠ Decision `{did}` already resolved.", parse_mode="Markdown"
        )
        return

    user_input = update.message.text.strip()
    by = update.effective_user.username or str(uid)

    await _fire_callback(item, {"decision_id": did, "type": "input",
                                "input": user_input, "by": by, "at": _now()})
    await update.message.reply_text(
        f"✔ Input received for `{did}`\n\n_{user_input}_",
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
    data = query.data or ""
    parts = data.split(":", 2)
    action = parts[0]
    did    = parts[1] if len(parts) > 1 else ""
    by     = query.from_user.username or str(uid)

    # ── cancel ────────────────────────────────────────────────────────────────
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

    # ── approve / reject ──────────────────────────────────────────────────────
    if action in ("approve", "reject"):
        approved = action == "approve"
        label    = "✔ Approved" if approved else "✘ Rejected"
        payload  = {"decision_id": did, "type": "approve",
                    "approved": approved, "by": by, "at": _now()}
        await _fire_callback(item, payload)
        await query.edit_message_text(
            f"{label}\n`{did}`\n\n_{item['description']}_",
            parse_mode="Markdown",
        )

    # ── choice ────────────────────────────────────────────────────────────────
    elif action == "choice":
        chosen = parts[2] if len(parts) > 2 else ""
        payload = {"decision_id": did, "type": "choice",
                   "choice": chosen, "by": by, "at": _now()}
        await _fire_callback(item, payload)
        await query.edit_message_text(
            f"🔀 *{chosen}*\n`{did}`\n\n_{item['description']}_",
            parse_mode="Markdown",
        )


# ── Callback helper ───────────────────────────────────────────────────────────

async def _fire_callback(item: dict, payload: dict) -> None:
    url = item.get("callback_url", "")
    if not url:
        return
    try:
        async with aiohttp.ClientSession() as session:
            await session.post(
                url, json=payload,
                timeout=aiohttp.ClientTimeout(total=5)
            )
    except Exception as exc:
        log.warning("callback failed %s: %s", payload.get("decision_id"), exc)


# ── HTTP: inbound from n8n ────────────────────────────────────────────────────

async def http_health(_req: web.Request) -> web.Response:
    return web.json_response({"status": "ok", "pending": len(_pending)})


async def http_decision_request(req: web.Request) -> web.Response:
    """
    POST /decision/request
    Accepts approve / choice / input decisions.
    Returns { "decision_id": "..." }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    dtype       = str(body.get("type", "approve"))
    description = str(body.get("description", "(no description)"))
    options     = list(body.get("options", []))
    placeholder = str(body.get("placeholder", "Type your reply and send:"))
    callback_url = str(body.get("callback_url", ""))

    if dtype not in ("approve", "choice", "input"):
        return web.json_response({"error": f"unknown type: {dtype}"}, status=400)
    if dtype == "choice" and not options:
        return web.json_response({"error": "choice type requires options[]"}, status=400)

    did = _new_id()
    _pending[did] = {
        "description":   description,
        "type":          dtype,
        "options":       options,
        "placeholder":   placeholder,
        "callback_url":  callback_url,
        "created_at":    _now(),
    }
    log.info("decision queued: %s [%s] — %s", did, dtype, description[:80])

    tg_app: Application = req.app["tg_app"]
    text = _format_pending(did, _pending[did])

    if dtype == "approve":
        kb = _keyboard_approve(did)
    elif dtype == "choice":
        kb = _keyboard_choice(did, options)
    else:
        kb = _keyboard_cancel(did)

    for chat_id in NOTIFY_CHAT_IDS:
        try:
            msg = await tg_app.bot.send_message(
                chat_id=chat_id,
                text=text,
                reply_markup=kb,
                parse_mode="Markdown",
            )
            # For input type: also send a plain follow-up prompt so the user
            # knows to just type their reply directly.
            if dtype == "input":
                await tg_app.bot.send_message(
                    chat_id=chat_id,
                    text=f"✏️ {placeholder}\n\n"
                         f"_(Reply to this chat — your next message will be captured)_",
                    parse_mode="Markdown",
                    reply_to_message_id=msg.message_id,
                )
                # Register all allowed users as "awaiting input" for this decision
                for uid in ALLOWED_USER_IDS:
                    _awaiting_input[uid] = did
        except Exception as exc:
            log.warning("notify failed chat_id=%s: %s", chat_id, exc)

    return web.json_response({"decision_id": did})


async def http_notify(req: web.Request) -> web.Response:
    """
    POST /notify
    { "message": "...", "level": "info|warn|error" }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    message = str(body.get("message", ""))
    level   = str(body.get("level", "info"))
    icon    = {"info": "ℹ", "warn": "⚠", "error": "🔴"}.get(level, "ℹ")

    tg_app: Application = req.app["tg_app"]
    for chat_id in NOTIFY_CHAT_IDS:
        try:
            await tg_app.bot.send_message(chat_id=chat_id, text=f"{icon} {message}")
        except Exception as exc:
            log.warning("notify failed chat_id=%s: %s", chat_id, exc)

    return web.json_response({"ok": True})


def _build_http_app(tg_app: Application) -> web.Application:
    app = web.Application()
    app["tg_app"] = tg_app
    app.router.add_get( "/health",            http_health)
    app.router.add_post("/decision/request",  http_decision_request)
    # Backward-compat alias for older n8n workflows
    app.router.add_post("/approval/request",  http_decision_request)
    app.router.add_post("/notify",            http_notify)
    return app


# ── Main ──────────────────────────────────────────────────────────────────────

async def _run() -> None:
    tg_app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    tg_app.add_handler(CommandHandler(["start", "help"], cmd_help))
    tg_app.add_handler(CommandHandler("status",          cmd_status))
    tg_app.add_handler(CommandHandler(["pending", "approve"], cmd_pending))
    tg_app.add_handler(CommandHandler("cancel",          cmd_cancel_input))
    tg_app.add_handler(CallbackQueryHandler(cb_button))
    # Text handler must come BEFORE the unknown-command handler
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
            "grid-messenger running | Telegram polling | HTTP %s:%d",
            WEBHOOK_BIND, WEBHOOK_PORT,
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
