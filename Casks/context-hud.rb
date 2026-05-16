cask "context-hud" do
  version "0.3.8"
  sha256 "6a7073ee5d7b462c6bd830a88a9b4af3227e213a8b82f33d7a3937f2491b80f9"

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
