# encoding: utf-8
#
# 논문 후보 수집기 — 학회 상위 논문 목록을 훑어 블로그 관심 주제만 걸러낸다.
#
#   ruby .blog-automation/papers.rb cvpr 2026        # CVPR 하이라이트 수집 + 키워드 필터
#   ruby .blog-automation/papers.rb cvpr 2026 --all  # 필터 없이 전부
#   ruby .blog-automation/papers.rb verify "<논문 제목>"   # arXiv 원문에서 제목·저자·날짜 확인
#
# ⚠️ 수집 결과는 "후보"일 뿐이다. papers.yml 로 승격하기 전에 반드시 verify 를 거친다.
#    학회 페이지의 제목만 보고 글을 쓰면 저자·날짜·주장을 확인하지 않은 셈이 된다.

require "net/http"
require "uri"
require "cgi"

# 블로그가 다루는 주제. 새 관심사가 생기면 여기에 추가한다.
KEYWORDS = /agent|LLM|language model|multimodal|vision-language|VLM|reasoning|
            foundation model|prompt|context|memory|tool use|retrieval/xi

def fetch(url)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: 15, read_timeout: 60) do |http|
    http.request(Net::HTTP::Get.new(uri, "User-Agent" => "Mozilla/5.0"))
  end
  abort "!! HTTP #{res.code} — #{url}" unless res.code == "200"
  res.body.force_encoding("UTF-8").scrub
end

# ── CVPR ──────────────────────────────────────────────────────────
# CVPR 은 spotlight 를 쓰지 않는다. 등급은 Oral / Highlight / Poster 다.
# 하이라이트 목록: /virtual/<year>/events/Highlights<year>
def collect_cvpr(year, all: false)
  html = fetch("https://cvpr.thecvf.com/virtual/#{year}/events/Highlights#{year}")
  items = html.scan(%r{href="(/virtual/#{year}/poster/\d+)"[^>]*>\s*([^<]{8,200}?)\s*<}m)
              .map { |u, t| [u, t.gsub(/\s+/, " ").strip] }
              .reject { |_, t| t.empty? || t == "View full details" }
              .uniq { |_, t| t }
  puts "CVPR #{year} Highlight: #{items.size}건 수집"
  picked = all ? items : items.select { |_, t| t =~ KEYWORDS }
  puts all ? "" : "  키워드 매칭: #{picked.size}건"
  picked.map { |u, t| { title: t, url: "https://cvpr.thecvf.com#{u}", venue: "CVPR #{year} Highlight" } }
end

# ── arXiv 검증 ────────────────────────────────────────────────────
def verify(title)
  q = CGI.escape("ti:\"#{title}\"")
  xml = fetch("https://export.arxiv.org/api/query?search_query=#{q}&max_results=1")
  entry = xml[%r{<entry>.*?</entry>}m]
  return puts("  arXiv 에서 못 찾음 — 학회 페이지에만 있는 논문일 수 있다") unless entry

  t  = entry[%r{<title>(.*?)</title>}m, 1].to_s.gsub(/\s+/, " ").strip
  id = entry[%r{<id>http[^<]*/abs/([^<v]+)}, 1]
  pub = entry[%r{<published>([^<]+)</published>}, 1].to_s[0, 10]
  authors = entry.scan(%r{<name>([^<]+)</name>}).flatten

  puts "  제목: #{t}"
  puts "  arXiv: #{id}  (https://arxiv.org/abs/#{id})"
  puts "  발표: #{pub}   저자 #{authors.size}명: #{authors.first(4).join(", ")}#{authors.size > 4 ? " 외" : ""}"
  warn "  ⚠️ 검색한 제목과 다르다 — 동명이인 논문인지 확인할 것" unless t.downcase.include?(title.downcase[0, 30])
end

cmd = ARGV[0]
case cmd
when "cvpr"
  year = ARGV[1] || abort("연도를 지정하세요: ruby papers.rb cvpr 2026")
  rows = collect_cvpr(year, all: ARGV.include?("--all"))
  puts
  rows.each_with_index { |r, i| puts "#{(i + 1).to_s.rjust(3)}. #{r[:title]}" }
  puts
  puts "다음: 관심 가는 것을 골라 `ruby .blog-automation/papers.rb verify \"<제목>\"` 로 검증 후 papers.yml 에 등록"
when "verify"
  title = ARGV[1] || abort("제목을 지정하세요: ruby papers.rb verify \"Continual Harness\"")
  puts "검증: #{title}"
  verify(title)
else
  puts <<~USAGE
    사용법:
      ruby .blog-automation/papers.rb cvpr 2026          # CVPR 하이라이트에서 관심 주제만
      ruby .blog-automation/papers.rb cvpr 2026 --all    # 필터 없이 전부
      ruby .blog-automation/papers.rb verify "<제목>"     # arXiv 원문 확인
  USAGE
end
