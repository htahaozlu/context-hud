cask "context-hud" do
  version "0.2.1"
  sha256 "cbd3b1a1716c0a7f2d94b60daf3441cf97b9f5de4a91d0e21dcd255d25afe552"

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
