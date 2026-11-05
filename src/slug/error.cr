# src/slug/error.cr
require "./result"

module Slug
  # A Slug operation failed.
  class Error < Exception
    # Returns the failing result code.
    getter result : Result

    def initialize(@result : Result, detail : String? = nil)
      super(detail || result.description)
    end
  end

  # Returns *result* when it is `Result::Ok`; raises `Error` otherwise.
  def self.check(result : Result) : Result
    raise Error.new(result) unless result.ok?
    result
  end
end
