# Homebrew cask for EdgePin. publish.sh fills in the version and checksum and
# opens a pull request with this file against ../homebrew-tap.
#
# Users then run:
#   brew install --cask magici-labs/tap/edgepin
cask "edgepin" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/Magici-Labs/edgepin/releases/download/v#{version}/EdgePin-#{version}.zip"
  name "EdgePin"
  desc "Pin a window to a screen edge and keep other windows out of its space"
  homepage "https://github.com/Magici-Labs/edgepin"

  depends_on macos: :ventura

  app "EdgePin.app"

  uninstall quit: "com.magicilabs.edgepin"

  zap trash: [
    "~/Library/Logs/edgepin.log",
    "~/Library/Preferences/com.magicilabs.edgepin.plist",
  ]

  caveats <<~EOS
    EdgePin moves other apps' windows, so macOS asks for Accessibility access
    the first time it runs. To start it at login, tick Start at Login in its menu.
  EOS
end
