#!/usr/bin/env python3
"""
Ledgerly LLM gateway log generator.

Usage:
    python generator/generate.py                 # random seed, full ~5M rows
    python generator/generate.py --scale 0.05    # smoke test (~250k rows)
    python generator/generate.py --seed 42       # reproducible

Writes analysis inputs to --out (default data/) and the SEALED answer key to
--key-dir (default answer_key/). Do not open the key until your analysis is done.
All prices and volumes are illustrative, not any vendor's real numbers.
"""
import argparse, json, os, time
import numpy as np
import pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=None)
ap.add_argument("--scale", type=float, default=1.0, help="row-volume multiplier")
ap.add_argument("--out", default="data")
ap.add_argument("--key-dir", default="answer_key")
args = ap.parse_args()

SEED = args.seed if args.seed is not None else int(time.time()) % (2**31)
rng = np.random.default_rng(SEED)
os.makedirs(args.out, exist_ok=True)
os.makedirs(args.key_dir, exist_ok=True)
t_start = time.time()

# ------------------------------------------------------------------ config
TARGET_ROWS = int(5_150_000 * args.scale)
TOKEN_SCALE = 2.0          # tuned so monthly spend lands ~ $7k (Apr) -> ~$34k (Sep)
START = pd.Timestamp("2026-04-01")
ND = 183                    # 1 Apr .. 30 Sep
T0 = START.value            # ns
days = START + pd.to_timedelta(np.arange(ND), "D")
dow, dom = days.dayofweek.values, days.day.values
d = np.arange(ND)
PRICE_CUT_DAY, MD2_DAY = 105, 131          # 15 Jul, 10 Aug
MODELS = ["lg-1", "md-1", "sm-1", "md-2"]
MSTOK = np.array([14.0, 8.0, 4.0, 7.0])    # ms per generated token
VERB = np.array([0.9, 1.0, 1.3, 1.05])     # output verbosity by model

cols = ["name", "cf", "inter", "turns", "share", "p_med", "p_sig", "o_med", "o_sig",
        "hit_p", "p_lg", "p_md", "p_sm", "launch", "fin", "owner"]
F = pd.DataFrame([
    ("txn_categorization", 1, 0, 1.0, .30, 2500, .45, 40, .50, .85, 0, .3, .7, 0, 1, "Accounting"),
    ("vendor_matching", 1, 0, 1.0, .10, 3000, .45, 60, .50, .80, 0, .4, .6, 0, 1, "Accounting"),
    ("receipt_ocr_cleanup", 1, 0, 1.0, .10, 3000, .45, 180, .50, .80, 0, .6, .4, 0, 1, "Expenses"),
    ("invoice_extraction", 1, 0, 1.0, .12, 9000, .60, 400, .50, .08, .3, .7, 0, 0, 1, "Accounting"),
    ("expense_policy_check", 1, 0, 1.0, .06, 5000, .40, 120, .40, .80, 0, .7, .3, 0, 1, "Expenses"),
    ("support_copilot", 1, 1, 3.2, .14, 8000, .40, 380, .50, .55, .5, .5, 0, 0, 0, "Support Eng"),
    ("ask_ledgerly", 1, 1, 2.8, .07, 9000, .50, 600, .60, .06, .7, .3, 0, 0, 0, "Product AI"),
    ("report_summarizer", 1, 1, 1.0, .03, 18000, .50, 500, .40, .07, .6, .4, 0, 30, 0, "Product AI"),
    ("collections_drafter", 1, 1, 1.0, .08, 8000, .40, 650, .40, .75, .8, .2, 0, 70, 1, "Collections"),
    ("sales_call_summary", 0, 0, 1.0, 0, 14000, .45, 600, .40, .80, 1, 0, 0, 0, 0, "Sales Ops"),
    ("eng_assistant", 0, 1, 4.0, 0, 9000, .50, 800, .60, .50, .8, .2, 0, 0, 0, "Engineering"),
    ("internal_triage", 0, 0, 1.0, 0, 1500, .50, 90, .50, .85, 0, .2, .8, 0, 0, "Support Ops"),
], columns=cols)
NF, NEXT = len(F), 9
# a few features have prompts structured so the static prefix is NOT first -> poor cache hits
POOR = ["invoice_extraction", "ask_ledgerly", "report_summarizer"]
F.loc[F.name.isin(POOR), "hit_p"] = rng.uniform(0.04, 0.12, len(POOR))
MT = F.turns.values
INTER = F.inter.values.astype(bool)
FIN = F.fin.values.astype(bool)

# ------------------------------------------------------------------ tenants
N = 900
plan = rng.choice(["Starter", "Growth", "Scale"], N, p=[.55, .33, .12])
seats = np.where(plan == "Starter", rng.integers(2, 13, N),
         np.where(plan == "Growth", rng.integers(10, 61, N), rng.integers(50, 251, N)))
pre = rng.random(N) < .61
signup_off = np.where(pre, -rng.integers(1, 900, N), rng.integers(0, 168, N))
adopt = rng.random(N) < np.where(pre, .85, .80)
ai_start = np.where(pre, np.where(rng.random(N) < .35, 0, rng.integers(0, 150, N)),
                    signup_off + rng.integers(0, 21, N))
adopt &= ai_start < ND - 3
ai_seats = np.where(adopt, np.maximum(1, np.round(seats * rng.uniform(.3, 1, N))).astype(int), 0)
ADDON_PRICE = 12.0
mrr = ai_seats * ADDON_PRICE

m = rng.lognormal(0, .7, N)
m /= m[adopt].mean()
cand = np.where(adopt & (plan != "Scale") & (ai_seats <= 10))[0]
uw = rng.choice(cand, 12, replace=False)       # "underwater" tenants (planted)
m[uw] *= 22

use_p = np.tile(np.array([.9, .6, .55, .8, .35, .75, .45, .3, .5]), (N, 1))
use_p[plan == "Starter", 8] = 0.0                       # collections: Growth/Scale only
use_p[plan == "Scale", 6:8] *= 1.3
use = rng.random((N, NEXT)) < use_p
use[uw, 6] = True
use[uw, 7] = True
W = F.share.values[:NEXT] * use * rng.gamma(2, .5, (N, NEXT))
W[uw, 6] *= 6
W[uw, 7] *= 6
dead = W.sum(1) == 0
W[dead, 0] = 1.0
W /= W.sum(1, keepdims=True)

# ------------------------------------------------------------------ caps (planted quasi-experiment)
starter_sc = np.where(adopt & (plan == "Starter") & (W[:, 5] > 0) & (ai_start < 120))[0]
order = starter_sc[np.argsort(-(m[starter_sc] * W[starter_sc, 5]))]   # heaviest first = NOT random
capped = order[: int(.65 * len(order))]
n1, n2 = int(.4 * len(capped)), int(.3 * len(capped))
wave = np.r_[np.full(n1, 1), np.full(n2, 2), np.full(len(capped) - n1 - n2, 3)]
wave_day = {1: 125, 2: 132, 3: 139}                                   # 4, 11, 18 Aug
CAP_EFFECT = float(rng.uniform(-.30, -.14))                           # true change in copilot requests
cap_day = np.full(N + 1, 10**6)
cap_eff = np.zeros(N + 1)
for t, w in zip(capped, wave):
    cap_day[t] = wave_day[w]
    cap_eff[t] = CAP_EFFECT

# ------------------------------------------------------------------ expected volumes
g = 1 + .8 * d / (ND - 1)
active = (d[None, :] >= ai_start[:, None]) & adopt[:, None]
ramp = .35 + .65 * np.clip((d[None, :] - ai_start[:, None]) / 30, 0, 1)
tenant_day = ai_seats[:, None] * m[:, None] * g[None, :] * active * ramp
dow_i = np.array([1, 1, 1, 1, 1, .22, .12])[dow]
dow_n = np.array([1, 1, 1, 1, 1, .55, .45])[dow]
mend = np.where(dom >= 27, 1.45, 1.0)
avail = np.ones((ND, NEXT))
avail[:, 7] = (d >= 30)
avail[:, 8] = (d >= 70)
featfac = np.where(INTER[None, :NEXT], dow_i[:, None], dow_n[:, None]) * \
          np.where(FIN[None, :NEXT], mend[:, None], 1.0) * avail
lam_ext = tenant_day[:, :, None] * W[:, None, :] * featfac[None, :, :]
bf = ((~pre) & adopt)[:, None] & (d[None, :] >= ai_start[:, None]) & (d[None, :] < ai_start[:, None] + 5)
lam_ext[:, :, [2, 3]] *= (1 + 5 * bf)[:, :, None]                      # onboarding backfill bursts
capmult = np.where(d[None, :] >= cap_day[:N, None], 1 + cap_eff[:N, None], 1.0)
lam_ext[:, :, 5] *= capmult

lam = np.zeros((N + 1, ND, NF))
ramp_int = d / (ND - 1)
for j, (a, b) in zip([9, 10, 11], [(20, 60), (450, 1000), (300, 900)]):
    lam[N, :, j] = (a + (b - a) * ramp_int) * dow_n * args.scale
internal_rows = lam[N].sum()
TARGET_EXT = max(TARGET_ROWS / 1.06 - internal_rows, 1000)
lam[:N, :, :NEXT] = lam_ext * (TARGET_EXT / lam_ext.sum())
lam_sess = lam / MT[None, None, :]

POOL = np.r_[ai_seats, 120]
TDOC = np.exp(rng.normal(0, .25, N + 1))
TEN_ID = np.array([f"T{i + 1:04d}" for i in range(N)] + ["INTERNAL"])
REASON_FEATS = [6, 7, 10]

# ------------------------------------------------------------------ helpers
ctr = {"uid": 0, "sid": 0}


def outcome(prompt, gen, model):
    n = len(prompt)
    lat = 350 + prompt / 60 + gen * MSTOK[model] * rng.lognormal(0, .35, n)
    lat = np.where(rng.random(n) < .012, lat * rng.uniform(3, 9, n), lat)
    slow = lat > 30000                                   # client times out at 30 s
    ghost = slow & (rng.random(n) < .6)                  # server finished anyway -> logged ok, billed
    status = np.zeros(n, np.int8)                        # 0 ok, 1 error, 2 timeout, 3 rate_limited
    status[slow & ~ghost] = 2
    lat = np.where(slow & ~ghost, 30000, np.minimum(lat, 120000))
    err = (~slow) & (rng.random(n) < (.010 + .006 * (model == 0)))
    status[err] = 1
    lat = np.where(err, rng.uniform(150, 1800, n), lat)
    return lat.astype(np.int32), status, ghost


def children(par):
    need = (par.status.values != 0) | par.ghost.values
    pr = np.where(par.status.values == 1, .7, .9)
    pick = need & (rng.random(len(par)) < pr)
    ch = par.loc[pick].copy()
    n = len(ch)
    if n == 0:
        return ch
    ch["retry_of"] = ch["uid"].values
    ch["uid"] = np.arange(ctr["uid"], ctr["uid"] + n)
    ctr["uid"] += n
    wait = np.minimum(ch.lat.values, 30000) / 1e3 + rng.uniform(1, 6, n)
    ch["ts"] = ch.ts.values + (wait * 1e9).astype(np.int64)
    lat, st, gh = outcome(ch.prompt.values, ch.gen.values + ch.reason.values, ch.model.values)
    ch["lat"], ch["status"], ch["ghost"] = lat, st, gh
    return ch


def compact(df):
    return df.astype({"ten": "int16", "feat": "int8", "model": "int8", "prompt": "int32",
                      "gen": "int32", "reason": "int32", "lat": "int32", "status": "int8",
                      "turn": "int16"})


# ------------------------------------------------------------------ main generation (month by month)
months = days.to_period("M")
chunks = []
for p in months.unique():
    dsel = np.where(months == p)[0]
    lo, hi = dsel[0], dsel[-1] + 1
    cnt = rng.poisson(lam_sess[:, lo:hi, :])
    ti, di, fi = np.nonzero(cnt)
    c = cnt[ti, di, fi]
    s_t, s_d, s_f = np.repeat(ti, c), np.repeat(di + lo, c), np.repeat(fi, c)
    ns = len(s_t)
    turns = np.ones(ns, np.int64)
    mm = MT[s_f] > 1
    turns[mm] = np.minimum(rng.geometric(1 / MT[s_f[mm]]), 25)
    rep = np.repeat(np.arange(ns), turns)
    nr = len(rep)
    first = np.cumsum(turns) - turns
    turn = np.arange(nr) - np.repeat(first, turns) + 1

    base = F.p_med.values[s_f] * np.exp(rng.normal(0, F.p_sig.values[s_f])) * TDOC[s_t] * TOKEN_SCALE
    pm = F[["p_lg", "p_md", "p_sm"]].values[s_f]
    r = rng.random(ns)
    model = (r > pm[:, 0]).astype(np.int8) + (r > pm[:, 0] + pm[:, 1]).astype(np.int8)
    mig = (model == 1) & (s_d >= MD2_DAY) & (rng.random(ns) < np.minimum(1, (s_d - MD2_DAY) / 20) * .9)
    model[mig] = 3

    f_r, m_r = s_f[rep], model[rep]
    gen = np.clip(F.o_med.values[f_r] * np.exp(rng.normal(0, F.o_sig.values[f_r])) * VERB[m_r], 1, 6000)
    reason = np.where(np.isin(f_r, REASON_FEATS) & (m_r == 0), gen * rng.uniform(.3, 1.2, nr), 0)
    x = gen + 140
    prior = np.cumsum(x) - x
    hist = np.where(MT[f_r] > 1, prior - np.repeat(prior[first], turns), 0)
    prompt = np.clip(base[rep] * np.exp(rng.normal(0, .08, nr)) + hist, 50, 150000)

    inter = INTER[s_f]
    batch = (~inter) & (rng.random(ns) < .7)
    hr = np.where(batch, rng.uniform(1, 5, ns), np.clip(rng.normal(12, 3.2, ns), 5, 20))
    gap = np.where(turn > 1, 20 + rng.exponential(70, nr), 0.0)
    cg = np.cumsum(gap)
    cg = cg - np.repeat((cg - gap)[first], turns)
    ts = ((s_d * 86400 + hr * 3600)[rep] + cg) * 1e9
    ts = ts.astype(np.int64) + T0

    u = np.floor(POOL[s_t] * rng.random(ns) ** 1.6).astype(np.int64) + 1
    svc = (~inter) & (s_t < N) & (rng.random(ns) < .85)
    user_s = (s_t + 1) * 10000 + np.where(svc, 9999, u)
    sid = np.where(MT[s_f] > 1, ctr["sid"] + np.arange(ns), -1)
    ctr["sid"] += ns

    lat, status, ghost = outcome(prompt, gen + reason, m_r)
    df = pd.DataFrame({
        "uid": np.arange(ctr["uid"], ctr["uid"] + nr), "ts": ts, "ten": s_t[rep], "user": user_s[rep],
        "sess": sid[rep], "feat": f_r, "model": m_r, "prompt": prompt.astype(np.int32),
        "gen": gen.astype(np.int32), "reason": reason.astype(np.int32), "lat": lat, "status": status,
        "ghost": ghost, "turn": turn, "retry_of": -1})
    ctr["uid"] += nr
    df = compact(df)
    parts, par = [df], df
    for _ in range(3):
        ch = children(par)
        if len(ch) == 0:
            break
        parts.append(ch)
        par = ch
    chunks.append(pd.concat(parts, ignore_index=True))
    del cnt, df, parts
    print(f"  generated {p}: {len(chunks[-1]):,} rows  ({time.time() - t_start:.0f}s)", flush=True)

# ------------------------------------------------------------------ storm: runaway retry loop (planted)
storm_cand = np.where(adopt & (plan == "Growth") & use[:, 3] & (ai_start < 100))[0]
storm_ten = int(rng.choice(storm_cand))
storm_day = int(rng.integers(140, 175))
n_roots = max(int(15000 * args.scale), 50)
L = np.minimum(rng.geometric(.22, n_roots), 15)
rep = np.repeat(np.arange(n_roots), L)
first = np.cumsum(L) - L
k = np.arange(len(rep)) - np.repeat(first, L)
gaps = np.where(k > 0, rng.uniform(1, 3, len(rep)), 0)
cgs = np.cumsum(gaps)
cgs = cgs - np.repeat((cgs - gaps)[first], L)
st0 = storm_day * 86400 + rng.uniform(13, 15.5, n_roots) * 3600
sp = (F.p_med[3] * TDOC[storm_ten] * np.exp(rng.normal(0, .3, n_roots)) * TOKEN_SCALE)[rep]
last = (k == L[rep] - 1) & (L[rep] < 15)
sm_status = np.where(last, 0, 1).astype(np.int8)
sm_lat = np.where(last, 350 + sp / 60 + 450 * 14 * rng.lognormal(0, .3, len(rep)), rng.uniform(150, 1800, len(rep)))
n_s = len(rep)
uids = np.arange(ctr["uid"], ctr["uid"] + n_s)
ctr["uid"] += n_s
storm = pd.DataFrame({
    "uid": uids, "ts": ((st0[rep] + cgs) * 1e9).astype(np.int64) + T0, "ten": storm_ten,
    "user": (storm_ten + 1) * 10000 + 9999, "sess": -1, "feat": 3, "model": 0,
    "prompt": sp.astype(np.int32), "gen": 450, "reason": 0, "lat": sm_lat.astype(np.int32),
    "status": sm_status, "ghost": False, "turn": 1,
    "retry_of": np.where(k > 0, uids - 1, -1)})
chunks.append(compact(storm))

al = pd.concat(chunks, ignore_index=True)
del chunks
al = compact(al)

# ------------------------------------------------------------------ rate-limited rows from the cap (not billed)
day_r = (al.ts.values - T0) // (86400 * 10**9)
cond = (al.feat.values == 5) & (al.status.values == 0) & (al.retry_of.values == -1) & \
       (day_r >= cap_day[al.ten.values])
ce = cap_eff[al.ten.values]
prl = np.where(cond, .35 * (-ce) / (1 + ce), 0)
pick = rng.random(len(al)) < prl
rl = al.loc[pick].copy()
n = len(rl)
rl["uid"] = np.arange(ctr["uid"], ctr["uid"] + n)
ctr["uid"] += n
rl["ts"] = rl.ts.values - (rng.uniform(2, 60, n) * 1e9).astype(np.int64)
rl["status"] = np.int8(3)
rl["lat"] = rng.integers(20, 120, n).astype(np.int32)
rl["ghost"] = False
rl["retry_of"] = -1
al = pd.concat([al, rl], ignore_index=True)
del rl

# ------------------------------------------------------------------ sort, final ids
order = np.argsort(al.ts.values, kind="stable")
al = al.iloc[order].reset_index(drop=True)
uid_map = np.zeros(ctr["uid"] + 1, np.int64)
uid_map[al.uid.values] = np.arange(1, len(al) + 1)
al["request_id"] = np.arange(1, len(al) + 1)
al["retry_of"] = np.where(al.retry_of.values >= 0, uid_map[np.maximum(al.retry_of.values, 0)], 0)
M = len(al)

# ------------------------------------------------------------------ caching
o2 = np.lexsort((al.ts.values, al.feat.values, al.ten.values))
ts_s, ten_s, feat_s = al.ts.values[o2], al.ten.values[o2], al.feat.values[o2]
gap_s = np.full(M, 1e12)
same = (ten_s[1:] == ten_s[:-1]) & (feat_s[1:] == feat_s[:-1])
gap_s[1:] = np.where(same, (ts_s[1:] - ts_s[:-1]) / 1e9, 1e12)
gap_gw = np.empty(M)
gap_gw[o2] = gap_s
hp = F.hit_p.values[al.feat.values]
poor = np.isin(al.feat.values, [F.index[F.name == nme][0] for nme in POOR])
elig = (al.prompt.values >= 1024) & (al.status.values != 3)
hit = elig & (rng.random(M) < np.where(gap_gw <= 300, hp, .03))
pf = np.where(poor, rng.uniform(.10, .35, M), rng.uniform(.60, .90, M))
al["cached"] = (al.prompt.values * pf * hit).astype(np.int32)

# ------------------------------------------------------------------ cost (true billing rules)
ts_ = al.ts.values
cut = (pd.Timestamp("2026-07-15")).value
mo = al.model.values
pin = np.select([mo == 0, mo == 1, mo == 2, mo == 3], [np.where(ts_ < cut, 5.0, 3.0), 1.0, .25, .8])
pout = np.select([mo == 0, mo == 1, mo == 2, mo == 3], [np.where(ts_ < cut, 15.0, 9.0), 4.0, 1.0, 3.2])
okm = al.status.values == 0
billed = al.status.values != 3
cost = ((al.prompt.values - al.cached.values) * pin + al.cached.values * pin * .1
        + np.where(okm, al.gen.values + al.reason.values, 0) * pout) / 1e6 * billed
al["cost"] = cost

# ------------------------------------------------------------------ thumbs, finish_reason
inter_row = INTER[al.feat.values]
th = okm & inter_row & (rng.random(M) < .03)
down = rng.random(M) < np.array([.18, .22, .35, .22])[mo]
thumbs = pd.array(np.where(th, np.where(down, -1, 1), 0), dtype="Int8")
thumbs[~th] = pd.NA
finish = np.where(okm, np.where(rng.random(M) < .015, "length", "stop"), None)

# ------------------------------------------------------------------ untagged feature_id (defect)
pnull = np.where(al.feat.values == 0, .08, np.where(al.feat.values == 1, .07, .0108))
isnull = rng.random(M) < pnull
true_feat = pd.DataFrame({"request_id": al.request_id.values[isnull],
                          "true_feature_id": F.name.values[al.feat.values[isnull]]})
feat_out = pd.Categorical(F.name.values[al.feat.values], categories=list(F.name))
feat_out = pd.Series(feat_out).where(~isnull)

# ------------------------------------------------------------------ model aliases (defect)
alias = {"lg-1": "LG-1", "md-1": "md-1-latest", "sm-1": "sm1", "md-2": "md-2"}
mname = np.array(MODELS)[mo].astype(object)
al_pick = rng.random(M) < .025
mname[al_pick] = np.array([alias[x] for x in mname[al_pick]], dtype=object)

# ------------------------------------------------------------------ eval sample (planted selection bias)
A = {0: 3.2, 1: 2.8, 2: 2.6, 3: 1.6, 4: 2.0, 5: 1.2, 6: .2, 7: .5, 8: .9}
cf_r = F.cf.values[al.feat.values].astype(bool)
cand_e = okm & cf_r & (mo != 2) & (al.retry_of.values == 0)
pool_r = np.where(cand_e)[0]
pool_f = np.where(cand_e & (np.asarray(thumbs.fillna(0)) == -1))[0]
n_e = int(1500 * min(1.0, max(args.scale * 4, .1)))
pick_f = rng.choice(pool_f, min(int(.35 * n_e), len(pool_f)), replace=False)
pick_r = rng.choice(np.setdiff1d(pool_r, pick_f), n_e - len(pick_f), replace=False)
pick_e = np.r_[pick_r, pick_f]
a_vec = np.array([A.get(int(f), 1.5) for f in al.feat.values[pick_e]])
logit = a_vec - .55 * np.log(al.prompt.values[pick_e] / 2000) - .25 * (al.turn.values[pick_e] - 1) \
        + rng.normal(0, .6, len(pick_e)) - .8 * (np.r_[np.zeros(len(pick_r)), np.ones(len(pick_f))])
passed = rng.random(len(pick_e)) < 1 / (1 + np.exp(-logit))
eval_df = pd.DataFrame({"request_id": al.request_id.values[pick_e], "model_tested": "sm-1",
                        "pass_fail": np.where(passed, "pass", "fail")}).sample(frac=1, random_state=1)

# ------------------------------------------------------------------ assemble fact table
st_names = np.array(["ok", "error", "timeout", "rate_limited"])
fact = pd.DataFrame({
    "request_id": al.request_id.values,
    "ts_utc": pd.to_datetime(al.ts.values),
    "tenant_id": pd.Categorical(TEN_ID[al.ten.values]),
    "user_id": al.user.values,
    "session_id": pd.array(np.where(al.sess.values >= 0, al.sess.values + 1, 0), dtype="Int64"),
    "feature_id": feat_out.values,
    "model": pd.Categorical(mname),
    "prompt_tokens": al.prompt.values,
    "cached_tokens": al.cached.values,
    "completion_tokens": pd.array(np.where(okm, al.gen.values, 0), dtype="Int32"),
    "reasoning_tokens": pd.array(np.where(okm, al.reason.values, 0), dtype="Int32"),
    "latency_ms": al.lat.values,
    "status": pd.Categorical(st_names[al.status.values]),
    "retry_of": pd.array(np.where(al.retry_of.values > 0, al.retry_of.values, 0), dtype="Int64"),
    "finish_reason": pd.Categorical(finish),
    "thumbs": thumbs,
})
fact.loc[fact.session_id == 0, "session_id"] = pd.NA
fact.loc[fact.retry_of == 0, "retry_of"] = pd.NA
fact.loc[~okm, ["completion_tokens", "reasoning_tokens"]] = pd.NA
fact.to_parquet(f"{args.out}/fact_llm_requests.parquet", compression="zstd", index=False)

# ------------------------------------------------------------------ dimension tables
dim_tenant = pd.DataFrame({
    "tenant_id": TEN_ID[:N], "plan_tier": plan, "seats": seats, "ai_addon_seats": ai_seats,
    "ai_addon_mrr": mrr, "signup_date": (START + pd.to_timedelta(signup_off, "D")).date})
dim_tenant = pd.concat([dim_tenant, pd.DataFrame([{
    "tenant_id": "INTERNAL", "plan_tier": "internal", "seats": 120, "ai_addon_seats": 0,
    "ai_addon_mrr": 0.0, "signup_date": pd.Timestamp("2025-01-01").date()}])], ignore_index=True)
dim_tenant.to_parquet(f"{args.out}/dim_tenant.parquet", index=False)

pd.DataFrame({"feature_id": F.name, "is_customer_facing": F.cf.astype(bool),
              "is_interactive": F.inter.astype(bool), "owner_team": F.owner,
              "launch_date": (START + pd.to_timedelta(F.launch.values, "D")).date}) \
    .to_parquet(f"{args.out}/dim_feature.parquet", index=False)

dim_price = pd.DataFrame([
    ("lg-1", "2026-04-01", "2026-07-14", 5.00, .50, 15.00),
    ("lg-1", "2026-07-15", None, 3.00, .30, 9.00),
    ("md-1", "2026-04-01", None, 1.00, .10, 4.00),
    ("sm-1", "2026-04-01", None, .25, .025, 1.00),
    ("md-2", "2026-08-10", None, .80, .08, 3.20)],
    columns=["model", "effective_from", "effective_to", "input_per_1m", "cached_input_per_1m", "output_per_1m"])
dim_price.to_parquet(f"{args.out}/dim_price.parquet", index=False)

pd.DataFrame({"tenant_id": TEN_ID[capped], "wave": wave,
              "cap_start_date": [(START + pd.Timedelta(days=wave_day[w])).date() for w in wave],
              "cap_level": 25}).to_parquet(f"{args.out}/cap_rollout.parquet", index=False)
eval_df.to_parquet(f"{args.out}/eval_sample.parquet", index=False)

inv = pd.DataFrame({"month": fact.ts_utc.dt.strftime("%Y-%m"), "c": cost}).groupby("month").c.sum().round(2)
inv.rename("invoiced_usd").reset_index().to_csv(f"{args.out}/vendor_invoice.csv", index=False)

# ------------------------------------------------------------------ sealed answer key
true_feat.to_parquet(f"{args.key_dir}/true_feature_for_untagged.parquet", index=False)
pd.DataFrame({"tenant_id": TEN_ID[:N], "intensity": m, "underwater_planted": np.isin(np.arange(N), uw),
              "storm_tenant": np.arange(N) == storm_ten}).to_csv(f"{args.key_dir}/tenant_truth.csv", index=False)
key = {
    "seed": SEED,
    "cap_true_effect_on_support_copilot_requests": CAP_EFFECT,
    "cap_assignment": "heaviest support_copilot Starter tenants first (non-random); waves 40/30/30%",
    "storm": {"tenant_idx": storm_ten, "tenant_id": TEN_ID[storm_ten], "day_offset": storm_day,
              "window_utc": "13:00-15:30", "roots": int(n_roots)},
    "poorly_cached_features": dict(zip(POOR, F.loc[F.name.isin(POOR), "hit_p"].round(3).tolist())),
    "eval_sample_bias": "35% of eval rows drawn from thumbs-down requests, which are harder",
    "model_aliases": alias, "price_cut": "lg-1 -40% from 2026-07-15", "md2_release": "2026-08-10",
    "ghost_retries": "requests >30s: 60% completed server-side, logged ok, billed, and retried anyway",
}
json.dump(key, open(f"{args.key_dir}/answer_key.json", "w"), indent=2)

# ------------------------------------------------------------------ validation printout (no key values)
al["mon"] = pd.to_datetime(al.ts.values).strftime("%Y-%m")
ok_ = al.status.values == 0
print(f"\nrows: {M:,}   total cost: ${cost.sum():,.0f}   time: {time.time() - t_start:.0f}s")
print((al.groupby("mon").agg(rows=("uid", "size"), cost=("cost", "sum")).round(0)).to_string())
print("status mix %:", (pd.Series(st_names[al.status.values]).value_counts(normalize=True) * 100).round(2).to_dict())
print("retry rows %:", round((al.retry_of.values > 0).mean() * 100, 2), "  untagged feature %:", round(isnull.mean() * 100, 2))
print("internal share of cost %:", round(cost[~cf_r].sum() / cost.sum() * 100, 1))
cs = pd.Series(cost).groupby(F.name.values[al.feat.values]).sum().sort_values(ascending=False)
print("cost share by feature %:", (cs / cs.sum() * 100).round(1).to_dict())
print("cache hit (eligible tokens) %:", round(al.cached.values[elig].sum() / al.prompt.values[elig].sum() * 100, 1))
