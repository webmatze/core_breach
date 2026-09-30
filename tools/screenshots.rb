#!/usr/bin/env ruby
# Runs the game headless in DragonRuby, stages the scenes from
# tools/screenshot_scenes.rb and saves them as JPEGs for the README.
#
#   ruby tools/screenshots.rb [--out DIR]   # default: docs/screenshots
#
# Uses the DragonRuby version from Smaug.toml (or DRAGONRUBY_BIN) and the C
# extension in native/ when it has been built. JPEG conversion uses macOS's
# sips; elsewhere the PNGs are kept.
require "tmpdir"
require "fileutils"

root = File.expand_path("..", __dir__)
idx = ARGV.index("--out")
out = File.expand_path(idx ? ARGV[idx + 1] : File.join(root, "docs/screenshots"))
toml = File.read(File.join(root, "Smaug.toml"))[/\[dragonruby\][^\[]*/m]
version = toml[/^version\s*=\s*"([^"]+)"/, 1]
edition = toml[/^edition\s*=\s*"([^"]+)"/, 1] || "standard"
bin = ENV["DRAGONRUBY_BIN"] ||
      File.expand_path("~/Library/Application Support/org.Erebor-Studios.Smaug/dragonruby/#{edition}-#{version}/dragonruby")
abort "DragonRuby not found at #{bin}; set DRAGONRUBY_BIN" unless File.exist?(bin)

work = Dir.mktmpdir("core-breach-")
begin
  game = File.join(work, "game")
  FileUtils.mkdir_p(game)
  %w[app lib metadata sprites sounds native].each do |d|
    FileUtils.cp_r(File.join(root, d), game) if File.exist?(File.join(root, d))
  end
  FileUtils.mkdir_p(File.join(game, "screens"))
  FileUtils.cp(File.join(__dir__, "screenshot_scenes.rb"), File.join(game, "screenshot_scenes.rb"))
  log = File.join(game, "dragonruby.log")
  pid = Process.spawn({ "SDL_VIDEODRIVER" => "dummy", "SDL_AUDIODRIVER" => "dummy" }, bin, game,
                      "--eval", "screenshot_scenes.rb", out: log, err: log)
  deadline = Time.now + 300
  until Process.wait(pid, Process::WNOHANG)
    if Time.now > deadline
      Process.kill("KILL", pid)
      Process.wait(pid)
      abort "timed out; log tail:\n" + File.read(log).lines.last(30).join
    end
    sleep 0.2
  end
  report = File.join(game, "screens/report.txt")
  abort File.read(log).lines.last(40).join unless File.exist?(report)
  puts File.read(report)
  FileUtils.mkdir_p(out)
  Dir[File.join(game, "screens/*.png")].sort.each do |png|
    jpg = File.join(out, File.basename(png, ".png") + ".jpg")
    if system("sips", "-s", "format", "jpeg", "-s", "formatOptions", "85", png, "--out", jpg, out: File::NULL)
      puts "wrote #{jpg.sub("#{root}/", '')}"
    else
      FileUtils.cp(png, out)
      puts "wrote #{File.join(out, File.basename(png)).sub("#{root}/", '')}"
    end
  end
  exit(File.read(report).include?("FAIL") ? 1 : 0)
ensure
  FileUtils.rm_rf(work)
end
