source "https://rubygems.org"

# Jekyll & Chirpy 테마
gem "jekyll", "~> 4.3"
gem "jekyll-theme-chirpy"

# _config.yml의 plugins와 일치시킵니다
group :jekyll_plugins do
  gem "jekyll-seo-tag"
  gem "jekyll-sitemap"
  gem "jekyll-feed"
  # gem "jekyll-archives"   # (옵션) Actions 빌드에서만 사용 권장
end

# Windows 로컬 실행 보완용
gem "webrick", "~> 1.8", platforms: [:mingw, :mswin, :x64_mingw]
gem "tzinfo", "~> 2.0"
gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw]

# (옵션) 링크 검증 등 테스트 도구
group :test do
  gem "html-proofer", "~> 5.0"
end