#!/usr/bin/env python3
"""Yad2 Ramat Aviv watch — houses & garden apartments, rent+sale (no_agent cron).

Silent unless: NEW listing within caps, RE-ADDED listing (מחודש: matches a removed
listing on street+rooms+sqm, reported with price delta), or a PRICE DROP.
First run seeds the state silently. 3+ consecutive empty scrapes -> one-time alarm.
State: ~/.hermes/cron/yad2-ra-watch-state.json  (seen + archive of removed listings)
"""
import asyncio, json, os, re, sys, time
from patchright.async_api import async_playwright

STATE_FILE = os.path.expanduser("~/.hermes/cron/yad2-ra-watch-state.json")
FORSALE_MAX = 12_000_000   # report new buys at/under this
RENT_MAX = 20_000          # report new rentals at/under this
URLS = {
    "forsale": "https://www.yad2.co.il/realestate/forsale/tel-aviv-area?area=1&city=5000&neighborhood=197",
    "rent": "https://www.yad2.co.il/realestate/rent/tel-aviv-area?area=1&city=5000&neighborhood=197",
}
LISTINGS_DIR = os.path.expanduser("~/.hermes/cron/yad2-listings")
KEEP_TYPES = ("בית פרטי", "קוטג", "דירת גן", "דו משפחתי", "דו-משפחתי")


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(st):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(tmp, STATE_FILE)


def norm_street(s):
    if not s:
        return ""
    s = re.sub(r"רמת אביב|תל אביב יפו|תל אביב", "", s)
    return re.sub(r"[\s,.\-]+", "", s)


def fingerprint(section, street, rnum, sqm):
    """stable identity for the same physical listing across listing IDs.
    Generic street text (just 'רמת אביב') is NOT identity — rooms+sqm alone would
    collide between different properties, so those get no fingerprint."""
    if not street or not rnum or not sqm:
        return None
    ns = norm_street(street)
    if not ns:
        return None
    return f"{section}|{ns}|{rnum:g}|{sqm}"


async def scrape():
    """walk the paginated list, read each page's __NEXT_DATA__ feed (full data incl.
    agency + photos — the DOM is virtualized and useless)"""
    out = {}
    feed_arrays = ("yad2", "platinum", "kingOfTheHar", "trio", "booster",
                   "leadingBroker", "lookalike")
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False, args=["--enable-unsafe-swiftshader"])
        ctx = await browser.new_context(locale="he-IL", viewport={"width": 1400, "height": 1000})
        pg = await ctx.new_page()
        for section, url in URLS.items():
            page = 1
            total_pages = 1
            while page <= total_pages and page <= 12:
                purl = url + (f"&page={page}" if page > 1 else "")
                try:
                    await pg.goto(purl, wait_until="domcontentloaded", timeout=90_000)
                    await pg.wait_for_timeout(7_000)
                    try:
                        await pg.get_by_text("הבנתי", exact=True).first.click(timeout=3000)
                    except Exception:
                        pass
                    await pg.wait_for_timeout(4_000)
                    nd = await pg.evaluate("""() => {
                        const el = document.getElementById('__NEXT_DATA__');
                        return el ? el.textContent : null;
                    }""")
                    if not nd:
                        print(f"{section} p{page}: no __NEXT_DATA__", file=sys.stderr)
                        break
                    feed = json.loads(nd)["props"]["pageProps"].get("feed", {})
                    total_pages = max(total_pages, int(feed.get("pagination", {}).get("totalPages") or 1))
                    added = 0
                    for arr in feed_arrays:
                        for m in feed.get(arr) or []:
                            tok = m.get("token")
                            if not tok or str(tok) in out:
                                continue
                            addr = m.get("address", {}) or {}
                            nb = (addr.get("neighborhood") or {}).get("id")
                            if nb not in (197, "197"):
                                continue
                            det = m.get("additionalDetails", {}) or {}
                            prop = ((det.get("property") or {}).get("text")) or ""
                            if not any(t in prop for t in KEEP_TYPES):
                                continue
                            try:
                                rnum_v = float(det["roomsCount"]) if det.get("roomsCount") is not None else None
                            except (TypeError, ValueError):
                                rnum_v = None
                            try:
                                sqm_v = int(det["squareMeter"]) if det.get("squareMeter") is not None else None
                            except (TypeError, ValueError):
                                sqm_v = None
                            street = ((addr.get("street") or {}).get("text")) or ""
                            hnum = (addr.get("house") or {}).get("number")
                            cust = m.get("customer", {}) or {}
                            out[str(tok)] = {
                                "price": m.get("price"),
                                "street": (street + (f" {hnum}" if hnum else "")).strip() or None,
                                "ptype": prop,
                                "rooms": f"{det.get('roomsCount')} חדרים" if det.get("roomsCount") else "",
                                "rnum": rnum_v,
                                "sqm": sqm_v,
                                "agency": cust.get("agencyName") or m.get("adType") or "",
                                "url": f"https://www.yad2.co.il/realestate/item/tel-aviv-area/{tok}",
                                "section": section,
                            }
                            added += 1
                    print(f"{section} p{page}: +{added} (total_pages={total_pages})", file=sys.stderr)
                    page += 1
                except Exception as e:
                    print(f"{section} p{page} fail: {type(e).__name__}", file=sys.stderr)
                    break
        await browser.close()
    return out


async def fetch_snapshots(lids):
    """per-item page fetch for REPORTED listings only (never bulk): snapshot
    description, photos, contact and publish dates to LISTINGS_DIR/<lid>.json"""
    if not lids:
        return {}
    os.makedirs(LISTINGS_DIR, exist_ok=True)
    snaps = {}
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False, args=["--enable-unsafe-swiftshader"])
        ctx = await browser.new_context(locale="he-IL", viewport={"width": 1400, "height": 1000})
        pg = await ctx.new_page()
        for lid in lids:
            try:
                await pg.goto(f"https://www.yad2.co.il/realestate/item/tel-aviv-area/{lid}",
                              wait_until="domcontentloaded", timeout=90_000)
                await pg.wait_for_timeout(8_000)
                try:
                    await pg.get_by_text("הבנתי", exact=True).first.click(timeout=3000)
                except Exception:
                    pass
                await pg.wait_for_timeout(4_000)
                nd = await pg.evaluate("""() => {
                    const el = document.getElementById('__NEXT_DATA__');
                    return el ? el.textContent : null;
                }""")
                if not nd:
                    print(f"snapshot {lid}: no __NEXT_DATA__", file=sys.stderr)
                    continue
                data = None
                for q in json.loads(nd)["props"]["pageProps"]["dehydratedState"]["queries"]:
                    k = q.get("queryKey") or []
                    if len(k) >= 2 and k[0] == "item" and str(k[1]) == lid:
                        data = q["state"]["data"]
                        break
                if not data:
                    print(f"snapshot {lid}: no item query", file=sys.stderr)
                    continue
                cust = data.get("customer", {}) or {}
                dates = data.get("dates", {}) or {}
                md = data.get("metaData", {}) or {}
                snaps[lid] = {
                    "token": lid,
                    "price": data.get("price"),
                    "address": data.get("address"),
                    "additionalDetails": data.get("additionalDetails"),
                    "description": md.get("description"),
                    "images": md.get("images") or [],
                    "contact": {"name": cust.get("name"), "agencyName": cust.get("agencyName"),
                                 "licenseNumber": cust.get("licenseNumber"),
                                 "brokers": [b.get("name") for b in cust.get("brokers") or []]},
                    "dates": dates,
                    "fetched_at": time.strftime("%Y-%m-%d %H:%M"),
                }
                path = os.path.join(LISTINGS_DIR, f"{lid}.json")
                tmp = path + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(snaps[lid], f, ensure_ascii=False)
                os.replace(tmp, path)
            except Exception as e:
                print(f"snapshot {lid} failed: {type(e).__name__}", file=sys.stderr)
        await browser.close()
    return snaps


def main():
    st = load_state()
    seen = st.get("seen", {})
    archive = st.get("archive", {})
    fails = st.get("consec_fails", 0)
    first_run = not seen
    try:
        cur = asyncio.run(scrape())
    except Exception as e:
        print(f"scrape crashed: {type(e).__name__}", file=sys.stderr)
        cur = {}

    if not cur:
        st["consec_fails"] = fails + 1
        if st["consec_fails"] >= 3 and not st.get("broken_sent"):
            print(f"⚠️ צפיית רמת אביב: 3 סריקות רצופות לא החזירו נכסים — כדאי לבדוק ידנית")
            st["broken_sent"] = True
        save_state(st)
        return
    st["consec_fails"] = 0
    st["broken_sent"] = False

    # run log — why did/didn't reports fire; diagnosable history
    try:
        with open(STATE_FILE.replace(".json", ".log"), "a") as lf:
            lf.write(f"{time.strftime('%Y-%m-%d %H:%M')} parsed={len(cur)} "
                     f"seen={len(seen)} first_run={first_run}\n")
    except Exception:
        pass

    # degraded-scrape guard: if this run parsed far fewer house listings than the peak
    # ever seen, treat it as a partial feed (anti-bot/lazy-load) — freeze misses so
    # healthy listings are not mass-pruned and later re-reported as duplicates.
    houses_now = sum(1 for v in cur.values() if any(t in v["ptype"] for t in KEEP_TYPES))
    peak = st.get("peak_houses", 0)
    st["peak_houses"] = max(peak, houses_now)
    degraded = peak >= 8 and houses_now < peak * 0.85
    if degraded:
        # re-baseline so genuine market shrink doesn't freeze pruning forever
        st["peak_houses"] = houses_now

    reports = []
    archive_hits = []
    reported_lids = []
    for lid, cur_d in cur.items():
        is_house = any(t in cur_d["ptype"] for t in KEEP_TYPES)
        if not is_house:
            continue
        prev = seen.get(lid)
        cap = RENT_MAX if cur_d["section"] == "rent" else FORSALE_MAX
        addr = cur_d["street"] or "רמת אביב"
        if prev is None:
            if not first_run and (cur_d["price"] is None or cur_d["price"] <= cap):
                icon = "🏠" if "בית" in cur_d["ptype"] or "קוטג" in cur_d["ptype"] else "🌱"
                fp = fingerprint(cur_d["section"], cur_d["street"], cur_d["rnum"], cur_d["sqm"])
                old = None
                if fp:
                    # prefer a LIVE twin (cross-ID dupe) over a stale archive entry
                    for olid, o in seen.items():
                        if olid != lid and fingerprint(o.get("section"), o.get("street"),
                                                       o.get("rnum"), o.get("sqm")) == fp:
                            old = {"price": o.get("price"), "lid": olid, "last_seen": None}
                            break
                if not old and fp:
                    old = archive.get(fp)
                    if old and time.time() - old.get("last_seen", 0) > 90 * 86400:
                        archive.pop(fp, None)  # stale: old price would be misleading
                        old = None
                if old:
                    if cur_d["price"] is None or old.get("price") is None:
                        archive_hits.append(fp)  # can't compute delta — clear match silently
                    else:
                        delta = cur_d["price"] - old["price"]
                        if delta != 0:
                            sign = "+" if delta >= 0 else ""
                            pct = (abs(delta) * 100 // old["price"]) if old["price"] else 0
                            ago = ""
                            if old.get("last_seen"):
                                days = int((time.time() - old["last_seen"]) / 86400)
                                ago = f" · הוסר לפני ~{days} ימים" if days >= 1 else " · הוסר לאחרונה"
                            reports.append({"lid": lid,
                                            "text": f"{icon} 🔄 מחודש · {addr}\n{cur_d['ptype']} · {cur_d['rooms']}\n"
                                                    f"₪{old['price']:,} → **₪{cur_d['price']:,}** ({sign}{delta:,} / {sign}{pct}%){ago}\n"
                                                    f"ישן: {old.get('lid')} · חדש: {lid}\n{cur_d['url']}"})
                            reported_lids.append(lid)
                        archive_hits.append(fp)
                else:
                    price_s = f"**₪{cur_d['price']:,}**" if cur_d["price"] else "מחיר לא צוין"
                    reports.append({"lid": lid,
                                    "text": f"{icon} 🟢 חדש · {addr}\n{cur_d['ptype']} · {cur_d['rooms']}\n"
                                            f"{price_s}\n{cur_d['url']}"})
                    reported_lids.append(lid)
        elif cur_d["price"] is not None and prev.get("price") is not None and cur_d["price"] < prev["price"]:
            drop = prev["price"] - cur_d["price"]
            pct = drop * 100 // prev["price"]
            reports.append({"lid": lid,
                            "text": f"🔻 ירידת מחיר · {addr}\n{cur_d['ptype']} · {cur_d['rooms']}\n"
                                    f"₪{prev['price']:,} → **₪{cur_d['price']:,}** (-{drop:,} / -{pct}%)\n{cur_d['url']}"})
            reported_lids.append(lid)

    # keep known ids across flicker: only prune after 3 consecutive absent scrapes
    seen.update({k: {"price": v["price"], "misses": 0, "street": v["street"],
                     "rnum": v["rnum"], "sqm": v["sqm"], "section": v["section"],
                     "agency": v["agency"]}
                 for k, v in cur.items() if any(t in v["ptype"] for t in KEEP_TYPES)})
    for k in list(seen):
        if k not in cur:
            if degraded:
                seen[k]["misses"] = 0  # partial feed — don't punish absent listings
                continue
            seen[k]["misses"] = seen[k].get("misses", 0) + 1
            if seen[k]["misses"] >= 3:
                gone = seen.pop(k)
                fp = fingerprint(gone.get("section"), gone.get("street"),
                                 gone.get("rnum"), gone.get("sqm"))
                if fp:
                    archive[fp] = {"price": gone["price"], "lid": k,
                                   "last_seen": time.time()}
    # archive entries that just re-appeared are cleared so the same match isn't re-reported
    for fp in archive_hits:
        archive.pop(fp, None)
    if len(archive) > 400:
        for k in sorted(archive, key=lambda x: archive[x].get("last_seen", 0))[:len(archive) - 400]:
            del archive[k]
    st["archive"] = archive
    st["last_ok"] = time.time()
    save_state(st)

    if reports:
        # snapshot reported listings (description/photos/contact/dates) + enrich reports
        try:
            snaps = asyncio.run(fetch_snapshots(reported_lids))
        except Exception as e:
            print(f"snapshot fetch failed: {type(e).__name__}", file=sys.stderr)
            snaps = {}
        for r in reports:
            s = snaps.get(r["lid"])
            if not s:
                continue
            extra = ""
            c = s.get("contact") or {}
            who = c.get("name") or ""
            agency = c.get("agencyName") or ""
            label = " · ".join(dict.fromkeys(x for x in (who, agency) if x))
            if label:
                extra += f"📞 {label}"
                if c.get("licenseNumber"):
                    extra += f" (רישיון {c['licenseNumber']})"
            d = s.get("dates") or {}
            created = (d.get("createdAt") or "")[:10]
            rebounced = (d.get("rebouncedAt") or "")[:10]
            if created and rebounced and rebounced > created:
                extra += f"\n🗓️ פורסם {created} · פורסם מחדש {rebounced}"
            elif created:
                extra += f"\n🗓️ פורסם {created}"
            imgs = s.get("images") or []
            if imgs:
                extra += f"\n🖼️ {len(imgs)} תמונות: {imgs[0]}"
            if extra:
                r["text"] += "\n" + extra
        print("רמת אביב — בתים ודירות גן 🔎\n\n" + "\n\n".join(r["text"] for r in reports))


if __name__ == "__main__":
    main()
