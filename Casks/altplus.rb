cask "altplus" do
  version "0.0.0"
  sha256 :no_check

  url "https://github.com/guillermoleale/altplus/releases/download/v#{version}/AltPlus-#{version}.zip"
  name "AltPlus"
  desc "Minimal free window switcher"
  homepage "https://github.com/guillermoleale/altplus"

  depends_on macos: :sonoma

  app "AltPlus.app"

  # La app no está notarizada (no hay cuenta de desarrollador paga). Sin esto, Gatekeeper la bloquea.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/AltPlus.app"],
        must_succeed: false
  end

  uninstall quit: "org.altplus.AltPlus"

  zap trash: [
    "~/Library/Logs/AltPlus",
    "~/Library/Preferences/org.altplus.AltPlus.plist",
  ]
end
