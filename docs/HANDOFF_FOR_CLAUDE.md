# Mini Fire — Technical Handoff

A finished, tested Godot 4.4 project. 2D Mini‑Militia‑style jetpack shooter with LAN (Wi‑Fi) multiplayer,
bots, gun skins, two currencies (MFC soft coin, Gems), rewarded ads and gem packs (plugin-ready).
**Goal for you:** produce a signed Android APK and optionally wire up the ad and billing plugins.
**Do not refactor the gameplay or networking code.** It passes the smoke tests below.

## Engine
- Godot **4.4.1 stable** (standard build, not .NET). Renderer: `gl_compatibility` (works on low-end phones).
- Open the folder containing `project.godot`. First open re-imports and creates `.godot/` (ignored by git).

## Structure
```
project.godot            main scene, autoloads, display (1280x720, expand, sensor_landscape)
export_presets.cfg       Android preset, package com.minifire.game, permissions already set
autoload/
  catalog.gd             ALL game data: weapons, skins, colors, maps, modes, rewards, GEM_PACKS
  profile.gd             encrypted save (user://profile.save), wallet, owned skins, settings
  network.gd             ENet host/join (port 7777), UDP LAN discovery (7778), lobby RPCs, bots, match flow
  monetization.gd        facade for rewarded ads + Play Billing (plugins detected at runtime)
  sfx.gd                 procedural sound effects
scripts/                 player.gd, game.gd (host-authoritative combat), hud.gd, touch_controls.gd,
                         lobby.gd, main_menu.gd, shop.gd, gun_art.gd, ui_kit.gd, widgets.gd
scenes/                  main_menu.tscn, lobby.tscn, game.tscn (UI is built in code)
tests/                   test_runner.gd, screenshots.gd, run_tests.sh  (excluded from export)
docs/                    this file + Persian proposal (excluded from export)
```

## Networking model
- Host is authoritative: bullets, damage, kills, respawns, timer, pickups run on the host.
- Clients send input/state at 30 Hz; host broadcasts results via RPC.
- Bots have negative peer ids and run only on the host.
- Practice mode uses `OfflineMultiplayerPeer`, same code path.
- Join: auto discovery via UDP broadcast, or manual IP (the lobby shows the host's IPs).
  Some Android devices filter broadcast packets; manual IP join is the fallback.
  A phone hotspot works as the network.

## Smoke tests (run before and after any change)
```
tests/run_tests.sh practice            # expect: match started ... back in lobby OK ... DONE practice
tests/run_tests.sh host  & tests/run_tests.sh client   # LAN on 127.0.0.1, run both together
tests/run_tests.sh client_quit / host_quit             # disconnect handling
tests/run_tests.sh shots                # screenshots to /tmp/shots (needs xvfb-run)
```
The script writes a temporary `override.cfg` that adds the test autoload and deletes it on exit.
**Never ship an `override.cfg`.** Any line containing `SCRIPT ERROR` or `ERROR` is a failure.

## Android export (no plugins)
1. Editor → Manage Export Templates → install 4.4.1 templates.
2. Install JDK 17 and Android SDK (platform-tools, build-tools, a platform >= 34). Set paths in
   Editor Settings → Export → Android.
3. Create a release keystore:
   `keytool -genkeypair -v -keystore minifire.keystore -alias minifire -keyalg RSA -keysize 2048 -validity 10000`
   Put path/alias/passwords in the preset's Keystore → Release fields (keep the keystore out of git; back it up).
4. Edit `autoload/profile.gd`: replace `SAVE_KEY` with a long random string. (Changing it later invalidates saves.)
5. Project → Export → Android → Export Project (uncheck "Export With Debug") → `MiniFire.apk`.
   For Google Play use `gradle_build/export_format=1` (AAB) with Gradle build enabled.
Permissions already in the preset: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE.

## Plugins (optional, needed for revenue)
Both require **Use Gradle Build = ON** (Project → Install Android Build Template first).
`monetization.gd` finds plugin classes via `ProjectSettings.get_global_class_list()`, so the game compiles
and runs with or without them. Without plugins, the shop hides ads/packs (in the editor they are simulated,
see `SIMULATE_IN_EDITOR`).

### Rewarded ads — Poing Studios Godot AdMob Plugin
- https://github.com/poingstudios/godot-admob-plugin (Asset Library: "Godot AdMob"). Install the editor
  plugin and its Android library via its menu; enable it in Project Settings → Plugins.
- Set your AdMob **App ID** in the plugin's Android config (AndroidManifest meta-data).
- In `monetization.gd` replace `REWARDED_AD_UNIT` (currently Google's official test unit) with your unit id.
- Used API: `MobileAds.initialize()`, `RewardedAdLoader.new().load(unit, AdRequest.new(), RewardedAdLoadCallback)`,
  `ad.show(OnUserEarnedRewardListener)`. If the installed version renamed something, adapt only the
  `ADS` section of `monetization.gd`.
- Check the plugin's minSdk/compileSdk requirements and set them in the export preset.

### Gem packs — official GodotGooglePlayBilling
- https://github.com/godot-sdk-integrations/godot-google-play-billing (copy `addons/GodotGooglePlayBilling`, enable plugin).
- Docs: https://docs.godotengine.org/en/stable/tutorials/platform/android/android_in_app_purchases.html
- In Play Console create **consumable in-app products** with ids `gems_small`, `gems_medium`, `gems_large`.
- Flow implemented: `start_connection` → `query_purchases` (recovers unconsumed buys) → `purchase(id)` →
  purchase update (PURCHASED) → `consume_purchase(token)` → on consume OK → gems granted.
- Billing only works on a build installed from a Play test track with a licensed tester account.
- v2: replace the marked TODO in `_grant_purchase` with server-side verification.

## Things not to change without re-running tests
- RPC function names/signatures in `network.gd`, `game.gd`, `player.gd` (host and client must match;
  bump `Catalog.GAME_VERSION` if you change the protocol — mismatched versions are rejected).
- `Catalog` ids (weapon, skin, map ids are saved in profiles and sent over the network).
- Collision layers and map rectangles in `catalog.gd`.

## Common pitfalls
- Using Godot 4.3 or 4.5+ may produce warnings; stick to 4.4.1.
- If UI appears empty on device, ensure you did not replace `set_anchors_and_offsets_preset` calls.
- Windows firewall blocks LAN tests on PC; phones on the same Wi‑Fi/hotspot are fine.
