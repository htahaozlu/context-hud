cask "context-hud" do
  version "0.1.3"
  sha256 "76a8333618cfdddc4af46295082fa94bc45dd38f8d0913f5bc5dac01d66647d6"

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
