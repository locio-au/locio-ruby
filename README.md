# locio

**Australian address validation, autocomplete and geocoding for Ruby and
Rails**, from G-NAF, the national address register. Turn whatever somebody
typed into one address with a stable id, a coordinate, an ABS mesh block and
the components a form has boxes for.

- Ruby 3.2 and up, standard library only
- A validator for Rails models that loads without Rails
- Tells a spent quota apart from a rate limit, so you know whether to wait or
  to upgrade

```sh
bundle add locio
```

Get a key at [locio.com.au](https://locio.com.au/account/api).

## Quick start

```ruby
require "locio"

locio = Locio::Client.new(ENV.fetch("LOCIO_KEY"), country: "AU")

res = locio.resolve("1 george st sydney nsw 2000")
if res.matched
  a = res.address
  puts a.id, a.formatted, a.lat, a.lng, a.mesh_block
end
```

Write the address however you hold it. Abbreviations, missing commas and a
missing state are all fine.

## The calls

| Call | Answers | Units |
|---|---|---|
| `search(term, limit: 8)` | candidates for what somebody is typing: autocomplete | 1 |
| `resolve(address)` | one address, or `matched` false: validation and geocoding | 1 |
| `similar(address, limit: 3)` | near misses for an address that did not resolve | 3 |
| `get(id)` | the address you stored, read back; `nil` once it has retired | 1 |

`search_scoped` and `similar_scoped` return the same addresses with the
country the service searched and, when a country is not covered, a `note`
saying so.

`matched` false is an answer, not an error: the address as written is not in
the register. Try `similar` once when a typo is likely.

## Rails

Put the key in your credentials or environment as `LOCIO_KEY`, then validate
the address on the model:

```ruby
class Order < ApplicationRecord
  validates_with Locio::AddressValidator, attribute: :shipping_address, store: :address_id
end
```

`store:` writes the G-NAF id to that attribute when the address matches: store
the id, not the text. One unit per record checked.

When the service cannot answer, because of a timeout, a rate limit or a spent
quota, the record **passes**: an outage of ours should not stop somebody
checking out. Pass `strict: true` to fail instead, and `client:` to use a
client of your own rather than one built from `LOCIO_KEY` and `LOCIO_COUNTRY`.

## Which id to store

Store `address.id` beside `address.country_code`. In Australia `id` is the
G-NAF Address Detail PID, stable across quarterly releases for an address that
has not changed. `unit?` says when `gnaf["primary_pid"]` names the parcel a
unit sits on, which is the building rather than the door.

G-NAF retires ids between releases, so `get` answers `nil` for one that has
gone rather than raising.

## Quota and rate limits

```ruby
begin
  locio.search(term)
rescue Locio::RateLimited => e
  # Too many a second. Wait e.retry_after seconds.
rescue Locio::QuotaExhausted => e
  # Every unit in the period is spent until e.reset.
end
```

`locio.quota` holds what the most recent answer said: `limit`, `remaining` and
`reset`. A job working through a table can read it to slow down before the
quota runs out.

Every error is a `Locio::Error` carrying the service's own `title` and
`detail`. The others are `Unauthorized` (401, 403), `NotFound`, `BadRequest`
and `TransportError` (no answer arrived).

## Your own HTTP stack

Anything with `call(url, headers)` returning a `Locio::Response` can carry the
requests: Faraday, HTTPX, or a test double.

```ruby
locio = Locio::Client.new(key, transport: MyFaradayTransport.new)
```

A transport must not follow redirects, since a redirect would carry the
`Authorization` header to wherever it points.

## Keys

This gem takes a **secret key** (`lc_live_...`), which belongs on a server.
Never render it into a page: anyone who can read the page can spend your quota.
For a browser autocomplete use a public key (`lc_pub_...`) with
[`@locio-au/react`](https://www.npmjs.com/package/@locio-au/react) or
[`@locio-au/vue`](https://www.npmjs.com/package/@locio-au/vue).

The client sends the key only over https (or plain http to localhost, for a
test server), and keeps it out of `inspect`, instance variable dumps and error
messages.

## The other packages

| | |
|---|---|
| [`@locio-au/client`](https://www.npmjs.com/package/@locio-au/client) | JavaScript and TypeScript |
| [`@locio-au/react`](https://www.npmjs.com/package/@locio-au/react) | React address autocomplete |
| [`@locio-au/vue`](https://www.npmjs.com/package/@locio-au/vue) | Vue address autocomplete |
| [`locio`](https://pypi.org/project/locio/) | Python |
| [`locio-go`](https://github.com/locio-au/locio-go) | Go |
| [`locio/locio`](https://packagist.org/packages/locio/locio) | PHP and Laravel |

API reference: [locio.com.au/docs](https://locio.com.au/docs/).

## Licence

MIT. Address data is G-NAF, published by Geoscape Australia under CC BY 4.0;
attribution belongs wherever you show it. See
[locio.com.au/legal](https://locio.com.au/legal/).
