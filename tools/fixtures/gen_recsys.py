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


def main():
    print(f"surprise {surprise.__version__} / sklearn {sklearn.__version__} "
          f"fixtures -> {OUT}")
    gen_baselines()


if __name__ == "__main__":
    main()
