module Every
  # Read the tail of a file without loading the whole thing. The files this
  # touches are bounded (logs rotate at 5 MB, run ledgers trim to 256 KB), but
  # `list` reads every task's ledger and `log` only wants the last few lines —
  # seeking from the end keeps both cheap regardless of file size.
  module Tail
    CHUNK = 16 * 1024

    module_function

    # The last `n` lines of the file, in order, each keeping its trailing "\n"
    # (the final line may lack one) — the same shape as `readlines.last(n)`, but
    # it reads only enough bytes from the end to find n complete lines.
    def lines(path, n)
      return [] if n <= 0
      File.open(path, "rb") do |f|
        size = f.size
        window = 0
        buf = "".b
        while window < size
          window = [window + CHUNK, size].min
          f.seek(size - window)
          buf = f.read(window)
          # More than n newlines guarantees the n-th line from the end is whole:
          # its head can't extend past the start of the window we've read.
          break if buf.count("\n") > n
        end
        buf.lines.last(n) || []
      end
    end
  end
end
