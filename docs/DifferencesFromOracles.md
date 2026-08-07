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
