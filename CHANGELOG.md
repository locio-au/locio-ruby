# Changelog

## 0.1.0

First release.

- `search`, `search_scoped`, `resolve`, `similar`, `similar_scoped` and `get`,
  covering the Locio address API, with `Address` and `Resolution` as frozen
  value objects that keep the raw record.
- Errors that tell a spent quota (`QuotaExhausted`, 402, with `reset`) from a
  rate limit (`RateLimited`, 429, with `retry_after`). `quota` reports the
  allowance from the most recent answer.
- `Locio::AddressValidator` for ActiveModel's `validates_with`, loaded without
  ActiveModel, that lets a record through when Locio cannot answer.
- A one method transport, with `NetHTTPTransport` as the default: it never
  follows redirects, speaks only http and https, verifies TLS and stops reading
  at 8 MiB.
- The key is held in a `Locio::Secret`, which never prints.
- Standard library only.
