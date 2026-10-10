# frozen_string_literal: true

# TLD
module KisHttp
  # A header builder class for outgoing requests
  #
  # Header names are case-insensitive, so they are stored in a canonical
  # `Capitalized-Words` form: `'content-type'`, `'CONTENT-TYPE'` and
  # `:content_type` all refer to the same `'Content-Type'` header (underscores
  # in `Symbol` names are translated to dashes). Names are validated against
  # the HTTP token grammar.
  #
  # Values are stored as `String`s; an `Array` value is joined with `', '`.
  # Values containing CR or LF are rejected to prevent header injection.
  # Building a key with a `nil` value removes that header.
  class Headers
    # RFC 7230 `token` characters allowed in a header field name.
    NAME = %r{\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z}.freeze

    # Accepts the same inputs as {#build}.
    #
    # @raise [TypeError] when given something that cannot be converted
    def initialize(args = {})
      @heads = {}
      build(args)
    end

    # Copies the backing store so a `dup`/`clone` does not share state.
    def initialize_copy(other)
      super
      @heads = other.to_h
    end

    # Add or update the request headers
    #
    # @param args [Hash, Array<Array>, Headers, nil] name/value pairs to add.
    #   A `nil` value removes the header. `nil` args is a no-op.
    # @raise [TypeError] when `args` cannot be converted to pairs
    # @raise [ArgumentError] when a name is not a valid header name, or a
    #   value contains CR or LF
    # @return [Headers] self
    def build(args = {})
      @heads ||= {}

      pairs_from(args).each do |key, value|
        name = canonical(key)

        if value.nil?
          @heads.delete(name)
        else
          @heads[name] = normalize_value(name, value)
        end
      end

      self
    end

    # Assign each header to object via :[]=
    #
    # @param obj [#[]=] typically a `Net::HTTPRequest`
    # @return obj
    def assign_each_to(obj)
      each_pair do |header, value|
        obj[header] = value
      end

      obj
    end

    # Fetch a header value.
    #
    # Mirrors `Hash#fetch`: when the header is missing the block (if given) is
    # called with the canonical name and its result returned, otherwise
    # `KeyError` is raised.
    #
    # @param key [Symbol, String] header name (any case)
    # @yield [name] when the header is missing
    # @raise [KeyError] when the header is missing and no block is given
    # @return [String] the header value
    def fetch(key)
      name = canonical(key, validate: false)
      return @heads[name] if @heads.key?(name)
      return yield(name) if block_given?

      raise KeyError.new("header not found: #{name.inspect}", receiver: self, key: name)
    end

    # @param key [Symbol, String] header name (any case)
    # @return [String, nil] the header value, or `nil` when missing
    def [](key)
      @heads[canonical(key, validate: false)]
    end

    # @param key [Symbol, String] header name (any case)
    # @return [Boolean] whether the header is present
    def key?(key)
      @heads.key?(canonical(key, validate: false))
    end
    alias include? key?
    alias has_key? key?

    # Remove key/value from headers via key
    #
    # @param key [Symbol, String] header name (any case)
    # @return [String, nil] returns value if key found, `nil` otherwise.
    def remove(key)
      @heads.delete(canonical(key, validate: false))
    end

    # Add the values of one `Headers` into another.  Modifies and returns self.
    #
    # @param other [Headers, Hash, Array<Array>] headers to add (see {#build})
    # @raise [TypeError] when `other` cannot be converted
    # @return [Headers] self
    def +(other)
      build(other)
    end

    # @yield [name, value] each stored header
    def each_pair(&block)
      return enum_for(:each_pair) unless block

      @heads.each_pair(&block)
      self
    end

    # @return [Boolean] whether there are no headers
    def empty?
      @heads.empty?
    end

    # @return [Integer] the number of headers
    def size
      @heads.size
    end
    alias length size

    # @return [Hash{String => String}] a copy of the `Headers` with canonical
    #   string names
    def to_h
      @heads.dup
    end

    # @return [Boolean] whether both hold the same headers
    def ==(other)
      other.is_a?(Headers) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      [Headers, @heads].hash
    end

    def inspect
      "#<#{self.class} #{@heads.inspect}>"
    end

    private # @private

    def pairs_from(args)
      case args
      when nil then []
      when Headers then args.to_h
      else
        if args.respond_to?(:to_hash)
          args.to_hash
        elsif args.respond_to?(:to_ary)
          pairs_from_array(args.to_ary)
        else
          raise TypeError,
                "Headers expects a Hash, Array of pairs or Headers, #{args.class} given"
        end
      end
    end

    def pairs_from_array(array)
      array.each_with_index.map do |pair, index|
        unless pair.respond_to?(:to_ary) && pair.to_ary.size == 2
          raise TypeError, "expected a [name, value] pair at index #{index}, #{pair.inspect} given"
        end

        pair.to_ary
      end
    end

    # Canonical `Capitalized-Words` form of a header name.
    def canonical(key, validate: true)
      name = key.is_a?(Symbol) ? key.to_s.tr('_', '-') : key.to_s

      if validate
        raise ArgumentError, 'header names must not be empty' if name.empty?
        raise ArgumentError, "invalid header name: #{name.inspect}" unless NAME.match?(name)
      end

      -name.split('-', -1).map(&:capitalize).join('-')
    end

    def normalize_value(name, value)
      string = value.is_a?(Array) ? value.flatten.map(&:to_s).join(', ') : value.to_s

      if string.match?(/[\r\n]/)
        raise ArgumentError, "header #{name} value must not contain CR or LF"
      end

      -string
    end
  end

  # Convert an object into a `Headers`.
  #
  # @param obj [Headers, Hash, Array<Array>, nil]
  # @raise [TypeError] when `obj` cannot be converted
  # @return [Headers] `obj` itself when already a `Headers`, otherwise a new
  #   `Headers` (an empty one for `nil`)
  def self.Headers(obj)
    return obj if obj.is_a? KisHttp::Headers

    KisHttp::Headers.new(obj)
  end
end
