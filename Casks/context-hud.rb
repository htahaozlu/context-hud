cask "context-hud" do
  version "0.1.8"
  sha256 "c0e15752953675e4494bf2b7c6f67a1ea3d45a1f27195cfbcf2fbbb6e407134b"

  url "https://github.com/htahaozlu/context-hud/releases/download/v#{version}/ContextHUD.dmg",
      verified: "github.com/htahaozlu/context-hud/"
  name "ContextHUD"
  desc "Local-first repo context generator with a native macOS menubar companion"
  homepage "https://github.com/htahaozlu/context-hud"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :ventura"

  app "ContextHUD.app"

  zap trash: [
    "~/.context-hud",
    "~/Library/Preferences/com.htahaozlu.contexthud.plist",
    "~/Library/Saved Application State/com.htahaozlu.contexthud.savedState",
  ]
end
