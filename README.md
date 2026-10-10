[![Gem Version](https://badge.fury.io/rb/kis_http.svg)](http://badge.fury.io/rb/kis_http)
[![CI](https://github.com/danielpclark/kis_http/actions/workflows/ci.yml/badge.svg)](https://github.com/danielpclark/kis_http/actions/workflows/ci.yml)

# KisHttp

Keep it Simple HTTP

A thin, dependency-free wrapper around `Net::HTTP` for JSON APIs.

**NOTE**: Current implementation is JSON only.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kis_http'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install kis_http

## Usage

```ruby
require 'kis_http'

response = KisHttp.get('https://api.example.com/users', options: { page: 2, q: 'ann marie' })
# => GET /users?page=2&q=ann+marie

response = KisHttp.post(
  'https://api.example.com/users',
  body: { name: 'Ann' },                    # serialized as JSON
  headers: { authorization: 'Bearer tok' }  # Content-Type: application/json is added
)

response.code  # => "201"
response.body  # => '{"id":1,...}'
```

`get`, `head`, `post`, `put`, `patch` and `delete` are available. Each takes a
url (a `String` or `URI`) and returns the `Net::HTTPResponse`. Keyword
arguments:

* `body:` a `String` is sent as-is; a `Hash` or `Array` is serialized with
  `JSON.generate` and a `Content-Type: application/json` header is added unless
  you supplied one. Anything else raises `TypeError`.
* `headers:` a `Hash`, `Array` of pairs or `KisHttp::Headers`.
* `options:` a `Hash`, `Array` of pairs, query `String` or `KisHttp::Options`.
  These are URL encoded and appended to the url, merging with any query string
  the url already has (`'/users?a=1'` plus `{ b: 2 }` requests `/users?a=1&b=2`).

Only `http` and `https` urls are accepted; anything else, or a url without a
host, raises `ArgumentError` before a connection is attempted. Userinfo in the
url (`https://user:pass@host/`) is sent as HTTP Basic authentication.
IPv6 literals (`http://[::1]:8080/`) work.

### Options

`KisHttp::Options` builds a query string. Keys are unique; building a key again
replaces its value.

```ruby
opts = KisHttp::Options.new(q: 'a b&c', ids: [1, 2], flag: nil)
opts.opts           # => "?q=a+b%26c&ids=1&ids=2&flag"
opts.fetch(:ids)    # => "ids=1&ids=2"
opts[:q]            # => "a b&c"
opts.remove(:q)     # => "a b&c"
opts + 'page=2'     # parses a query string into the options
opts.immutable { |o| o.build(page: 3).opts }  # state restored afterwards
opts.to_h           # => { "ids" => ["1", "2"], "flag" => nil, "page" => "2" }
```

Values are stored as `String`s; `nil` renders as a bare key (`?flag`) and an
`Array` as repeated keys (`?ids=1&ids=2`).

### Headers

`KisHttp::Headers` builds request headers. Names are case-insensitive and are
stored in canonical `Capitalized-Words` form; `Symbol` names translate
underscores to dashes.

```ruby
heads = KisHttp::Headers.new(content_type: 'application/json', 'x-api-key' => 123)
heads.to_h            # => { "Content-Type" => "application/json", "X-Api-Key" => "123" }
heads['CONTENT-TYPE'] # => "application/json"
heads + { accept: ['text/html', 'application/json'] }  # => "Accept: text/html, application/json"
heads.build(x_api_key: nil)  # removes the header
```

Names must be valid HTTP tokens and values may not contain CR or LF
(`ArgumentError` otherwise), which prevents header injection.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` (or `rake spec`) to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/danielpclark/kis_http.
