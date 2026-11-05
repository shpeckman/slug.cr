# src/slug/result.cr
module Slug
  # Result codes returned by every fallible function.
  enum Result
    # Success.
    Ok
    # Allocation failed.
    OutOfMemory
    # A parameter was null or out of range.
    InvalidArgument
    # FreeType reported an error.
    FreeType
    # Glyph format or GPU feature not supported.
    Unsupported
    # Glyph missing from a frozen atlas.
    Frozen
    # A texture coordinate or band limit was exceeded.
    Limit
    # Output buffer too small; the required count was reported.
    Capacity
    # GPU backend failure; see the backend's error string.
    Backend

    # Returns a static description of the result.
    def description : String
      case self
      in .ok?                then "ok"
      in .out_of_memory?     then "out of memory"
      in .invalid_argument?  then "invalid argument"
      in .free_type?         then "FreeType error"
      in .unsupported?       then "unsupported"
      in .frozen?            then "glyph missing from frozen atlas"
      in .limit?             then "atlas limit exceeded"
      in .capacity?          then "output capacity too small"
      in .backend?           then "backend error"
      end
    end
  end
end
