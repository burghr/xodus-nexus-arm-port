# Xodus Nexus on ArmadaOS (ARM64)

> **An unofficial side project.** This is not an official port of Xodus Nexus. It is not part of Xodus Nexus, Xodus, ArmadaOS, or Microsoft. I made it because I wanted PC Game Pass on my ARM handheld, and I maintain it in my free time. I do my best to answer bug reports and to keep up with new Xodus Nexus releases, but sometimes it may take longer than you like.
>
> The scripts and the arm64 build are provided as is, with no warranty. If something does not work, please [open an issue here](https://github.com/burghr/xodus-nexus-armada-arm/issues). Do not report problems with this setup to the Xodus Nexus developer.
>
> All the real work is by the [Xodus Nexus](https://github.com/domsvoboda/xodus-nexus), [ArmadaOS](https://armadaos.dev/), and [FEX](https://github.com/FEX-Emu/FEX) teams. Thank you to them.

These scripts install [Xodus Nexus](https://github.com/domsvoboda/xodus-nexus) on an ARM64 handheld with [ArmadaOS](https://armadaos.dev/). Xodus Nexus is a launcher for Microsoft Store and PC Game Pass games on Linux. Its official build is available only for x86_64.

The installer uses a native arm64 build of the launcher from the [xodus-nexus-arm](https://github.com/burghr/xodus-nexus-arm) fork. The backend, the Wine runtime, and the games are still x86_64, and they run through the [FEX](https://github.com/FEX-Emu/FEX) x86 translation layer that ArmadaOS includes.

Tested on an AYN Odin 3 (Snapdragon 8 Elite) with ArmadaOS 20261010 and Xodus Nexus 0.3.10. Sign-in, the game library, **Add to Steam**, and games work in Desktop Mode and in Game Mode.

## Install

Do these steps in Desktop Mode, in Konsole:

```bash
git clone https://github.com/burghr/xodus-nexus-armada-arm.git
cd xodus-nexus-armada-arm
./install.sh
```

The installer asks before it closes Steam. If you do not have a KDE wallet yet, the installer asks if you want a wallet password (see [Wallet password](#wallet-password)). Then a KDE Wallet window opens. In that window, do these steps:

1. Select **Classic** (not GPG).
2. Type your password in both password fields, or leave them **empty** if you chose no password.

At the end, the installer opens Google Chrome one time. Accept the Chrome terms, then close Chrome. The Microsoft sign-in does not work until you accept them.

Then the installer opens Xodus Nexus. Do these steps:

1. Sign in one time.
2. Open **Settings**, then select **Install Nexus runtime**. Games do not start without the runtime. Do this one time.
3. In Game Mode, start **Xodus Nexus** from your Steam library.

Later, open **Xodus Nexus** from the app menu, or from Steam.

### Games that you add to Steam

Use the **Add to Steam** button in Xodus Nexus to put a game in your Steam library. The game shortcut works in Game Mode with no other step.

If Decky Loader is installed, the game artwork shows in Steam at once. Without Decky, it shows after the next Steam start.

### Update

The arm64 build does not update itself. To update it, run the installer again in Desktop Mode:

```bash
cd xodus-nexus-armada-arm
git pull
./install.sh
```

If there is a new release, the installer downloads it. Close Xodus Nexus first.

### Earlier installs with the x86_64 build

Earlier versions of these scripts installed the x86_64 build, which ran through FEX. If you have that install, run the steps in [Update](#update). The installer asks before it replaces the x86_64 build. Your sign-in, settings, games, and Steam shortcuts stay. The installer also removes the x86_64 libraries that the earlier install added.

The `--fix-shortcuts` option is not necessary now.

### Options

| Option | What it does |
|---|---|
| `--appimage PATH` | Use an arm64 AppImage that you already have. The default is to download the latest release. |
| `--no-chrome` | Do not install the Google Chrome Flatpak. |
| `--no-wallet` | Do not set up the KDE wallet. |
| `--no-steam` | Do not add the Steam shortcut. |
| `--no-launch` | Do not open Chrome and Xodus Nexus at the end. |
| `-y` | Answer yes to all questions. |

You can run the installer again at any time. Each step skips what is already done.

## What the installer does

| Step | Why |
|---|---|
| Downloads the latest arm64 AppImage from the xodus-nexus-arm releases to `~/.local/share/xodus-nexus-fex/`, and checks its SHA-512 checksum | The native launcher is faster than the x86_64 launcher under FEX, mostly in the game search and the game list. |
| Installs a `pkexec` stand-in that only Xodus Nexus uses | At sign-in, the backend uses `pkexec` to read SMBIOS data. ARM devices have no SMBIOS data, so the password prompt fails again and again. The backend continues without the data. |
| Installs the start script `~/.local/bin/xodus-nexus-fex` and a menu item | The start script puts the `pkexec` stand-in first in `PATH`, then starts the AppImage. |
| Installs Google Chrome from Flathub for your user | The Microsoft sign-in uses Chrome. |
| Makes a KDE wallet, with or without a password | Xodus Nexus stores the sign-in in the wallet. |
| Adds a non-Steam shortcut to Steam | Then you can start Xodus Nexus in Game Mode. |

The file and folder names come from the earlier x86_64 install, so they still say `fex` and `x86_64`. They stay the same, so that the Steam shortcuts of earlier installs still work.

All files go in your home folder. ArmadaOS updates do not change them.

## Wallet password

Xodus Nexus keeps your Microsoft sign-in in the KDE wallet. The installer lets you choose:

| Choice | What you do | Security |
|---|---|---|
| **No password** (the default, and the choice with `-y`) | Nothing | The wallet is not encrypted with a password. Each program that runs as your user, and each person with the device files, can read the sign-in. |
| **A password** | After each start of the device, Xodus Nexus asks for the password one time, also in Game Mode. Press **Steam + X** for the on-screen keyboard. | The wallet is encrypted with your password. |

ArmadaOS logs you in automatically, so nothing can unlock the wallet at boot without the password. A password that is saved on the device to unlock the wallet automatically gives about the same protection as no password. So the installer does not do that.

If your device is lost or stolen, go to [account.microsoft.com](https://account.microsoft.com/), and sign out of all devices. Do not keep other important passwords in a wallet with no password.

To remove the password later, run `./install.sh` just after a start of the device, before you open Xodus Nexus. The wallet is still locked then, so the installer can find the password and offer to remove it.

## Uninstall

Close Steam and Xodus Nexus first. Then run:

```bash
./uninstall.sh
```

The uninstaller removes the AppImage, the start script, the menu item, and the Steam shortcuts for Xodus Nexus and its games. Your games, the Xodus Nexus settings and sign-in, your KDE wallet, and Google Chrome stay.

| Option | What it also removes |
|---|---|
| `--remove-data` | The Xodus Nexus settings, the sign-in, the runtimes, and the Wine prefixes. Save games that are only in a prefix are lost. |
| `--remove-games` | The games that Xodus Nexus installed in its game folder. Imported games stay. |

Each option shows what it removes and asks before it removes it.

## Troubleshooting

| Problem | Fix |
|---|---|
| You are signed out in Game Mode | If your wallet has a password, type it in the window that Xodus Nexus shows. If no window shows, restart Xodus Nexus. |
| `keyring-unavailable` in Desktop Mode | Run `./install.sh` again to make the wallet. |
| "Google Chrome was not found" | Run `./install.sh` again without `--no-chrome`. |
| The app does not open | Run `~/.local/bin/xodus-nexus-fex` in Konsole and read the error. |
| `git clone` asks for a username and password | The URL has a typo. GitHub asks for a sign-in when a repository does not exist. This repository is public and needs no sign-in. |

## License

MIT. See [LICENSE](LICENSE).
