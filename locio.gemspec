# frozen_string_literal: true

require_relative "lib/locio/version"

Gem::Specification.new do |spec|
  spec.name = "locio"
  spec.version = Locio::VERSION
  spec.authors = ["Locio"]
  spec.email = ["postmaster@locio.com.au"]
  spec.summary = "Australian address validation, autocomplete and geocoding from G-NAF"
  spec.description = "Turn whatever somebody typed into one Australian address with a stable G-NAF id, " \
                     "coordinates, an ABS mesh block and its components. Address validation for Rails " \
                     "checkouts, with no runtime dependencies."
  spec.homepage = "https://locio.com.au"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/locio-au/locio-ruby",
    "changelog_uri" => "https://github.com/locio-au/locio-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://locio.com.au/docs/",
    "bug_tracker_uri" => "https://github.com/locio-au/locio-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]
end
