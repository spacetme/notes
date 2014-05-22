
require 'open-uri'

def fetch(url, depth=0)
  puts "#{'  ' * depth}#{url}"
  return unless url =~ /\.css/ or url['fonts.googleapis.com/css?']
  open(url, &:read).scan(/http[^\s)'"]+/) do |n|
    fetch(n, depth + 1)
  end
end

fetch ARGV[0]
