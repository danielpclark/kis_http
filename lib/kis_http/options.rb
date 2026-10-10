# frozen_string_literal: true

require 'uri'

# TLD
module KisHttp
  # A url options builder class for outgoing requests.
  #
  # Keys are stored as `String`s and are unique; building the same key again
  # replaces the previous value and moves the pair to the end of the query.
  # Scalar values are stored as `String`s, `nil` is kept as `nil` (rendered as
  # a bare key, e.g. `?flag`), and `Array` values are kept as arrays of
  # `String`s (rendered as repeated keys, e.g. `?id=1&id=2`).
  #
  # Rendering (`#opts`, `#to_s`, `#query`, `#fetch`) is always URL encoded via
  # `URI.encode_www_form`, so keys and values may safely contain characters
  # such as spaces, `&`, `=`, `?`, `#` and non-ASCII text.
  class Options
    # Accepts the same inputs as {#build}.
    #
    # @raise [TypeError] when given something that cannot be converted
    def initialize(args = {})
      @opts = {}
      build(args)
    end

    # Copies the backing store so a `dup`/`clone` does not share state.
    def initialize_copy(other)
      super
      @opts = other.to_h
    end

    # url safe rendering of options for the url
    #
    # @return [String] url options, prefixed with `?`, or `''` when empty
    def opts
      rendered = query
      return '' if rendered.empty?

      "?#{rendered}"
    end

    # (see #opts)
    def to_s
      opts
    end

    # url safe rendering of options without the leading `?`
    #
    # @return [String] url encoded query string, or `''` when empty
    def query
      URI.encode_www_form(pairs)
    end

    # Add or update url options
    #
    # @param args [Hash, Array<Array>, String, Options, nil] key/value pairs to
    #   add. A `String` is parsed as a query string (an optional leading `?` is
    #   ignored, repeated keys collect into an `Array`). `nil` is a no-op.
    # @raise [TypeError] when `args` cannot be converted to pairs
    # @raise [ArgumentError] when a key is empty
    # @return [Options] self
    def build(args = {})
      @opts ||= {}

      pairs_from(args).each do |key, value|
        key = normalize_key(key)
        @opts.delete(key)
        @opts[key] = normalize_value(value)
      end

      self
    end

    # Fetch the `key=value` as it would be rendered in the url.
    #
    # Mirrors `Hash#fetch`: when the key is missing the block (if given) is
    # called with the key and its result returned, otherwise `KeyError` is
    # raised.
    #
    # @param key [Symbol, String] key of the key/value pair to fetch
    # @yield [key] when the key is missing
    # @raise [KeyError] when the key is missing and no block is given
    # @return [String] url encoded `key=value` (an `Array` value renders as
    #   `key=1&key=2`, an empty `Array` as `''`, a `nil` value as `key`)
    def fetch(key)
      name = key.to_s
      return URI.encode_www_form(pairs(name => @opts[name])) if @opts.key?(name)
      return yield(name) if block_given?

      raise KeyError.new("key not found: #{name.inspect}", receiver: self, key: name)
    end

    # Fetch and remove `key=value`.  Modifies `Options`.
    #
    # @param key [Symbol, String] key of the key/value pair to fetch
    # @return [String]
    # @see #fetch
    def fetch!(key, &block)
      result = fetch(key, &block)
      remove(key)
      result
    end

    # Fetch the stored value for a key.
    #
    # @param key [Symbol, String]
    # @return [String, Array<String>, nil] the value, or `nil` when missing
    def [](key)
      @opts[key.to_s]
    end

    # @param key [Symbol, String]
    # @return [Boolean] whether the key is present
    def key?(key)
      @opts.key?(key.to_s)
    end
    alias include? key?
    alias has_key? key?

    # Execute a block of code and restore original `Options` state afterwards.
    # The state is restored even when the block raises.
    #
    # @yield [Options] self
    # @return the result of the block
    def immutable
      saved = @opts.dup
      yield self
    ensure
      @opts = saved
    end

    # Remove key/value from options via key
    #
    # @param key [Symbol, String] key to look up
    # @return [String, Array<String>, nil] the stored value if the key was
    #   found, `nil` otherwise.
    def remove(key)
      @opts.delete(key.to_s)
    end

    # this purges all options
    #
    # @return [Options] self
    def reset!
      @opts = {}

      self
    end

    # Add the values of one `Options` into another.  Modifies and returns self.
    #
    # @param other [Options, Hash, Array<Array>, String] values to add
    #   (see {#build})
    # @raise [TypeError] when `other` cannot be converted
    # @return [Options] self
    def +(other)
      build(other)
    end

    # @yield [key, value] each stored pair
    def each_pair(&block)
      return enum_for(:each_pair) unless block

      @opts.each_pair(&block)
      self
    end

    # @return [Boolean] whether there are no options
    def empty?
      @opts.empty?
    end

    # @return [Integer] the number of keys
    def size
      @opts.size
    end
    alias length size

    # @return [Hash{String => String, Array<String>, nil}] a copy of the
    #   `Options` with string keys
    def to_h
      @opts.dup
    end

    # @return [Boolean] whether both hold the same keys and values
    def ==(other)
      other.is_a?(Options) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      [Options, @opts].hash
    end

    def inspect
      "#<#{self.class} #{opts.inspect}>"
    end

    private # @private

    # Flat `[key, value]` pairs ready for `URI.encode_www_form`; an `Array`
    # value becomes one pair per element (an empty `Array` renders nothing).
    # `URI.encode_www_form` is not given arrays directly because it renders an
    # empty array, or a `nil` inside an array, as a dangling `&`.
    def pairs(opts = @opts)
      opts.flat_map do |key, value|
        value.is_a?(Array) ? value.map { |item| [key, item] } : [[key, value]]
      end
    end

    def pairs_from(args)
      case args
      when nil then []
      when Options then args.to_h
      when String then parse_query(args)
      else
        if args.respond_to?(:to_hash)
          args.to_hash
        elsif args.respond_to?(:to_ary)
          pairs_from_array(args.to_ary)
        else
          raise TypeError,
                "Options expects a Hash, Array of pairs, String or Options, #{args.class} given"
        end
      end
    end

    def pairs_from_array(array)
      array.each_with_index.map do |pair, index|
        unless pair.respond_to?(:to_ary) && pair.to_ary.size == 2
          raise TypeError, "expected a [key, value] pair at index #{index}, #{pair.inspect} given"
        end

        pair.to_ary
      end
    end

    # Parses a query string; repeated keys are collected into an `Array`.
    def parse_query(string)
      string = string.sub(/\A\?/, '')

      URI.decode_www_form(string).each_with_object({}) do |(key, value), result|
        if result.key?(key)
          result[key] = Array(result[key]) << value
        else
          result[key] = value
        end
      end
    end

    def normalize_key(key)
      name = key.to_s
      raise ArgumentError, 'option keys must not be empty' if name.empty?

      -name
    end

    def normalize_value(value)
      case value
      when nil then nil
      when Array then value.flatten.map { |item| item.nil? ? nil : -item.to_s }.freeze
      else -value.to_s
      end
    end
  end

  # Convert an object into an `Options`.
  #
  # @param obj [Options, Hash, Array<Array>, String, nil]
  # @raise [TypeError] when `obj` cannot be converted
  # @return [Options] `obj` itself when already an `Options`, otherwise a new
  #   `Options` (an empty one for `nil`)
  def self.Options(obj)
    return obj if obj.is_a? KisHttp::Options

    KisHttp::Options.new(obj)
  end
end
