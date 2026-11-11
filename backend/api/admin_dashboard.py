from task_logging import _admin_log, _task_log
from fastapi import APIRouter, Query
from pydantic import BaseModel
import json, urllib.request, ssl, os, subprocess, time, re
from datetime import datetime, timedelta

router = APIRouter(prefix="/api/snipe", tags=["admin"])

@router.get("/admin/dashboard")
def admin_dashboard(admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    import models
    from database import SessionLocal
    db = SessionLocal()
    try:
        total = db.query(models.User).count()
        vip = db.query(models.User).filter(models.User.is_vip == 1).count()
        today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        active = db.query(models.SearchHistory).filter(
            models.SearchHistory.queried_at >= today
        ).distinct(models.SearchHistory.user_id).count()

        tasks = []
        _now = time.time()
        TM = {"snipe_buy": "捡漏", "snipe_sell": "射求购", "batch_list": "上架",
              "batch_unlist": "下架", "synth_snipe_task": "合成", "snipe_swap": "抢合", "auto-loop": "互刷"}

        # Celery tasks
        try:
            from celery_app import app
            ins = app.control.inspect()
            for w, tl in (ins.active() or {}).items():
                for t in tl:
                    tn = t.get("name", "?").replace("celery-", "")
                    label = TM.get(tn, tn)
                    info = ""
                    try:
                        args = t.get("args", [])
                        a = args[0] if args and isinstance(args[0], dict) else {}
                        gid = a.get("group_id", ""); tar = a.get("target_price", "")
                        qty = a.get("quantity", ""); cname = a.get("collection_name", "")
                        if cname: info = cname
                        elif gid: info = "GID=" + str(gid)
                        if tar: info += " <=Y" + str(tar)
                        if qty: info += " x" + str(qty) + "件"
                    except: pass
                    tasks.append({"id": t.get("id", "")[:16], "type": label,
                                  "worker": w, "status": "active", "info": info})
            for w, tl in (ins.scheduled() or {}).items():
                for t in tl:
                    tn = t.get("name", "?").replace("celery-", "")
                    tasks.append({"id": t.get("id", "")[:16], "type": TM.get(tn, tn),
                                  "worker": w, "status": "waiting", "info": ""})
        except: pass

        # File-based tasks — detect type from filename prefix
        _file_type_map = {"sell_": "射求购", "list_": "上架", "unlist_": "下架",
                          "sweep_": "点对点", "auto_": "互刷"}
        for dname, fallback_type in [("/opt/ibox/.auto_loops", "互刷"),
                                      ("/opt/ibox/.batch_jobs", "批量")]:
            try:
                for fn in os.listdir(dname):
                    if fn.endswith(".json"):
                        try:
                            with open(dname + "/" + fn) as f: d = json.loads(f.read())
                            if d.get("running") and (_now - d.get("heartbeat", 0) < 120):
                                ftype = fallback_type
                                for prefix, label in _file_type_map.items():
                                    if fn.startswith(prefix):
                                        ftype = label; break
                                info = ""
                                tg = d.get("target", "?"); b = d.get("bought", 0)
                                s = d.get("sold", 0); c = d.get("cycle", 0)
                                if tg != "?": info += "目标" + str(tg)
                                if b + s > 0: info += " 买" + str(b) + "/卖" + str(s)
                                if c > 0: info += " 第" + str(c) + "轮"
                                tasks.append({"id": fn[:-5], "type": ftype,
                                    "status": "running", "info": info})
                        except: pass
            except: pass

        # Crawl status
        try:
            for fn in os.listdir("/opt/ibox/.crawl_status"):
                if fn.endswith(".json"):
                    try:
                        mtime = os.path.getmtime("/opt/ibox/.crawl_status/" + fn)
                        if _now - mtime < 300:
                            with open("/opt/ibox/.crawl_status/" + fn) as f:
                                d = json.loads(f.read())
                            if d.get("status") in ("running", "enriching"):
                                tasks.append({"id": fn[:-5], "type": "数据采集",
                                    "status": d.get("status"),
                                    "info": str(d.get("items_crawled", 0)) + "条"})
                    except: pass
        except: pass

        # Logs
        logs = []
        try:
            for r in db.query(models.AdminLog).order_by(models.AdminLog.id.desc()).limit(200).all():
                logs.append({"id": r.id, "user": r.username, "action": r.action,
                    "detail": r.detail, "gid": r.group_id,
                    "time": str(r.created_at + timedelta(hours=8))[:19] if r.created_at else ""})
        except: pass

        # History
        history = []
        for r in db.query(models.TaskHistory).order_by(models.TaskHistory.id.desc()).limit(100).all():
            gname = ""
            if r.group_id:
                try:
                    idx = db.query(models.CollectionIndex).filter_by(id=r.group_id).first()
                    if idx and idx.name:
                        gname = idx.name[:30]
                except: pass

            detail = r.detail or ""
            b = re.search(r"bought=(\d+)", detail)
            s = re.search(r"sold=(\d+)", detail)
            t = re.search(r"target=([\d.]+)", detail)
            parts = []
            if b: parts.append("买" + b.group(1) + "件")
            if s: parts.append("卖" + s.group(1) + "件")
            if t: parts.append("<=Y" + t.group(1))
            if parts: detail = " ".join(parts)

            history.append({
                "id": r.task_id, "type": r.task_type, "status": r.status,
                "detail": detail, "user": r.username, "gid": r.group_id,
                "gname": gname,
                "ended": str(r.ended_at + timedelta(hours=8))[:19] if r.ended_at else ""
            })

        # System
        mem = "?/?MB"; disk = "?/?"
        try:
            m = subprocess.check_output("free -m | grep Mem", shell=True).decode().split()
            mem = "{}/{}MB".format(m[2], m[1])
        except: pass
        try:
            d = subprocess.check_output("df -h / | tail -1", shell=True).decode().split()
            disk = "{}/{}".format(d[2], d[1])
        except: pass
        ps = "?"; ic = 0
        try:
            from crawler.proxy_pool import get_alive
            al = get_alive()
            ps = "{} alive".format(len(al)) if al else "EMPTY"
        except: pass
        try: ic = db.query(models.CollectionIndex).count()
        except: pass

        return {
            "users": {"total": total, "vip": vip, "active_today": active},
            "tasks": {"running": len(tasks), "list": tasks},
            "task_history": history,
            "logs": logs,
            "system": {"memory": mem, "disk": disk, "proxy_pool": ps, "index_count": ic},
            "server_time": (datetime.utcnow() + timedelta(hours=8)).strftime("%Y-%m-%d %H:%M:%S CST"),
        }
    finally:
        db.close()


@router.get("/admin/cards")
def admin_cards(admin_token: str = Query("")):
    """List all card keys (read-only)."""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    import models
    from database import SessionLocal
    db = SessionLocal()
    try:
        cards = []
        for r in db.query(models.CardKey).order_by(models.CardKey.id.desc()).all():
            cards.append({
                "id": r.id,
                "key": r.key_code,
                "days": r.duration_days,
                "used": bool(r.is_used),
                "used_by": r.used_by,
                "used_at": str(r.used_at)[:19] if r.used_at else "",
                "created": str(r.created_at)[:19] if r.created_at else "",
            })
        return {"cards": cards, "total": len(cards), "unused": sum(1 for c in cards if not c["used"])}
    finally:
        db.close()


class AdminLoginReq(BaseModel):
    username: str = ""
    password: str = ""

class ChangePwdReq(BaseModel):
    old_password: str = ""
    new_password: str = ""

import secrets as _secrets, hashlib as _hashlib

def _check_admin(request=None, admin_token: str = ""):
    """Validate admin session token via Redis (shared across Gunicorn workers)."""
    token = admin_token or (request.headers.get("X-Admin-Token","") if request else "")
    if not token: return False
    try:
        import redis as _r
        return _r.Redis().get(f"admin:session:{token}") == b"1"
    except:
        return False

@router.post("/admin/login")
def admin_login(req: AdminLoginReq):
    """Verify admin credentials. Returns session token (24h valid, stored in Redis)."""
    try:
        with open("/opt/ibox/.admin_pass") as f:
            stored = f.read().strip()
    except:
        stored = "iboxnb"
    if req.username == "admin" and req.password.strip() == stored.strip():
        token = _secrets.token_hex(32)
        try:
            import redis as _r
            _r.Redis().setex(f"admin:session:{token}", 86400, "1")
        except:
            pass
        return {"status": "ok", "token": token}
    return {"status": "error", "message": "账号或密码错误"}

@router.post("/admin/change-password")
def admin_change_password(req: ChangePwdReq, admin_token: str = Query("")):
    """Change admin password. Requires valid admin session."""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    try:
        with open("/opt/ibox/.admin_pass") as f:
            stored = f.read().strip()
    except:
        stored = "iboxnb"
    if req.old_password.strip() != stored.strip():
        return {"status": "error", "message": "旧密码错误"}
    if len(req.new_password) < 4:
        return {"status": "error", "message": "新密码至少4位"}
    with open("/opt/ibox/.admin_pass", "w") as f:
        f.write(req.new_password)
    return {"status": "ok", "message": "密码已修改"}

class ProxyTestReq(BaseModel):
    proxy: str = ""

@router.post("/admin/proxy-test")
def admin_proxy_test(req: ProxyTestReq, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    if not req.proxy: return {"status": "error", "message": "请输入代理地址"}
    try:
        ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
        ph = urllib.request.ProxyHandler({"https": req.proxy})
        op = urllib.request.build_opener(ph)
        url = "https://sail-api.ibox.art/public-service/markets?pageNo=1&pageSize=1"
        token = ""
        try:
            with open("/opt/.ibox_crawler_config.json") as f:
                token = json.loads(f.read()).get("authorization", "")
        except: pass
        h = {"User-Agent": "Dart/3.11 (dart:io)", "accept": "application/json"}
        if token: h["Authorization"] = token
        start = time.time()
        resp = op.open(urllib.request.Request(url, headers=h), timeout=10)
        ms = int((time.time() - start) * 1000)
        raw = resp.read().decode()
        data = json.loads(raw)
        if data.get("data") and data.get("encryptKey"):
            from crawler.ibox3 import decrypt
            try: data = json.loads(decrypt(json.dumps(data)))
            except: pass
        if data.get("code") == 0:
            return {"status": "ok", "latency_ms": ms, "message": "连接成功"}
        return {"status": "error", "message": "API返回错误 code=" + str(data.get("code", "?"))}
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}

@router.post("/admin/refresh-index")
def admin_refresh_index(admin_token: str = Query("")):
    """Admin: refresh collection index — 2-phase: markets scan + author crawl."""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    import threading, time
    def _do_refresh():
        from database import SessionLocal; import models
        from crawler.engine import crawl_all_collections, _request
        import config as cfg
        import uuid, json
        db = SessionLocal()
        try:
            # Load auth token
            tok = ''
            for cp in ['/opt/.ibox_crawler_config.json', '/opt/ibox/.ibox_crawler_config.json']:
                import os as _os
                if _os.path.exists(cp):
                    with open(cp) as f:
                        tok = json.load(f).get('authorization', '')
                    break
            if not tok.startswith('Bearer '):
                tok = 'Bearer ' + tok
            dv = str(uuid.uuid4())

            # ═══ Phase 1: Markets API direct scan (fast, catches all active) ═══
            all_groups = []
            seen_ids = set()
            segments = [-1, 54, 39]
            for seg in segments:
                page = 1
                consec_known = 0  # consecutive pages where all items are known
                while page <= 30:
                    try:
                        url = (f"{cfg.SAIL_API_BASE}/public-service/markets"
                               f"?pageNo={page}&pageSize=50&segmentId={seg}"
                               f"&sortField=2&sortType=0&timeRange=0")
                        r = _request(url, max_retries=2)
                        if not r or r.get("code") != 0:
                            break
                        items = r.get("data", {}).get("list", [])
                        if not items:
                            break
                        new_on_page = 0
                        for it in items:
                            gid = it.get("id", 0)
                            if not gid: continue
                            if gid not in seen_ids:
                                seen_ids.add(gid)
                                all_groups.append({
                                    "id": gid,
                                    "name": it.get("name", ""),
                                    "issue_num": it.get("issueNum") or 0,
                                    "cover_url": it.get("coverPicUrl") or "",
                                    "consignment_status": 1,
                                })
                                new_on_page += 1
                        print(f"[RefreshIndex] Markets seg={seg} p={page}: {new_on_page} new / {len(items)} total")
                        if new_on_page == 0:
                            consec_known += 1
                            if consec_known >= 2:  # 2 consecutive known pages → stop this segment
                                print(f"[RefreshIndex] Seg {seg}: 2 consecutive known pages, stop")
                                break
                        else:
                            consec_known = 0
                        if len(items) < 50:
                            break
                        page += 1
                        time.sleep(0.5)
                    except Exception as e:
                        print(f"[RefreshIndex] Markets seg={seg} p={page} error: {e}")
                        break

            print(f"[RefreshIndex] Phase 1 (markets): {len(all_groups)} collections found")

            # ═══ Phase 2: Author crawl (deep, catches collections by new authors) ═══
            crawled = set()
            pending = {36, 475, 449}
            # Also seed from newly discovered authors in phase 1
            author_count = 0
            while pending:
                aid = pending.pop()
                if aid in crawled: continue
                try:
                    groups = crawl_all_collections(author_id=aid)
                    crawled.add(aid)
                    for g in groups:
                        gid = g.get("id", 0)
                        if gid and gid not in seen_ids:
                            seen_ids.add(gid)
                            all_groups.append(g)
                        na = g.get("author_id") or 0
                        if na and na not in crawled and na not in pending:
                            pending.add(na)
                    author_count += 1
                    if author_count % 10 == 0:
                        print(f"[RefreshIndex] Author crawl: {author_count} authors, {len(all_groups)} total")
                except Exception as e:
                    crawled.add(aid)
                    print(f"[RefreshIndex] Author {aid} error: {e}")

            print(f"[RefreshIndex] Phase 2 (authors): {len(all_groups)} total after {author_count} authors")

            # ── Write to DB ──
            new_count = updated_count = 0
            for g in all_groups:
                gid = g.get("id", 0)
                if not gid: continue
                ex = db.query(models.CollectionIndex).filter_by(id=gid).first()
                if ex:
                    ex.name = g.get("name", ex.name)
                    ex.consignment_status = g.get("consignment_status", ex.consignment_status)
                    updated_count += 1
                else:
                    db.add(models.CollectionIndex(
                        id=gid, name=g.get("name", ""),
                        issue_num=g.get("issue_num") or 0,
                        cover_url=g.get("cover_url") or "",
                        consignment_status=g.get("consignment_status", 1)
                    ))
                    new_count += 1
            db.commit()
            print(f"[RefreshIndex] Done: {new_count} new, {updated_count} updated, {len(all_groups)} total")

            # Deactivate collections not in this refresh (if scan was comprehensive)
            active_ids = {g["id"] for g in all_groups if g.get("consignment_status") == 1}
            stale = 0
            all_db = db.query(models.CollectionIndex.id).filter(
                models.CollectionIndex.consignment_status == 1).all()
            for (gid,) in all_db:
                if gid not in active_ids:
                    db.query(models.CollectionIndex).filter_by(id=gid).update(
                        {models.CollectionIndex.consignment_status: 0})
                    stale += 1
            if stale:
                db.commit()
                print(f"[RefreshIndex] Deactivated {stale} stale collections")
        except Exception as e:
            print(f"[RefreshIndex] Error: {e}")
            import traceback; traceback.print_exc()
            try: db.rollback()
            except: pass
        finally:
            db.close()
    threading.Thread(target=_do_refresh, daemon=True).start()
    return {"status": "ok", "message": "索引刷新已启动（两阶段：市场扫描+作者遍历），后台执行中"}


# ═══════════════════════════════════════════
# Admin: User management + activity log
# ═══════════════════════════════════════════

@router.get("/admin/users")
def admin_users(q: str = "", page: int = 1, page_size: int = 50, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token): return {"status": "error", "message": "未登录"}
    from database import SessionLocal; import models
    db = SessionLocal()
    try:
        query = db.query(models.User)
        if q:
            query = query.filter(models.User.username.contains(q))
        total = query.count()
        # Sort: VIP users first (by expiry desc), then free users
        from sqlalchemy import case
        users = query.order_by(
            case((models.User.is_vip == 1, 0), else_=1),  # VIP first
            models.User.vip_expires_at.desc().nullslast(),
            models.User.id.desc()
        ).offset((page-1)*page_size).limit(page_size).all()
        result = []
        for u in users:
            task_count = db.query(models.TaskHistory).filter_by(user_id=u.id).count()
            quotas = {}
            try:
                from api import snipe as sn
                quotas = {
                    "synth": sn._synth_quota_status(int(u.id), u),
                    "presale": sn._presale_quota_status(int(u.id)),
                    "announce_lock": sn._announce_lock_quota_status(int(u.id), u),
                }
            except Exception:
                quotas = {}
            result.append({
                "id": u.id, "username": u.username,
                "is_vip": bool(u.is_vip), "is_admin": bool(u.is_admin),
                "vip_expires_at": str(u.vip_expires_at) if u.vip_expires_at else None,
                "proxy": u.proxy or "",
                "task_count": task_count,
                "created_at": str(u.created_at) if u.created_at else None,
                "quotas": quotas,
            })
        return {"status": "ok", "users": result, "total": total}
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}
    finally:
        db.close()


class VipAdjustReq(BaseModel):
    user_id: int
    days: int  # positive = add, negative = reduce

@router.post("/admin/adjust-vip")
def admin_adjust_vip(req: VipAdjustReq, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token): return {"status": "error", "message": "未登录"}
    from database import SessionLocal; import models
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=req.user_id).first()
        if not user:
            return {"status": "error", "message": "用户不存在"}
        now = datetime.utcnow()
        if user.is_vip and user.vip_expires_at and user.vip_expires_at > now:
            base = user.vip_expires_at
        else:
            base = now
        new_expiry = base + timedelta(days=req.days)
        if new_expiry <= now:
            user.is_vip = 0
            user.vip_expires_at = None
        else:
            user.is_vip = 1
            user.vip_expires_at = new_expiry
        db.commit()
        delta_str = f"+{req.days}" if req.days > 0 else str(req.days)
        _admin_log(req.user_id, user.username, "vip_adjust", f"{delta_str}天 → {new_expiry.strftime('%Y-%m-%d') if new_expiry > now else '已取消'}")
        return {"status": "ok", "vip_expires_at": str(new_expiry) if new_expiry > now else None, "is_vip": bool(user.is_vip)}
    except Exception as e:
        db.rollback()
        return {"status": "error", "message": str(e)[:200]}
    finally:
        db.close()


@router.get("/admin/activity")
def admin_activity(limit: int = 50, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token): return {"status": "error", "message": "未登录"}
    from database import SessionLocal; import models
    db = SessionLocal()
    try:
        tasks = db.query(models.TaskHistory).order_by(models.TaskHistory.ended_at.desc()).limit(limit).all()
        result = []
        for t in tasks:
            result.append({
                "time": str(t.ended_at) if t.ended_at else "",
                "username": t.username or str(t.user_id or ""),
                "type": t.task_type or "",
                "status": t.status or "",
                "detail": t.detail or "",
                "group_id": t.group_id,
            })
        return {"status": "ok", "activities": result}
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}
    finally:
        db.close()


# ── 后台重写：科技任务 / 卡密 / 今日次数 ──

TECH_MODULES = [
    ("buy", "捡漏"),
    ("sell", "卖求购"),
    ("list", "上架"),
    ("unlist", "下架"),
    ("sweep", "点对点"),
    ("swap", "互刷"),
    ("synth", "抢合"),
    ("presale", "抢购"),
    ("precision", "精准射"),
    ("rank", "打榜"),
    ("quant", "量化出货"),
    ("announce_lock", "公告锁定"),
]

_TYPE_TO_MODULE = {
    "buy": "buy", "snipe_buy": "buy", "snipe-buy": "buy",
    "sell": "sell", "sell_loop": "sell", "sell-loop": "sell", "snipe_sell": "sell",
    "list": "list", "batch-list": "list", "batch_list": "list",
    "unlist": "unlist", "batch-unlist": "unlist", "batch_unlist": "unlist",
    "sweep": "sweep", "sweep-buy": "sweep",
    "swap": "swap", "swap-loop": "swap", "snipe_swap": "swap",
    "synth": "synth", "synth-snipe": "synth", "synth_snipe": "synth",
    "synth-snipe-task": "synth", "synth_snipe_task": "synth",
    "presale": "presale",
    "precision": "precision",
    "rank": "rank",
    "quant": "quant",
    "announce_lock": "announce_lock", "announce-lock": "announce_lock",
}

_MODULE_CN = dict(TECH_MODULES)


def _norm_module(raw: str) -> str:
    s = (raw or "").strip()
    if s in _MODULE_CN:
        return s
    return _TYPE_TO_MODULE.get(s, s)


def _user_map(uids):
    if not uids:
        return {}
    from database import SessionLocal
    import models
    db = SessionLocal()
    try:
        rows = db.query(models.User).filter(models.User.id.in_(list(uids))).all()
        return {u.id: u.username for u in rows}
    finally:
        db.close()


def _result_outcome(celery_state: str, info) -> str:
    """返回 成功 / 失败 / 已停止。"""
    if celery_state == "SUCCESS":
        if isinstance(info, dict):
            st = str(info.get("status") or "").lower()
            if st in ("failed", "error", "fail"):
                return "失败"
            if "bought" in info and int(info.get("bought") or 0) <= 0 and st not in ("ok", "done", "success", ""):
                # 有 bought 字段且为 0，且显式非成功
                if st in ("failed", "error"):
                    return "失败"
        return "成功"
    if celery_state == "FAILURE":
        return "失败"
    if celery_state == "REVOKED":
        return "已停止"
    return ""


def _parse_num(v):
    if v is None or v == "":
        return None
    try:
        if isinstance(v, (int, float)):
            return v
        s = str(v).strip().replace("¥", "").replace(",", "")
        if not s:
            return None
        if "." in s:
            return float(s)
        return int(s)
    except Exception:
        return None


def _enrich_from_redis_task(r, tid: str, row: dict) -> None:
    """从 ibox:task:{id} 补全名称/数量/价格。"""
    if not tid or str(tid).startswith("db-"):
        return
    try:
        raw = r.get(f"ibox:task:{tid}")
        if not raw:
            return
        t = json.loads(raw)
        if not row.get("cname") and t.get("cname"):
            row["cname"] = t.get("cname") or ""
        if row.get("gid") in (None, "", 0) and t.get("gid"):
            row["gid"] = t.get("gid")
        if row.get("qty") is None and t.get("qty") is not None:
            row["qty"] = _parse_num(t.get("qty"))
        if row.get("price") is None and t.get("price") is not None:
            row["price"] = _parse_num(t.get("price"))
    except Exception:
        pass


def _parse_detail_qty_price(detail: str, row: dict) -> None:
    """从 detail 文本尽量解析数量/价格（历史库无独立字段时）。"""
    if not detail:
        return
    import re
    if row.get("qty") is None:
        m = re.search(r"(?:数量|件数|qty|x)\s*[=:：]?\s*(\d+)", detail, re.I)
        if not m:
            m = re.search(r"bought=(\d+)", detail, re.I)
        if not m:
            m = re.search(r"(\d+)\s*件", detail)
        if m:
            row["qty"] = int(m.group(1))
    if row.get("price") is None:
        m = re.search(r"(?:价格|单价|price|¥)\s*[=:：]?\s*(\d+(?:\.\d+)?)", detail, re.I)
        if m:
            row["price"] = float(m.group(1))


@router.get("/admin/tech-modules")
def admin_tech_modules(admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    return {"status": "ok", "modules": [{"key": k, "name": n} for k, n in TECH_MODULES]}


@router.get("/admin/tech-tasks")
def admin_tech_tasks(
    module: str = "",
    status: str = "running",
    limit: int = 100,
    admin_token: str = Query(""),
):
    """科技任务：running=运行中，done=已完成（含成功/失败）。"""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    module = _norm_module(module)
    status = (status or "running").strip().lower()
    limit = max(1, min(int(limit or 100), 300))
    out = []

    if status == "running":
        active_ids = set()
        try:
            from celery_app import app
            insp = app.control.inspect(timeout=2)
            if insp:
                for bag in (insp.active() or {}, insp.reserved() or {}).values():
                    for t in bag or []:
                        active_ids.add(t.get("id", ""))
        except Exception:
            pass

        try:
            import redis as _r
            r = _r.Redis()
            keys = r.keys("ibox:task:*")
            uids = set()
            rows = []
            for k in keys:
                try:
                    raw = r.get(k)
                    if not raw:
                        continue
                    t = json.loads(raw)
                    tid = k.decode().replace("ibox:task:", "") if isinstance(k, bytes) else str(k).replace("ibox:task:", "")
                    ttype = t.get("type", "")
                    mod = _norm_module(ttype)
                    if module and mod != module:
                        continue
                    # live celery / stop flag
                    live = "running"
                    try:
                        from celery_app import app
                        st = app.AsyncResult(tid).state
                        if st in ("SUCCESS", "FAILURE", "REVOKED"):
                            continue
                        if r.get(f"ibox:stop:{tid}") == b"1":
                            live = "stopping"
                        elif tid in active_ids or st in ("STARTED", "PROGRESS", "PENDING", "RECEIVED", "RETRY"):
                            live = "running"
                        elif st not in ("STARTED", "PROGRESS", "PENDING", "RECEIVED", "RETRY"):
                            # 无明确运行态且不在 worker 上 → 跳过（可能已结束未清理）
                            if tid not in active_ids:
                                continue
                    except Exception:
                        if t.get("status") not in (None, "", "running", "stopping"):
                            continue
                    uid = int(t.get("uid") or 0)
                    if uid:
                        uids.add(uid)
                    rows.append({
                        "task_id": tid,
                        "type": ttype,
                        "module": mod,
                        "module_name": _MODULE_CN.get(mod, mod or "未知"),
                        "uid": uid,
                        "gid": t.get("gid") or "",
                        "cname": t.get("cname") or "",
                        "price": _parse_num(t.get("price")),
                        "qty": _parse_num(t.get("qty")),
                        "started_at": int(t.get("time") or 0),
                        "live_status": live,
                        "outcome": "",
                    })
                except Exception:
                    continue
            names = _user_map(uids)
            for row in rows:
                row["username"] = names.get(row["uid"], "") or (str(row["uid"]) if row["uid"] else "")
            rows.sort(key=lambda x: x.get("started_at") or 0, reverse=True)
            out = rows[:limit]
        except Exception as e:
            return {"status": "error", "message": str(e)[:200], "tasks": []}

    else:
        # 已完成：TaskHistory + Celery 落库结果
        seen = set()
        from database import SessionLocal
        import models
        from datetime import datetime, timedelta
        since = datetime.utcnow() - timedelta(hours=24)
        db = SessionLocal()
        try:
            q = db.query(models.TaskHistory).filter(models.TaskHistory.ended_at >= since)
            if module:
                # 模糊匹配多种 type 写法
                aliases = [k for k, m in _TYPE_TO_MODULE.items() if m == module] + [module]
                from sqlalchemy import or_
                q = q.filter(or_(*[models.TaskHistory.task_type == a for a in aliases]))
            for t in q.order_by(models.TaskHistory.ended_at.desc()).limit(limit).all():
                mod = _norm_module(t.task_type or "")
                if module and mod != module:
                    continue
                st = (t.status or "").lower()
                if st in ("done", "success", "ok"):
                    outcome = "成功"
                elif st in ("failed", "fail", "error"):
                    outcome = "失败"
                else:
                    outcome = st or "失败"
                tid = t.task_id or f"db-{t.id}"
                seen.add(tid)
                row = {
                    "task_id": tid,
                    "type": t.task_type or "",
                    "module": mod,
                    "module_name": _MODULE_CN.get(mod, mod or "未知"),
                    "uid": t.user_id or 0,
                    "username": t.username or "",
                    "gid": t.group_id or "",
                    "cname": "",
                    "price": None,
                    "qty": None,
                    "detail": t.detail or "",
                    "ended_at": str(t.ended_at)[:19] if t.ended_at else "",
                    "live_status": "done",
                    "outcome": outcome,
                }
                _parse_detail_qty_price(t.detail or "", row)
                out.append(row)
        finally:
            db.close()

        # 补充：Redis 任务元数据里已结束但可能未写 TaskHistory
        try:
            import redis as _r
            r = _r.Redis()
            from celery_app import app
            for k in r.keys("ibox:task:*"):
                if len(out) >= limit:
                    break
                try:
                    tid = k.decode().replace("ibox:task:", "") if isinstance(k, bytes) else str(k).replace("ibox:task:", "")
                    if tid in seen:
                        continue
                    t = json.loads(r.get(k) or b"{}")
                    mod = _norm_module(t.get("type", ""))
                    if module and mod != module:
                        continue
                    ar = app.AsyncResult(tid)
                    if ar.state not in ("SUCCESS", "FAILURE", "REVOKED"):
                        continue
                    info = ar.info if isinstance(ar.info, dict) else {}
                    outcome = _result_outcome(ar.state, info)
                    if not outcome:
                        continue
                    seen.add(tid)
                    row = {
                        "task_id": tid,
                        "type": t.get("type", ""),
                        "module": mod,
                        "module_name": _MODULE_CN.get(mod, mod or "未知"),
                        "uid": int(t.get("uid") or 0),
                        "username": "",
                        "gid": t.get("gid") or "",
                        "cname": t.get("cname") or "",
                        "price": _parse_num(t.get("price")),
                        "qty": _parse_num(t.get("qty")),
                        "detail": str(info.get("message") or info.get("status") or "")[:120],
                        "ended_at": "",
                        "started_at": int(t.get("time") or 0),
                        "live_status": "done",
                        "outcome": outcome,
                        "bought": info.get("bought"),
                    }
                    if row["qty"] is None and info.get("bought") is not None:
                        row["qty"] = _parse_num(info.get("bought"))
                    if row["price"] is None and info.get("price") is not None:
                        row["price"] = _parse_num(info.get("price"))
                    out.append(row)
                except Exception:
                    continue
            # 用 Redis 任务缓存给 TaskHistory 行补全数量/价格/名称
            for row in out:
                _enrich_from_redis_task(r, row.get("task_id") or "", row)
            uids = {int(x["uid"]) for x in out if x.get("uid") and not x.get("username")}
            names = _user_map(uids)
            for row in out:
                if not row.get("username") and row.get("uid"):
                    row["username"] = names.get(row["uid"], "") or str(row["uid"])
        except Exception:
            pass

        # 兜底：即使上面 Redis 扫描失败，也尽量补全历史行
        try:
            import redis as _r2
            r2 = _r2.Redis()
            for row in out:
                if row.get("price") is None or row.get("qty") is None or not row.get("cname"):
                    _enrich_from_redis_task(r2, row.get("task_id") or "", row)
        except Exception:
            pass

        out = out[:limit]

    # 分组计数
    counts = {k: 0 for k, _ in TECH_MODULES}
    for row in out:
        m = row.get("module")
        if m in counts:
            counts[m] += 1

    return {
        "status": "ok",
        "tasks": out,
        "modules": [{"key": k, "name": n, "count": counts.get(k, 0)} for k, n in TECH_MODULES],
        "filter": {"module": module, "status": status},
    }


class TechStopReq(BaseModel):
    task_id: str = ""
    type: str = ""


@router.post("/admin/tech-stop")
def admin_tech_stop(req: TechStopReq, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    tid = (req.task_id or "").strip()
    if not tid:
        return {"status": "error", "message": "缺少 task_id"}
    ttype = _norm_module(req.type)
    try:
        import redis as _r
        r = _r.Redis()
        r.setex(f"ibox:stop:{tid}", 3600, "1")
        # 更新本地任务缓存状态
        raw = r.get(f"ibox:task:{tid}")
        if raw:
            try:
                d = json.loads(raw)
                d["status"] = "stopping"
                r.setex(f"ibox:task:{tid}", 86400, json.dumps(d, ensure_ascii=False))
            except Exception:
                pass
    except Exception:
        pass
    try:
        from celery_app import app
        app.control.revoke(tid, terminate=True)
    except Exception:
        pass
    # 线程型任务
    try:
        from api import snipe as sn
        if tid in getattr(sn, "_snipe_tasks", {}):
            sn._snipe_tasks[tid]["running"] = False
        if tid in getattr(sn, "_sell_tasks", {}):
            sn._sell_tasks[tid]["running"] = False
        if tid in getattr(sn, "_batch_jobs", {}):
            sn._batch_jobs[tid]["running"] = False
        if tid in getattr(sn, "_swap_tasks", {}):
            sn._swap_tasks[tid]["running"] = False
        fpath = f"/opt/ibox/.batch_jobs/{tid}.json"
        if os.path.exists(fpath):
            with open(fpath) as f:
                d = json.loads(f.read())
            d["running"] = False
            d["stopped_by"] = "admin"
            with open(fpath, "w") as f:
                json.dump(d, f)
    except Exception:
        pass
    _admin_log(None, "admin", "tech_stop", f"stop {ttype} {tid[:16]}")
    return {"status": "ok", "task_id": tid, "module": ttype}


@router.get("/admin/card-lookup")
def admin_card_lookup(key: str = "", admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    code = (key or "").strip()
    if not code:
        return {"status": "error", "message": "请输入卡密"}
    from database import SessionLocal
    import models
    db = SessionLocal()
    try:
        row = db.query(models.CardKey).filter(models.CardKey.key_code == code).first()
        if not row:
            return {"status": "error", "message": "卡密不存在"}
        uname = ""
        if row.used_by:
            u = db.query(models.User).filter_by(id=row.used_by).first()
            uname = u.username if u else str(row.used_by)
        return {
            "status": "ok",
            "card": {
                "key": row.key_code,
                "days": row.duration_days,
                "used": bool(row.is_used),
                "used_by_id": row.used_by,
                "used_by": uname,
                "used_at": str(row.used_at)[:19] if row.used_at else "",
                "created": str(row.created_at)[:19] if row.created_at else "",
            },
        }
    finally:
        db.close()


def _user_quotas(uid: int) -> dict:
    from api import snipe as sn
    user = None
    try:
        from database import SessionLocal
        import models as _m
        db = SessionLocal()
        user = db.query(_m.User).filter_by(id=int(uid)).first()
        db.close()
    except Exception:
        user = None
    return {
        "synth": sn._synth_quota_status(uid, user),
        "presale": sn._presale_quota_status(uid),
        "announce_lock": sn._announce_lock_quota_status(uid, user),
    }


class QuotaAdjustReq(BaseModel):
    user_id: int
    kind: str  # synth | presale | announce_lock
    delta: int  # >0 增加今日剩余（减少 used）；<0 减少今日剩余


@router.post("/admin/adjust-quota")
def admin_adjust_quota(req: QuotaAdjustReq, admin_token: str = Query("")):
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    kind = (req.kind or "").strip()
    from api import snipe as sn
    key_fn = {
        "synth": sn._synth_quota_key,
        "presale": sn._presale_quota_key,
        "announce_lock": sn._announce_lock_quota_key,
    }.get(kind)
    limit_map = {
        "synth": sn._synth_daily_limit(user),
        "presale": sn.PRESALE_DAILY_LIMIT,
        "announce_lock": sn.ANNOUNCE_LOCK_DAILY_LIMIT,
    }
    if not key_fn:
        return {"status": "error", "message": "kind 须为 synth/presale/announce_lock"}
    from database import SessionLocal
    import models
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=req.user_id).first()
        if not user:
            return {"status": "error", "message": "用户不存在"}
        uname = user.username
    finally:
        db.close()

    key = key_fn(int(req.user_id))
    limit = limit_map[kind]
    try:
        import redis as _r
        r = _r.Redis()
        used = int(r.get(key) or 0)
        # delta>0 → 增加剩余 = 减少 used
        new_used = max(0, used - int(req.delta))
        if new_used == 0:
            r.delete(key)
        else:
            r.setex(key, sn._seconds_to_cst_midnight(), str(new_used))
        q = {
            "used": new_used,
            "limit": limit,
            "remaining": max(0, limit - new_used),
        }
        label = {"synth": "抢合", "presale": "抢购", "announce_lock": "公告锁定"}[kind]
        _admin_log(req.user_id, uname, "quota_adjust", f"{label} delta={req.delta} → 剩余{q['remaining']}")
        return {"status": "ok", "kind": kind, "quota": q}
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}


class CrawlerAuthReq(BaseModel):
    accessToken: str = ""
    refreshToken: str = ""
    deviceId: str = ""
    # 仅更新 access 时是否清掉旧 refresh（默认清，避免旧续期票拖死）
    clear_stale_refresh: bool = True


@router.get("/admin/crawler-auth")
def admin_crawler_auth_status(admin_token: str = Query("")):
    """新开寄售 / 索引爬虫凭证状态（不含明文票）。"""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    try:
        from crawler.ibox_auth import status as auth_status

        st = auth_status()
        left_h = round((st.get("left_s") or 0) / 3600, 2)
        import os as _os

        borrow_on = (_os.environ.get("IBOX_CRAWLER_BORROW_PRESENCE") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )
        if st.get("has_refresh"):
            hint = "专用号模式：有 refresh 时服务端自动续期；勿与科技页个人号共票"
        else:
            hint = (
                "缺 refreshToken：请用「短信登录的专用爬虫号」一次写入 access+refresh+deviceId"
                "（默认不再借用用户日活票）"
            )
        if borrow_on:
            hint += " · 警告：IBOX_CRAWLER_BORROW_PRESENCE=1 已开启借用户票"
        return {
            "status": "ok",
            **st,
            "left_h": left_h,
            "borrow_presence": borrow_on,
            "hint": hint,
        }
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}


@router.post("/admin/crawler-auth")
def admin_crawler_auth_set(req: CrawlerAuthReq, admin_token: str = Query("")):
    """写入爬虫 access + refresh（推荐一起给）。有 refresh 后 index_refresher 自动续期。"""
    if not _check_admin(admin_token=admin_token):
        return {"status": "error", "message": "未登录"}
    access = (req.accessToken or "").strip()
    refresh = (req.refreshToken or "").strip()
    device = (req.deviceId or "").strip()
    if not access and not refresh:
        return {"status": "error", "message": "需要 accessToken 或 refreshToken"}
    try:
        from crawler.ibox_auth import update_credentials, ensure_bearer, status as auth_status, _read_cfg, _write_cfg, _FileLock, _lock_path, _lock

        # 只更 access 且要求清旧 refresh：避免上次失效续期票占坑
        if access and not refresh and req.clear_stale_refresh:
            with _FileLock(_lock_path()):
                with _lock:
                    cfg = dict(_read_cfg())
                    cfg.pop("refreshToken", None)
                    cfg.pop("deadUntil", None)
                    _write_cfg(cfg)

        info = update_credentials(
            access_token=access,
            refresh_token=refresh,
            device_id=device,
        )
        # 有 refresh 时立刻试续期，确认票可用
        tok = ""
        refresh_ok = None
        if refresh or info.get("has_refresh"):
            tok = ensure_bearer(force=True, proactive=True) or ""
            refresh_ok = bool(tok)
        elif access:
            tok = ensure_bearer(proactive=False) or ""
            refresh_ok = None

        st = auth_status()
        _admin_log(
            0,
            "admin",
            "crawler_auth",
            "access={} refresh={} refresh_ok={}".format(
                bool(access), bool(refresh or st.get("has_refresh")), refresh_ok
            ),
        )
        return {
            "status": "ok" if (tok or st.get("has_access")) else "error",
            "token_ok": bool(tok),
            "refresh_ok": refresh_ok,
            "left_h": round((st.get("left_s") or 0) / 3600, 2),
            **st,
            **info,
            "message": (
                "已写入专用号；续期正常。请勿再把此号登录科技页/官方 App（共票会顶掉）"
                if refresh_ok
                else (
                    "已写入 access，但无可用 refresh——请用短信专用号补 refresh，否则过期后爬虫停"
                    if not st.get("has_refresh")
                    else "已写入，但 refresh 试续期失败，请换短信新登的专用号 refreshToken"
                )
            ),
        }
    except Exception as e:
        return {"status": "error", "message": str(e)[:200]}
