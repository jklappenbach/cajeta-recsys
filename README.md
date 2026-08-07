# cajeta-recsys

`dev.cajeta.recsys` — user-item recommendation for the cajeta ecosystem:
collaborative filtering, content-based filtering, and matrix estimation.

**The defining invariant (spec §12.1): missing ≠ zero, by construction.**
A rating of 0 and no rating never compare equal — `Interactions` keeps
presence and value as separate concepts, reading a missing cell throws,
and densification demands an explicit fill because "defaults to zero" is
*the* defining bug of this domain.

- **Interactions** — the sparse user-item matrix (CSR+CSC mirrors,
  external-id round-tripping, density reporting, documented −1
  cold-start answer).
- **Baselines** — global/item/user mean and the regularized bias model;
  the bar every real model must clear, evaluated on the same split.
- **Neighbourhood CF** — user- and item-based k-NN over co-rated
  entries only, similarity from `cajeta.math.distance`.
- **Factorization** — the two "SVD"s, *named distinctly*: zero-filled
  truncated SVD (the textbook estimator, with its assumption stated) vs
  SGD factorization over observed entries only (Surprise's `SVD`);
  plus singular value thresholding for matrix completion.
- **Co-clustering** — Surprise's `CoClustering`, with the documented
  empty-cluster fallback chain.
- **Content-based** — item/user profiles over `dev.cajeta.docs` TF-IDF
  vectors *(blocked until cajeta-docs ships its text pipeline)*.
- **mSSA** — matrix estimation over time series: the trajectory
  transform comes from `dev.cajeta.timeseries`, completion from the §5
  estimators; no stationarity assumed.
- **Evaluation** — rating metrics through `dev.cajeta.ml.Metrics`;
  precision/recall/F1@k with an explicit relevance threshold, NDCG@k,
  coverage; already-interacted items excluded by default.

## The oracles, and their pins

Four, not one (spec §1.3):

- **Surprise 1.1.5** — the collaborative-filtering algorithms. A
  divergence from Surprise is a **finding to investigate, not
  automatically a cajeta bug** — it is a small, lightly-maintained
  project, the opposite of the sklearn discipline.
- **scikit-learn 1.9.0** — TF-IDF and cosine.
- **mSSA** (Shah group) — a research-grade reference, not a standard.

`tools/fixtures/gen_recsys.py` asserts the pins before generating.
Departures live in [docs/DifferencesFromOracles.md](docs/DifferencesFromOracles.md).

## Build, test, tour

```
./run-tests.sh    # unit suite (cajeta-unit reflective @Test discovery)
./run-tour.sh     # self-checking tour
cajeta build      # emit build/archive/dev.cajeta.recsys-<version>.cja
```

Depends on `dev.cajeta.ml` 0.9.0 (`Metrics`, `KMeans`, the protocol
where it genuinely fits) and `dev.cajeta.timeseries` 0.1.0 (the
trajectory transform).
