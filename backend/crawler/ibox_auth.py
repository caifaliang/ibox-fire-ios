"""iBox 爬虫鉴权：专用号 access + refresh 续期（勿与用户科技页共票）。

配置：/opt/.ibox_crawler_config.json
  authorization / accessToken  — Bearer access
  refreshToken                 — 续期票（一次性，必须单飞刷新）
  deviceId                     — 与登录时一致更稳

用法：ensure_bearer() 返回可用 Bearer；快过期时自动 refresh。
默认不借用日活用户票；紧急才设 IBOX_CRAWLER_BORROW_PRESENCE=1。
"""
from __future__ import annotations

import base64
import json
import os
import ssl
import threading
import time
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Optional


def _borrow_presence_enabled() -> bool:
    """默认关闭：爬虫只吃后台写入的专用号，避免共票/误伤用户。"""
    v = (os.environ.get("IBOX_CRAWLER_BORROW_PRESENCE") or "").strip().lower()
    return v in ("1", "true", "yes", "on")

_CFG_PATHS = (
    Path("/opt/.ibox_crawler_config.json"),
    Path("/opt/ibox/.ibox_crawler_config.json"),
)
_lock = threading.RLock()
_refresh_dead_until = 0.0

_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


class _FileLock:
    def __init__(self, path: Path):
        self.path = path
        self.fh = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fh = open(self.path, "a+b")
        if os.name == "nt":
            import msvcrt

            self.fh.seek(0)
            msvcrt.locking(self.fh.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl

            fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        if not self.fh:
            return
        try:
            if os.name == "nt":
                import msvcrt

                self.fh.seek(0)
                msvcrt.locking(self.fh.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
        finally:
            self.fh.close()
            self.fh = None


def _cfg_path() -> Path:
    for p in _CFG_PATHS:
        if p.is_file():
            return p
    return _CFG_PATHS[0]


def _lock_path() -> Path:
    return _cfg_path().with_name(".ibox_crawler_config.lock")


def _token_exp(tok: str) -> int:
    t = (tok or "").strip()
    if t.lower().startswith("bearer "):
        t = t[7:].strip()
    if not t or t.count(".") < 2:
        return 0
    try:
        payload = t.split(".")[1]
        payload += "=" * ((4 - len(payload) % 4) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload))
        return int(data.get("exp") or 0)
    except Exception:
        return 0


def _normalize_bearer(tok: str) -> str:
    t = (tok or "").strip()
    if not t:
        return ""
    if not t.lower().startswith("bearer "):
        t = "Bearer " + t
    return t


def _read_cfg() -> dict[str, Any]:
    path = _cfg_path()
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}


def _write_cfg(cfg: dict[str, Any]) -> None:
    path = _cfg_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        import config as _cfg

        auth = _normalize_bearer(cfg.get("authorization") or cfg.get("accessToken") or "")
        if auth:
            _cfg.IBOX_AUTH_TOKEN = auth
    except Exception:
        pass


def update_credentials(
    access_token: str = "",
    refresh_token: str = "",
    device_id: str = "",
) -> dict[str, Any]:
    """写入/更新爬虫凭证。"""
    with _FileLock(_lock_path()):
        with _lock:
            cfg = dict(_read_cfg())
            if access_token:
                cfg["authorization"] = _normalize_bearer(access_token)
                cfg["accessToken"] = access_token.strip()
                if access_token.lower().startswith("bearer "):
                    cfg["accessToken"] = access_token[7:].strip()
            if refresh_token:
                cfg["refreshToken"] = refresh_token.strip()
            if device_id:
                cfg["deviceId"] = device_id.strip()
            cfg.pop("deadUntil", None)
            _write_cfg(cfg)
            return {
                "ok": True,
                "has_access": bool(cfg.get("authorization") or cfg.get("accessToken")),
                "has_refresh": bool(cfg.get("refreshToken")),
                "exp": _token_exp(cfg.get("authorization") or cfg.get("accessToken") or ""),
                "deviceId": cfg.get("deviceId") or "",
            }


def status() -> dict[str, Any]:
    cfg = _read_cfg()
    access = cfg.get("authorization") or cfg.get("accessToken") or ""
    exp = _token_exp(access)
    now = int(time.time())
    return {
        "has_access": bool(access),
        "has_refresh": bool(cfg.get("refreshToken")),
        "exp": exp,
        "left_s": max(0, exp - now) if exp else 0,
        "deviceId": (cfg.get("deviceId") or "")[:20],
        "deadUntil": cfg.get("deadUntil"),
    }


def _mark_dead(cfg: dict[str, Any], seconds: float) -> None:
    global _refresh_dead_until
    until = time.time() + seconds
    cfg["deadUntil"] = until
    _refresh_dead_until = until
    _write_cfg(cfg)


def _unwrap_ibox_body(obj: Any) -> dict[str, Any]:
    """sail-api 常返回 {data, encryptKey} 密文；解成业务 JSON。"""
    if not isinstance(obj, dict):
        return {"code": -1, "message": "bad body"}
    if obj.get("encryptKey") and obj.get("data") is not None:
        try:
            from crawler.ibox3 import decrypt

            plain = decrypt(json.dumps(obj, ensure_ascii=False))
            out = json.loads(plain) if isinstance(plain, str) else plain
            if isinstance(out, dict):
                return out
        except Exception as e:
            return {"code": -1, "message": "decrypt fail: {}".format(str(e)[:80])}
    return obj


def _http_refresh(refresh: str, device: str) -> dict[str, Any]:
    body = json.dumps({"refreshToken": refresh}).encode()
    did = device.strip() or ("dev_" + uuid.uuid4().hex)
    headers = {
        "Content-Type": "application/json;charset=UTF-8",
        "User-Agent": "Dart/3.11 (dart:io)",
        "platform-type": "1",
        "channel": "website",
        "device-id": did,
        "DEVICE-ID": did,
        "msg-id": str(uuid.uuid4()) + "_android",
        "app-version": "3.0.13",
        "app-version-number": "30013",
        "accept": "application/json",
    }
    # APP 真路径（libapp）：/personal-center-service/refresh-token
    # 旧 v1/auth/token/refresh 已 404
    url = "https://sail-api.ibox.art/personal-center-service/refresh-token"
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=12) as resp:
            raw = json.loads(resp.read().decode("utf-8", "replace"))
            return _unwrap_ibox_body(raw)
    except urllib.error.HTTPError as e:
        try:
            raw_txt = e.read().decode("utf-8", "replace")
            raw = json.loads(raw_txt) if raw_txt else {"code": e.code, "message": "HTTP {}".format(e.code)}
            out = _unwrap_ibox_body(raw)
            # 部分网关对业务错误也回 4xx + 加密体；解完后以业务 code 为准
            if "code" not in out and e.code:
                out["code"] = e.code
            return out
        except Exception:
            return {"code": e.code, "message": "HTTP {}".format(e.code)}
    except Exception as e:
        return {"code": -1, "message": str(e)[:120]}


def borrow_access_from_presence(min_left_s: int = 600) -> str:
    """从日活落库的用户 access 里挑一张仍有效的，写入爬虫配置（不改 refresh）。

    默认禁用；仅 IBOX_CRAWLER_BORROW_PRESENCE=1 时可用。生产应靠专用号 refresh。
    """
    if not _borrow_presence_enabled():
        return ""
    try:
        from api.ibox_token_crypto import decrypt_ibox_token
        from api.presence import ensure_presence_schema
        from database import SessionLocal
        import models

        ensure_presence_schema()
    except Exception as e:
        print("[ibox_auth] borrow import fail: {}".format(str(e)[:80]), flush=True)
        return ""

    now_ts = int(time.time())
    need_exp = now_ts + max(60, int(min_left_s))
    db = SessionLocal()
    best_tok = ""
    best_exp = 0
    best_uid = 0
    try:
        rows = (
            db.query(models.IboxPresence)
            .filter(
                models.IboxPresence.ibox_token_enc.isnot(None),
                models.IboxPresence.ibox_token_enc != "",
                models.IboxPresence.health == "ok",
            )
            .order_by(models.IboxPresence.last_seen.desc())
            .limit(40)
            .all()
        )
        for row in rows:
            raw = decrypt_ibox_token(row.ibox_token_enc or "") or ""
            if not raw:
                continue
            exp = _token_exp(raw)
            if exp < need_exp:
                continue
            if exp > best_exp:
                best_exp = exp
                best_tok = raw
                best_uid = int(row.ibox_uid or 0)
    except Exception as e:
        print("[ibox_auth] borrow query fail: {}".format(str(e)[:80]), flush=True)
        return ""
    finally:
        db.close()

    if not best_tok:
        return ""

    info = update_credentials(access_token=best_tok)
    left_h = round(max(0, best_exp - now_ts) / 3600, 2)
    print(
        "[ibox_auth] borrowed access from presence uid={} left_h={} has_refresh={}".format(
            best_uid, left_h, info.get("has_refresh")
        ),
        flush=True,
    )
    return _normalize_bearer(best_tok)


def ensure_bearer(force: bool = False, proactive: bool = True) -> str:
    """返回可用 Bearer。proactive 时提前 120s 续期；默认不借用户日活票。"""
    global _refresh_dead_until
    peek = _read_cfg()
    try:
        dead = float(peek.get("deadUntil") or 0)
    except Exception:
        dead = 0.0
    access = _normalize_bearer(peek.get("authorization") or peek.get("accessToken") or "")
    if dead and time.time() < dead and not force:
        _refresh_dead_until = dead
        if access and _token_exp(access) > int(time.time()):
            return access
        # refresh 冷却中且 access 已死：仅紧急开关才借日活
        return borrow_access_from_presence() or ""

    result = ""
    with _FileLock(_lock_path()):
        with _lock:
            cfg = dict(_read_cfg())
            access = _normalize_bearer(cfg.get("authorization") or cfg.get("accessToken") or "")
            refresh = (cfg.get("refreshToken") or "").strip()
            device = (cfg.get("deviceId") or "").strip()
            if not refresh and not access:
                result = ""
            else:
                exp = _token_exp(access) if access else 0
                now = int(time.time())
                try:
                    dead = float(cfg.get("deadUntil") or 0)
                except Exception:
                    dead = 0.0
                if dead and now < dead and not force:
                    _refresh_dead_until = dead
                    result = access if access and exp > now else ""
                else:
                    slack = 120 if proactive or force else 0
                    if access and not force and exp > now + slack:
                        result = access
                    elif now < _refresh_dead_until and not force:
                        result = access if access and exp > now else ""
                    elif not refresh:
                        result = access if access and exp > now else ""
                    else:
                        result = None  # 需要走 refresh

        if result is None:
            out = _http_refresh(refresh, device)
            data = out.get("data") if isinstance(out.get("data"), dict) else {}
            with _lock:
                cfg = dict(_read_cfg())
                cur_refresh = (cfg.get("refreshToken") or "").strip()
                cur_access = _normalize_bearer(cfg.get("authorization") or cfg.get("accessToken") or "")
                now = int(time.time())
                new_access = (data.get("accessToken") or data.get("token") or "").strip()
                if out.get("code") in (0, "0") and new_access:
                    cfg["authorization"] = _normalize_bearer(new_access)
                    cfg["accessToken"] = new_access
                    if data.get("refreshToken"):
                        cfg["refreshToken"] = str(data["refreshToken"]).strip()
                    if data.get("expiresIn") is not None:
                        cfg["expiresIn"] = data["expiresIn"]
                    cfg.pop("deadUntil", None)
                    _write_cfg(cfg)
                    print("[ibox_auth] access token refreshed", flush=True)
                    result = cfg["authorization"]
                else:
                    msg = str(out.get("message") or out.get("code") or "")
                    print("[ibox_auth] refresh fail: {}".format(msg[:80]), flush=True)
                    revoked = (
                        "失效" in msg
                        or "过期" in msg
                        or out.get("code") in (401, 403, "401", "403")
                    )
                    timed_out = (
                        "timed out" in msg.lower()
                        or "timeout" in msg.lower()
                        or out.get("code") == -1
                    )
                    if cur_refresh == refresh:
                        if revoked:
                            _mark_dead(cfg, 3600)
                            result = ""
                        elif timed_out:
                            _mark_dead(cfg, 20)
                            exp = _token_exp(cur_access) if cur_access else 0
                            result = cur_access if cur_access and exp > now else ""
                        else:
                            exp = _token_exp(cur_access) if cur_access else 0
                            result = cur_access if cur_access and exp > now else ""
                    else:
                        exp = _token_exp(cur_access) if cur_access else 0
                        result = cur_access if cur_access and exp > now else ""

    if result:
        return result

    # 专用号不可用：默认返回空（要求后台重写专用短信票）；紧急才借日活
    return borrow_access_from_presence() or ""
