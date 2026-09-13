#!/usr/bin/env ruby

require "pathname"
require "set"

repo = Pathname.new(__dir__).parent
book = repo.join("book")
summary = book.join("SUMMARY.md")
errors = []
summary_targets = Set.new
legacy_redirects = []

markdown_files = [repo.join("README.md"), *book.glob("**/*.md")]
markdown_files.each do |file|
  content = file.read
  local_link_count = 0
  open_fence = nil

  content.each_line.with_index(1) do |line, line_number|
    stripped = line.lstrip
    if open_fence
      closing = /\A#{Regexp.escape(open_fence[:char])}{#{open_fence[:length]},}[ \t]*(?:\r?\n)?\z/
      open_fence = nil if stripped.match?(closing)
    elsif (match = stripped.match(/\A([`~])\1{2,}/))
      marker = match[0]
      open_fence = { char: marker[0], length: marker.length, line: line_number }
    end

    line.scan(/\]\(([^)]+)\)/).flatten.each do |raw_target|
      target = raw_target.strip
      next if target.empty?
      next if target.start_with?("#", "http://", "https://", "mailto:")

      local_link_count += 1
      path_text = target.split("#", 2).first
      resolved = file.dirname.join(path_text).cleanpath
      unless resolved.exist?
        errors << "#{file.relative_path_from(repo)}:#{line_number}: missing #{target}"
      end

      if file == summary && resolved.file? && resolved.to_s.start_with?(book.to_s)
        summary_targets << resolved
      end
    end
  end

  if open_fence
    errors << "#{file.relative_path_from(repo)}:#{open_fence[:line]}: unclosed Markdown fence"
  end

  if content.include?("<!-- legacy-redirect -->")
    legacy_redirects << file
    line_count = content.lines.length
    if local_link_count.zero?
      errors << "#{file.relative_path_from(repo)}: legacy redirect has no local target"
    end
    if line_count > 80
      errors << "#{file.relative_path_from(repo)}: legacy redirect is too long (#{line_count} lines)"
    end
  end
end

public_pages = book.glob("**/*.md").reject { |path| path == summary }.to_set
unlisted = public_pages - summary_targets
unlisted.each do |path|
  errors << "SUMMARY.md: page not listed: #{path.relative_path_from(book)}"
end

if errors.empty?
  puts "Book links and SUMMARY coverage passed (#{public_pages.length} pages, #{legacy_redirects.length} legacy redirects)."
else
  warn errors.join("\n")
  exit 1
end
