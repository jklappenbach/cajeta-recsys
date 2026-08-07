#!/usr/bin/env python3
"""Golden-fixture generator for dev.cajeta.recsys.

FOUR ORACLES, pinned and asserted below (spec §1.3): Surprise 1.1.5 for
the collaborative-filtering algorithms — where Surprise's behaviour is
idiosyncratic the DOCUMENTED algorithm wins and the divergence is
recorded in docs/DifferencesFromOracles.md — and scikit-learn 1.9.0 for
TF-IDF/cosine. mSSA is a research-grade reference, validated
self-consistently rather than fixture-pinned.

Run:  /home/julian/code/ml/venv-sklearn-ref/bin/python gen_recsys.py
Emits C-order .npy files (np.ascontiguousarray everywhere — the Npy
reader misreads fortran_order, INDEX defect npy-fortran-order-silent-misread).
"""

import numpy as np
import sklearn
import surprise

assert surprise.__version__ == "1.1.5", surprise.__version__
assert sklearn.__version__ == "1.9.0", sklearn.__version__
assert np.__version__ == "2.5.1", np.__version__

OUT = __file__.rsplit("/", 1)[0]


def save(name, arr):
    a = np.ascontiguousarray(np.asarray(arr, dtype=np.float64))
    np.save(f"{OUT}/{name}.npy", a)
    print(f"  {name}.npy {a.shape}")


def ratings_fixture():
    """The shared ratings set: 30 users, 20 items, ~200 ratings, seeded.

    Ratings are 1..5 with a planted structure (user bias + item bias +
    noise) so baselines and factorizations have signal to find.
    """
    rng = np.random.default_rng(101)
    n_u, n_i = 30, 20
    bu = rng.normal(0.0, 0.5, n_u)
    bi = rng.normal(0.0, 0.7, n_i)
    mu = 3.4
    triples = []
    seen = set()
    target = 200
    while len(triples) < target:
        u = int(rng.integers(0, n_u))
        i = int(rng.integers(0, n_i))
        if (u, i) in seen:
            continue
        seen.add((u, i))
        r = mu + bu[u] + bi[i] + rng.normal(0.0, 0.4)
        r = float(np.clip(np.round(r * 2) / 2, 1.0, 5.0))
        triples.append((u, i, r))
    triples.sort()
    us = np.array([t[0] for t in triples], dtype=np.float64)
    its = np.array([t[1] for t in triples], dtype=np.float64)
    rs = np.array([t[2] for t in triples], dtype=np.float64)
    return us, its, rs, n_u, n_i


def surprise_trainset(us, its, rs):
    from surprise import Dataset, Reader
    import pandas as pd
    df = pd.DataFrame({
        "user": [str(int(u)) for u in us],
        "item": [str(int(i)) for i in its],
        "rating": rs,
    })
    data = Dataset.load_from_df(df[["user", "item", "rating"]],
                                Reader(rating_scale=(1, 5)))
    return data.build_full_trainset()


def gen_baselines():
    """U2 — BaselineOnly (ALS, Surprise defaults: 10 epochs, reg_i=10,
    reg_u=15). bu/bi are saved in OUR index order via the raw-id map."""
    from surprise import BaselineOnly

    us, its, rs, n_u, n_i = ratings_fixture()
    save("rs_ratings_u", us)
    save("rs_ratings_i", its)
    save("rs_ratings_r", rs)

    ts = surprise_trainset(us, its, rs)
    algo = BaselineOnly(bsl_options={"method": "als", "n_epochs": 10,
                                     "reg_i": 10, "reg_u": 15},
                        verbose=False)
    algo.fit(ts)
    bu = np.zeros(n_u)
    bi = np.zeros(n_i)
    for u in range(n_u):
        bu[u] = algo.bu[ts.to_inner_uid(str(u))]
    for i in range(n_i):
        bi[i] = algo.bi[ts.to_inner_iid(str(i))]
    save("rs_baseline_mu", [ts.global_mean])
    save("rs_baseline_bu", bu)
    save("rs_baseline_bi", bi)


def gen_knn():
    """U3 — neighbourhood CF vs Surprise KNNBasic/KNNWithMeans.

    An interaction split (§2.5): 20 held-out ratings whose user AND item
    both still appear in training, so no accidental cold start. Three
    pinned configs on the train set, est saved over the test pairs. The
    3.1.6 asymmetry claim (item-based beats user-based when users
    outnumber items) is VERIFIED here before the fixture is trusted.
    """
    from surprise import KNNBasic, KNNWithMeans

    us, its, rs, n_u, n_i = ratings_fixture()
    rng = np.random.default_rng(202)
    order = rng.permutation(len(rs))
    test_idx = []
    for t in order:
        if len(test_idx) == 20:
            break
        rest = [x for x in range(len(rs)) if x not in test_idx and x != t]
        if any(us[x] == us[t] for x in rest) and \
           any(its[x] == its[t] for x in rest):
            test_idx.append(int(t))
    train_idx = [x for x in range(len(rs)) if x not in test_idx]
    tu, ti, tr = us[train_idx], its[train_idx], rs[train_idx]
    vu, vi, vr = us[test_idx], its[test_idx], rs[test_idx]
    save("rs_knn_train_u", tu)
    save("rs_knn_train_i", ti)
    save("rs_knn_train_r", tr)
    save("rs_knn_test_u", vu)
    save("rs_knn_test_i", vi)
    save("rs_knn_test_r", vr)

    ts = surprise_trainset(tu, ti, tr)

    def ests(algo):
        algo.fit(ts)
        return np.array([algo.predict(str(int(u)), str(int(i))).est
                         for u, i in zip(vu, vi)])

    e_uc = ests(KNNBasic(k=40, sim_options={"name": "cosine",
                                            "user_based": True,
                                            "min_support": 1},
                         verbose=False))
    save("rs_knn_user_cosine_est", e_uc)
    e_im = ests(KNNBasic(k=40, sim_options={"name": "msd",
                                            "user_based": False,
                                            "min_support": 1},
                         verbose=False))
    save("rs_knn_item_msd_est", e_im)
    e_um = ests(KNNBasic(k=40, sim_options={"name": "msd",
                                            "user_based": True,
                                            "min_support": 1},
                         verbose=False))
    save("rs_knn_user_msd_est", e_um)
    e_pm = ests(KNNWithMeans(k=40, sim_options={"name": "pearson",
                                                "user_based": True,
                                                "min_support": 1},
                             verbose=False))
    save("rs_knn_user_pearson_means_est", e_pm)

    # 3.1.6 needs its own fixture: two item genres × two user camps, each
    # user rating only 4 of 12 items — user-user co-rating support is
    # thin (camp detection noisy) while item-item support is dense
    # (same-genre items correlate across ALL users). Verified before the
    # fixture is trusted.
    # The regime that produces it (found empirically): 300 users x 60
    # items x 4 ratings each. User-pair co-rating overlap ~0.27 items
    # (user-user similarity mostly nonexistent or one-sample noise);
    # item-pair support ~6.7 co-raters (item-item similarity reliable).
    rng2 = np.random.default_rng(303)
    n_u2, n_i2 = 300, 60
    au, ai, ar = [], [], []
    for u in range(n_u2):
        camp = u % 2
        items = rng2.choice(n_i2, 4, replace=False)
        for i in items:
            genre = 0 if i < n_i2 // 2 else 1
            base = 4.0 if genre == camp else 2.0
            r = float(np.clip(np.round((base
                + rng2.normal(0, 0.4)) * 2) / 2, 1.0, 5.0))
            au.append(u); ai.append(int(i)); ar.append(r)
    au = np.array(au, dtype=np.float64)
    ai = np.array(ai, dtype=np.float64)
    ar = np.array(ar, dtype=np.float64)
    order2 = rng2.permutation(len(ar))
    a_test = []
    for t in order2:
        if len(a_test) == 30:
            break
        rest = [x for x in range(len(ar)) if x not in a_test and x != t]
        if any(au[x] == au[t] for x in rest) and \
           any(ai[x] == ai[t] for x in rest):
            a_test.append(int(t))
    a_train = [x for x in range(len(ar)) if x not in a_test]
    save("rs_asym_train_u", au[a_train])
    save("rs_asym_train_i", ai[a_train])
    save("rs_asym_train_r", ar[a_train])
    save("rs_asym_test_u", au[a_test])
    save("rs_asym_test_i", ai[a_test])
    save("rs_asym_test_r", ar[a_test])
    ts2 = surprise_trainset(au[a_train], ai[a_train], ar[a_train])

    def ests2(algo):
        algo.fit(ts2)
        return np.array([algo.predict(str(int(u)), str(int(i))).est
                         for u, i in zip(au[a_test], ai[a_test])])

    e2_i = ests2(KNNBasic(k=40, sim_options={"name": "msd",
                                             "user_based": False,
                                             "min_support": 1},
                          verbose=False))
    e2_u = ests2(KNNBasic(k=40, sim_options={"name": "msd",
                                             "user_based": True,
                                             "min_support": 1},
                          verbose=False))
    save("rs_asym_item_est", e2_i)
    save("rs_asym_user_est", e2_u)
    rmse_u = float(np.sqrt(np.mean((e2_u - ar[a_test]) ** 2)))
    rmse_i = float(np.sqrt(np.mean((e2_i - ar[a_test]) ** 2)))
    print(f"  [check] asym: user rmse {rmse_u:.4f} vs item {rmse_i:.4f}")
    assert rmse_i < rmse_u, "3.1.6 asymmetry does not hold on this fixture"


def gen_mf():
    """U4 — the two SVDs (spec §5's note).

    Zero-filled truncated SVD: sklearn TruncatedSVD (arpack, exact for
    this size) on the zero-filled 30×20 matrix — the RECONSTRUCTION is
    saved (sign-invariant, unlike the factors). Surprise SVD: bit
    parity is impossible across RNGs (its factor init draws from
    numpy's MT19937), so the pin is the held-out RMSE at fixed
    hyperparameters — recorded as the §11.3 judgement call in
    DifferencesFromOracles.md.
    """
    from sklearn.decomposition import TruncatedSVD
    from surprise import SVD

    us, its, rs, n_u, n_i = ratings_fixture()
    dense = np.zeros((n_u, n_i))
    for u, i, r in zip(us.astype(int), its.astype(int), rs):
        dense[u, i] = r
    tsvd = TruncatedSVD(n_components=5, algorithm="arpack")
    z = tsvd.fit_transform(dense)
    recon = z @ tsvd.components_
    save("rs_tsvd_recon", recon)
    save("rs_tsvd_singular", tsvd.singular_values_)

    tu = np.load(f"{OUT}/rs_knn_train_u.npy")
    ti = np.load(f"{OUT}/rs_knn_train_i.npy")
    tr = np.load(f"{OUT}/rs_knn_train_r.npy")
    vu = np.load(f"{OUT}/rs_knn_test_u.npy")
    vi = np.load(f"{OUT}/rs_knn_test_i.npy")
    vr = np.load(f"{OUT}/rs_knn_test_r.npy")
    ts = surprise_trainset(tu, ti, tr)
    algo = SVD(n_factors=20, n_epochs=20, random_state=7)
    algo.fit(ts)
    est = np.array([algo.predict(str(int(u)), str(int(i))).est
                    for u, i in zip(vu, vi)])
    rmse = float(np.sqrt(np.mean((est - vr) ** 2)))
    print(f"  [check] surprise SVD held-out rmse {rmse:.4f}")
    save("rs_svd_rmse", [rmse])


def gen_cocluster():
    """U5 — Surprise CoClustering(3,3), 20 epochs: RMSE-level pin on the
    shared split (init randomness is numpy's, so bitwise parity is
    impossible — the 11.3 judgement again)."""
    from surprise import CoClustering

    tu = np.load(f"{OUT}/rs_knn_train_u.npy")
    ti = np.load(f"{OUT}/rs_knn_train_i.npy")
    tr = np.load(f"{OUT}/rs_knn_train_r.npy")
    vu = np.load(f"{OUT}/rs_knn_test_u.npy")
    vi = np.load(f"{OUT}/rs_knn_test_i.npy")
    vr = np.load(f"{OUT}/rs_knn_test_r.npy")
    ts = surprise_trainset(tu, ti, tr)
    algo = CoClustering(n_cltr_u=3, n_cltr_i=3, n_epochs=20,
                        random_state=7, verbose=False)
    algo.fit(ts)
    est = np.array([algo.predict(str(int(u)), str(int(i))).est
                    for u, i in zip(vu, vi)])
    rmse = float(np.sqrt(np.mean((est - vr) ** 2)))
    print(f"  [check] surprise CoClustering held-out rmse {rmse:.4f}")
    save("rs_cc_rmse", [rmse])


def main():
    print(f"surprise {surprise.__version__} / sklearn {sklearn.__version__} "
          f"fixtures -> {OUT}")
    gen_baselines()
    gen_knn()
    gen_mf()
    gen_cocluster()


if __name__ == "__main__":
    main()
