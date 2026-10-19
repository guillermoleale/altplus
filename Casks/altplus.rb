cask "altplus" do
  version "0.1.0"
  sha256 "8dc0cb78273e6d7c6416eb64afef79408c52cae31598aa76d880c1a0ad7d0695"

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
