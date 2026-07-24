#!/usr/bin/env ruby

require "pathname"
require "set"

repo = Pathname.new(__dir__).parent
book = repo.join("book")
summary = book.join("SUMMARY.md")
errors = []
summary_targets = Set.new

markdown_files = [repo.join("README.md"), *book.glob("**/*.md")]
markdown_files.each do |file|
  file.read.each_line.with_index(1) do |line, line_number|
    line.scan(/\]\(([^)]+)\)/).flatten.each do |raw_target|
      target = raw_target.strip
      next if target.empty?
      next if target.start_with?("#", "http://", "https://", "mailto:")

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
end

public_pages = book.glob("**/*.md").reject { |path| path == summary }.to_set
unlisted = public_pages - summary_targets
unlisted.each do |path|
  errors << "SUMMARY.md: page not listed: #{path.relative_path_from(book)}"
end

if errors.empty?
  puts "Book links and SUMMARY coverage passed (#{public_pages.length} pages)."
else
  warn errors.join("\n")
  exit 1
end
