cask "slicky" do
  version "1.2"
  sha256 "d314e76aaabf1acda95ccd7498e6ec5cf6bfa1bf55d038251c77d197dac369f3"

  url "https://github.com/ananthasharma/Slicky/releases/download/v#{version}/Slicky.zip",
      verified: "github.com/ananthasharma/Slicky/"
  name "Slicky"
  desc "Desktop robot that hops around and opens your apps"
  homepage "https://github.com/ananthasharma/Slicky"

  livecheck do
    url :url
    strategy :github_latest
  end

  # He updates himself from GitHub releases, so `brew upgrade` leaves him alone
  # unless you ask for it with --greedy.
  auto_updates true
  depends_on macos: :sonoma

  app "Slicky.app"

  zap trash: [
    "~/Library/Preferences/com.slicky.desktop.plist",
    "~/Library/Saved Application State/com.slicky.desktop.savedState",
  ]
end
