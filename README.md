# Xodus Nexus on ArmadaOS (ARM64)

These scripts install [Xodus Nexus](https://github.com/domsvoboda/xodus-nexus) on an ARM64 handheld with [ArmadaOS](https://armadaos.dev/). Xodus Nexus is a launcher for Microsoft Store and PC Game Pass games on Linux. It is available only for x86_64. On ArmadaOS, it runs through the [FEX](https://github.com/FEX-Emu/FEX) x86 translation layer, after the fixes in this repository.

Tested on an AYN Odin 3 (Snapdragon 8 Elite) with ArmadaOS 20261010 and Xodus Nexus 0.3.9. Sign-in, the game library, and games work in Desktop Mode and in Game Mode.

This project is not part of Xodus Nexus, Xodus, ArmadaOS, or Microsoft. Do not report problems with this setup to the Xodus Nexus developer.

## Install

Do these steps in Desktop Mode, in Konsole:

```bash
git clone https://github.com/burghr/xodus-nexus-armada-arm.git
cd xodus-nexus-armada-arm
./install.sh
```

The installer asks before it closes Steam. If you do not have a KDE wallet yet, a KDE Wallet window opens. In that window, do these steps:

1. Select **Classic** (not GPG).
2. Leave the password fields **empty**.

At the end, the installer opens Google Chrome one time. Accept the Chrome terms, then close Chrome. The Microsoft sign-in does not work until you accept them.

Then the installer opens Xodus Nexus. Do these steps:

1. Sign in one time.
2. In Game Mode, start **Xodus Nexus** from your Steam library.

Later, open **Xodus Nexus (FEX)** from the app menu, or from Steam.

### Options

| Option | What it does |
|---|---|
| `--appimage PATH` | Use an AppImage that you already have. The default is to download the latest release. |
| `--no-chrome` | Do not install the Google Chrome Flatpak. |
| `--no-wallet` | Do not set up the KDE wallet. |
| `--no-steam` | Do not add the Steam shortcut. |
| `--no-launch` | Do not open Chrome and Xodus Nexus at the end. |
| `-y` | Answer yes to all questions. |

You can run the installer again at any time. Each step skips what is already done.

## What the installer does

| Step | Why |
|---|---|
| Downloads the latest Xodus Nexus AppImage to `~/.local/share/xodus-nexus-fex/` and checks its SHA-512 checksum | The launcher updates itself in place, so the file name stays the same. |
| Installs the x86_64 NSS libraries from the Arch Linux package to `~/.local/lib/xodus-x86_64/` | The FEX RootFS does not have NSS. Without NSS, the app stops at start and shows no error. |
| Installs a `pkexec` stand-in that only Xodus Nexus uses | The backend uses `pkexec` to read SMBIOS data. ARM devices have no SMBIOS data, so the password prompt fails again and again. The backend continues without the data. |
| Installs the start script `~/.local/bin/xodus-nexus-fex` and a menu item | See below. |
| Installs Google Chrome from Flathub for your user | The Microsoft sign-in uses Chrome. |
| Makes a KDE wallet with no password, or offers to remove the password from your wallet | Xodus Nexus stores the sign-in in the wallet. Game Mode cannot show a password window, so only a wallet with no password can unlock there. |
| Adds a non-Steam shortcut to Steam | Then you can start Xodus Nexus in Game Mode. |

The start script does these steps each time:

1. It adds the NSS libraries and the `pkexec` stand-in for Xodus Nexus only.
2. If the KDE wallet service does not run (Game Mode), it starts the service.
3. It unlocks the wallet.
4. It starts the AppImage with `--no-sandbox`, because the Chromium sandbox crashes under FEX.
5. When the app closes, it stops the wallet service that it started, so that Steam sees the game end.

All files go in your home folder. ArmadaOS updates do not change them.

## Security

A KDE wallet with no password is not encrypted with a password. Each program that runs as your user can read it. On a handheld that holds only game logins, this is a small risk. Do not keep other important passwords in this wallet.

## Uninstall

Close Steam first. Then run:

```bash
./uninstall.sh
```

Your games, your KDE wallet, Google Chrome, and the Xodus Nexus settings in `~/.config/xodus-nexus` stay.

## Troubleshooting

| Problem | Fix |
|---|---|
| You are signed out in Game Mode | Your wallet has a password. Restart the device, go to Desktop Mode, and run `./install.sh` again before you open any app. The wallet is still locked then, so the installer can find the password and offer to remove it. |
| `keyring-unavailable` in Desktop Mode | Run `./install.sh` again to make the wallet. |
| "Google Chrome was not found" | Run `./install.sh` again without `--no-chrome`. |
| The app does not open | Run `~/.local/bin/xodus-nexus-fex` in Konsole and read the error. |
| `git clone` asks for a username and password | The URL has a typo. GitHub asks for a sign-in when a repository does not exist. This repository is public and needs no sign-in. |

## License

MIT. See [LICENSE](LICENSE).
