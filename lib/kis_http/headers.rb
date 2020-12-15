# frozen_string_literal: true

require 'forwardable'

# TLD
module KisHttp
  # A header builder class for outgoing requests
  class Headers
    extend Forwardable
    # @!macro [attach] def_delegators
    #   @!method each_pair
    #     Forwards to $1.
    #     @see Hash#each_pair
    #   @!method fetch
    #     Forwards to $1.
    #     @see Hash#fetch
    def_delegators :@heads, :each_pair, :fetch

    def initialize(args = {})
      build(args)
    end

    # Add or update the request headers
    #
    # @return [Headers] self
    def build(args = {})
      @heads ||= {}

      args.to_h.each do |(key, value)|
        @heads[key] = value
      end

      self
    end

    # Assign each header to object via :[]
    def assign_each_to(obj)
      each_pair do |header, value|
        obj[header] = value
      end

      obj
    end

    # Remove key/value from headers via key
    #
    # @param key [Symbol, String] key to look up
    # @return [String, Symbol, nil] returns value if key found, `nil` otherwise.
    def remove(key)
      @heads.delete(key)
    end

    # Add the values of one `Headers` into another
    #
    # @param other [Headers] instance of `Headers`
    # @return [Headers]
    def +(other)
      raise TypeError, "Headers type expected, #{other.class} given" \
        unless other.is_a? Headers

      @heads.merge(other.instance_variable_get(:@heads))

      self
    end

    # @return [Hash] hash of the `Headers`
    def to_h
      @heads
    end
  end

  def self.Headers(obj)
    if obj.is_a? Rest::Headers
      obj
    elsif obj.is_a? Hash
      Rest::Headers.new(**obj)
    elsif obj.is_a? Array
      Rest::Headers.new(**obj.to_h)
    else
      raise 'Invalid object type for Headers!'
    end
  end
end
