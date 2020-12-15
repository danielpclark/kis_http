# frozen_string_literal: true

require_relative 'lib/kis_http/version'

Gem::Specification.new do |spec|
  spec.name          = 'kis_http'
  spec.version       = KisHttp::VERSION
  spec.authors       = ['Daniel P. Clark']
  spec.email         = ['6ftdan@gmail.com']

  spec.license       = 'MIT'

  spec.summary       = 'Keep it Simple for Net::HTTP'
  spec.description   = 'DRY for Net::HTTP'
  spec.homepage      = 'https://github.com/danielpclark/kist_http'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  spec.files = Dir['lib/**/*']

  spec.require_paths = ['lib']
end
