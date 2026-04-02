#!/usr/bin/env python3
"""
grid-messenger — fusionAIze Grid Communication Bridge
Telegram bot + HTTP webhook server for n8n approval flows.

Config (/etc/grid-messenger/config.env):
  TELEGRAM_BOT_TOKEN        BotFather token (required)
  TELEGRAM_ALLOWED_USER_IDS comma-separated Telegram user IDs
  NOTIFY_CHAT_IDS           chat IDs that receive proactive notifications
                            (defaults to TELEGRAM_ALLOWED_USER_IDS)
  N8N_BASE_URL              default: http://127.0.0.1:5678
  FAIGATE_URL               default: http://127.0.0.1:8090
  OPENCLAW_URL              default: http://127.0.0.1:18789
  WEBHOOK_PORT              inbound HTTP port for n8n (default: 9119)
  WEBHOOK_BIND              bind address (default: 127.0.0.1)
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
WEBHOOK_PORT  = int(os.getenv("WEBHOOK_PORT",  "9119"))
WEBHOOK_BIND  = os.getenv("WEBHOOK_BIND",  "127.0.0.1")

log = logging.getLogger("grid-messenger")

# ── Approval queue ────────────────────────────────────────────────────────────
# { approval_id: { description, callback_url, created_at } }
_pending: dict = {}


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _allowed(update: Update) -> bool:
    uid = update.effective_user.id if update.effective_user else None
    return uid is not None and (not ALLOWED_USER_IDS or uid in ALLOWED_USER_IDS)


# ── Telegram: commands ────────────────────────────────────────────────────────

async def cmd_help(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    await update.message.reply_text(
        "🤖 *grid-messenger*\n\n"
        "*/status*   — grid-core health\n"
        "*/approve*  — list pending approvals\n"
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

    lines.append(f"\n_{_now()}_")
    await update.message.reply_text("\n".join(lines), parse_mode="Markdown")


async def cmd_approve(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    if not _pending:
        await update.message.reply_text("✔ No pending approvals.")
        return
    for aid, item in list(_pending.items()):
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✔ Approve", callback_data=f"approve:{aid}"),
            InlineKeyboardButton("✘ Reject",  callback_data=f"reject:{aid}"),
        ]])
        await update.message.reply_text(
            f"⏳ *Approval required*\n`{aid}`\n\n{item['description']}",
            reply_markup=kb,
            parse_mode="Markdown",
        )


async def cb_decision(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    uid = query.from_user.id if query.from_user else None
    if uid is None or (ALLOWED_USER_IDS and uid not in ALLOWED_USER_IDS):
        await query.answer("Not authorized.")
        return

    await query.answer()
    parts = query.data.split(":", 1)
    if len(parts) != 2:
        return
    action, aid = parts
    item = _pending.pop(aid, None)

    if item is None:
        await query.edit_message_text(
            f"⚠ `{aid}` already handled or expired.", parse_mode="Markdown"
        )
        return

    approved = action == "approve"
    label = "✔ Approved" if approved else "✘ Rejected"
    by = query.from_user.username or str(uid)

    # Notify n8n callback URL
    if item.get("callback_url"):
        try:
            async with aiohttp.ClientSession() as session:
                await session.post(
                    item["callback_url"],
                    json={
                        "approval_id": aid,
                        "approved": approved,
                        "by": by,
                        "at": _now(),
                    },
                    timeout=aiohttp.ClientTimeout(total=5),
                )
        except Exception as exc:
            log.warning("callback failed %s: %s", aid, exc)

    await query.edit_message_text(
        f"{label}\n`{aid}`\n\n_{item['description']}_",
        parse_mode="Markdown",
    )


async def handle_unknown(update: Update, _ctx: ContextTypes.DEFAULT_TYPE) -> None:
    if not _allowed(update):
        return
    await update.message.reply_text("Unknown command. /help")


# ── HTTP webhook server ───────────────────────────────────────────────────────
# n8n calls these endpoints to push approval requests and plain notifications.

async def http_health(_req: web.Request) -> web.Response:
    return web.json_response({"status": "ok", "pending_approvals": len(_pending)})


async def http_approval_request(req: web.Request) -> web.Response:
    """
    POST /approval/request
    {
      "description": "Agent X wants to delete /tmp/foo — approve?",
      "callback_url": "https://n8n.grid/webhook/approval-result"
    }
    → { "approval_id": "a1b2c3d4" }

    grid-messenger pushes an inline-button message to all NOTIFY_CHAT_IDS.
    When the user taps Approve/Reject, the callback_url receives:
    { approval_id, approved, by, at }
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    description  = str(body.get("description", "(no description)"))
    callback_url = str(body.get("callback_url", ""))
    aid = str(uuid.uuid4())[:8]

    _pending[aid] = {
        "description":  description,
        "callback_url": callback_url,
        "created_at":   _now(),
    }
    log.info("approval queued: %s — %s", aid, description[:80])

    tg_app: Application = req.app["tg_app"]
    kb = InlineKeyboardMarkup([[
        InlineKeyboardButton("✔ Approve", callback_data=f"approve:{aid}"),
        InlineKeyboardButton("✘ Reject",  callback_data=f"reject:{aid}"),
    ]])
    for chat_id in NOTIFY_CHAT_IDS:
        try:
            await tg_app.bot.send_message(
                chat_id=chat_id,
                text=f"⏳ *Approval required*\n`{aid}`\n\n{description}",
                reply_markup=kb,
                parse_mode="Markdown",
            )
        except Exception as exc:
            log.warning("notify failed chat_id=%s: %s", chat_id, exc)

    return web.json_response({"approval_id": aid})


async def http_notify(req: web.Request) -> web.Response:
    """
    POST /notify
    { "message": "Workflow finished", "level": "info|warn|error" }
    Sends a plain text notification to all NOTIFY_CHAT_IDS.
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
    app.router.add_get( "/health",           http_health)
    app.router.add_post("/approval/request", http_approval_request)
    app.router.add_post("/notify",           http_notify)
    return app


# ── Main ──────────────────────────────────────────────────────────────────────

async def _run() -> None:
    tg_app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    tg_app.add_handler(CommandHandler(["start", "help"], cmd_help))
    tg_app.add_handler(CommandHandler("status",          cmd_status))
    tg_app.add_handler(CommandHandler("approve",         cmd_approve))
    tg_app.add_handler(CallbackQueryHandler(cb_decision))
    tg_app.add_handler(MessageHandler(filters.COMMAND,   handle_unknown))

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
        log.warning("TELEGRAM_ALLOWED_USER_IDS is empty — all users will be blocked")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
