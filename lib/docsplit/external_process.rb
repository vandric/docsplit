module Docsplit
  module ExternalProcess
    COMMAND_TIMEOUT = 300 # seconds

    # Run an external process and raise an exception if it fails.
    def run(command, env = "")
      # If a corrupt PDF is parsed, it generates an infinite amount of identical warnings (with blank lines in between).
      # By filtering these we avoid memory bloat when the executing process tries to capture stdout. The timeout makes
      # sure we exit at some point.
      #
      # - See https://github.com/GetSilverfin/silverfin/issues/1998
      # - Add timeout so a stuck process doesn't block our Ruby process forever
      # - Remove blank lines
      # - Remove duplicate lines
      run_command = "#{env} #{timeout} #{command} | grep -v \"^$\" | uniq"

      # - Run through bash so we can use PIPESTATUS
      # - Use PIPESTATUS to return the exit status of #{command} instead of `uniq`
      result = `bash -c '#{run_command}; exit ${PIPESTATUS[0]}'`.chomp

      raise ExtractionFailed, result if $? != 0
      result
    end

    def timeout
      "#{timeout_bin} #{COMMAND_TIMEOUT}"
    end

    def timeout_bin
      # gtimeout on Mac
      `which timeout` != "" ? "timeout" : "gtimeout"
    end
  end
end
