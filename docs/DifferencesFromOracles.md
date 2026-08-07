# Differences from the oracles

Four oracles (README): Surprise 1.1.5, scikit-learn 1.9.0, mSSA as a
research-grade reference. One bullet per deliberate departure, recorded
as it is made. **The Surprise discipline is inverted from sklearn's**: a
divergence there is a finding to investigate — the documented algorithm
wins over Surprise's incidental behaviour when they disagree, and the
disagreement is recorded here.

## The interaction matrix (spec §2)

- **Duplicate (user, item) triples are rejected loudly.** Surprise's
  `Dataset` keeps whatever lands last; here a duplicate is treated as a
  data bug upstream, because last-write-wins silently changes answers.
- **A NaN rating is rejected at construction.** Missing is an ABSENT
  triple, never a NaN cell — one representation of "missing", not two.

## Neighbourhood CF (spec §4)

- **Degenerate-pair similarity follows Surprise, not the stdlib
  doctrine.** `cajeta.math.distance` defines both-degenerate pairs
  (both zero-norm / both constant) as similarity 1; Surprise's
  similarities give 0 whenever the denominator vanishes. Here "we know
  nothing about this pair" must not read as "perfectly similar", so the
  Surprise policy is applied AROUND the stdlib kernels — the kernels
  themselves are consumed verbatim for every well-posed pair.
- **`msd` is the one similarity implemented locally** — Surprise's
  `1/(msd+1)` is domain-specific and has no stdlib home; cosine and
  Pearson math never appears in this library.
