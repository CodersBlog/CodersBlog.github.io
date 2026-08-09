# encoding: utf-8
#
# IndexNow 제출 스크립트 — 네이버 / Bing / Yandex / Seznam / Yep 에 새 글을 즉시 통보한다.
# 구글은 IndexNow 에 참여하지 않으므로 여기 포함되지 않는다 (구글은 Search Console 수동 요청뿐).
#
# 사용법:
#   ruby .blog-automation/indexnow.rb <URL> [<URL> ...]   # 지정한 URL 제출
#   ruby .blog-automation/indexnow.rb --latest            # 사이트맵에서 가장 최근 글 1개
#   ruby .blog-automation/indexnow.rb --all               # 사이트맵의 모든 글 (최초 1회용)
#
# 키는 repo 루트의 <키>.txt 파일명에서 읽는다 (파일명 = 키 = 소유 증명). 별도 설정 없음.

require "net/http"
require "uri"
require "json"

ROOT = File.expand_path("..", __dir__)
HOST = "codersblog.github.io"
SITE = "https://#{HOST}"

ENDPOINTS = [
  "https://api.indexnow.org/indexnow",          # 참여 검색엔진 전체로 전파
  "https://searchadvisor.naver.com/indexnow"    # 네이버 직접 (전파 지연 대비)
]

def key
  found = Dir[File.join(ROOT, "*.txt")]
          .map { |p| File.basename(p, ".txt") }
          .select { |n| n =~ /\A[0-9a-fA-F]{32,128}\z/ }
  abort "!! repo 루트에 IndexNow 키 파일(<32자이상hex>.txt)이 없습니다." if found.empty?
  abort "!! 키 파일이 여러 개입니다: #{found.join(", ")}" if found.size > 1
  found.first
end

def sitemap_post_urls
  xml = Net::HTTP.get(URI("#{SITE}/sitemap.xml"))
  locs = xml.scan(%r{<loc>([^<]+)</loc>}).flatten
  # lastmod 와 짝지어 최신순 정렬
  entries = xml.scan(%r{<url>\s*<loc>([^<]+)</loc>\s*(?:<lastmod>([^<]*)</lastmod>)?}m)
  posts = entries.select { |loc, _| loc.include?("/posts/") }
  posts.sort_by { |_, mod| mod.to_s }.reverse.map(&:first)
rescue => e
  abort "!! 사이트맵을 읽지 못했습니다: #{e.message}"
end

urls =
  case ARGV[0]
  when "--all"    then sitemap_post_urls
  when "--latest" then sitemap_post_urls.first(1)
  when nil        then abort("사용법: ruby .blog-automation/indexnow.rb <URL...> | --latest | --all")
  else ARGV
  end

urls = urls.uniq.reject(&:empty?)
abort "!! 제출할 URL 이 없습니다." if urls.empty?

bad = urls.reject { |u| u.start_with?(SITE) }
abort "!! 이 사이트 URL 이 아닙니다: #{bad.join(", ")}" unless bad.empty?

k = key
payload = {
  "host"        => HOST,
  "key"         => k,
  "keyLocation" => "#{SITE}/#{k}.txt",
  "urlList"     => urls
}

puts "제출 대상 #{urls.size}개"
urls.first(5).each { |u| puts "  #{u}" }
puts "  … 외 #{urls.size - 5}개" if urls.size > 5
puts

ENDPOINTS.each do |ep|
  uri = URI(ep)
  begin
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json; charset=utf-8")
      req.body = JSON.generate(payload)
      http.request(req)
    end
    # 200 OK / 202 Accepted 가 정상. 202 는 "접수했고 키 검증은 나중에" 라는 뜻.
    ok = %w[200 202].include?(res.code)
    puts "#{ok ? "OK  " : "실패"} #{uri.host}  HTTP #{res.code} #{res.message}"
    puts "     #{res.body.to_s.strip[0, 200]}" unless res.body.to_s.strip.empty?
  rescue => e
    puts "실패 #{uri.host}  #{e.class}: #{e.message}"
  end
end
