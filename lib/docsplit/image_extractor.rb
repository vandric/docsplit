module Docsplit

  # Delegates to GraphicsMagick in order to convert PDF documents into
  # nicely sized images.
  class ImageExtractor

    MEMORY_ARGS     = "-limit memory 256MiB -limit map 512MiB"
    DEFAULT_FORMAT  = :png
    DEFAULT_DENSITY = '150'
    COMMAND_TIMEOUT = 300 # seconds

    # Extract a list of PDFs as rasterized page images, according to the
    # configuration in options.
    def extract(pdfs, options)
      @pdfs = [pdfs].flatten
      extract_options(options)
      @pdfs.each do |pdf|
        previous = nil
        @sizes.each_with_index do |size, i|
          @formats.each {|format| convert(pdf, size, format, previous) }
          previous = size if @rolling
        end
      end
    end

    # Convert a single PDF into page images at the specified size and format.
    # If `--rolling`, and we have a previous image at a larger size to work with,
    # we simply downsample that image, instead of re-rendering the entire PDF.
    # Now we generate one page at a time, a counterintuitive opimization
    # suggested by the GraphicsMagick list, that seems to work quite well.
    def convert(pdf, size, format, previous=nil)
      tempdir   = Dir.mktmpdir
      basename  = File.basename(pdf, File.extname(pdf))
      directory = directory_for(size)
      pages     = @pages || '1-' + Docsplit.extract_length(pdf).to_s
      escaped_pdf = ESCAPE[pdf]
      FileUtils.mkdir_p(directory) unless File.exists?(directory)
      env = "MAGICK_TMPDIR=#{tempdir} OMP_NUM_THREADS=2"
      common = "#{MEMORY_ARGS} -density #{@density} #{resize_arg(size)} #{quality_arg(format)}"

      if previous
        FileUtils.cp(Dir[directory_for(previous) + '/*'], directory)
        # We're adding `| grep -v '^$' | uniq` here and below because if a corrupt PDF is parsed, it generates an infinite amount of identical warnings (with blank lines in between).
        # By filtering these we avoid memory bloat when the executing process tries to capture stdout.
        # See https://github.com/GetSilverfin/silverfin/issues/1998

        run(env, "gm mogrify #{common} -unsharp 0x0.5+0.75 \"#{directory}/*.#{format}\" 2>&1")
      else
        page_list(pages).each do |page|
          out_file = ESCAPE[File.join(directory, "#{basename}_#{page}.#{format}")]
          run(env, "gm convert +adjoin -define pdf:use-cropbox=true #{common} #{escaped_pdf}[#{page - 1}] #{out_file} 2>&1")
        end
      end
    ensure
      FileUtils.remove_entry_secure tempdir if File.exists?(tempdir)
    end

    private

    # Run an external process and raise an exception if it fails.
    def run(env, command)
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

    # Extract the relevant GraphicsMagick options from the options hash.
    def extract_options(options)
      @output  = options[:output]  || '.'
      @pages   = options[:pages]
      @density = options[:density] || DEFAULT_DENSITY
      @formats = [options[:format] || DEFAULT_FORMAT].flatten
      @sizes   = [options[:size]].flatten.compact
      @sizes   = [nil] if @sizes.empty?
      @rolling = !!options[:rolling]
    end

    # If there's only one size requested, generate the images directly into
    # the output directory. Multiple sizes each get a directory of their own.
    def directory_for(size)
      path = @sizes.length == 1 ? @output : File.join(@output, size)
      File.expand_path(path)
    end

    # Generate the resize argument.
    def resize_arg(size)
      size.nil? ? '' : "-resize #{size}"
    end

    # Generate the appropriate quality argument for the image format.
    def quality_arg(format)
      case format.to_s
      when /jpe?g/ then "-quality 85"
      when /png/   then "-quality 100"
      else ""
      end
    end

    # Generate the expanded list of requested page numbers.
    def page_list(pages)
      pages.split(',').map { |range|
        if range.include?('-')
          range = range.split('-')
          Range.new(range.first.to_i, range.last.to_i).to_a.map {|n| n.to_i }
        else
          range.to_i
        end
      }.flatten.uniq.sort
    end

  end

end
