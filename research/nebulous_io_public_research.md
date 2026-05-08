# Nebulous.io Public Research Dossier

Date: 2026-05-08
Scope: clean-room Godot recreation of the core FFA/basic Nebulous.io mode from public sources only.

## Source Set

- Official site: https://www.simplicialsoftware.com/
- Official FAQ: https://www.simplicialsoftware.com/faqs/en/index.html
- Google Play listing: https://play.google.com/store/apps/details?id=software.simplicial.nebulous
- Apple App Store listing: https://apps.apple.com/us/app/nebulous-io/id1069691018
- Japanese community wiki, system page: https://wikiwiki.jp/nebulous/%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0
- Japanese community wiki, game modes page: https://wikiwiki.jp/nebulous/%E3%82%B2%E3%83%BC%E3%83%A0%E3%81%AE%E9%81%8A%E3%81%B3%E6%96%B9
- Japanese community wiki, dots and black holes: https://wikiwiki.jp/nebulous/%E7%B2%92%E3%83%BB%E3%83%96%E3%83%A9%E3%83%83%E3%82%AF%E3%83%9B%E3%83%BC%E3%83%AB
- Japanese community wiki, solo techniques: https://wikiwiki.jp/nebulous/%E3%83%86%E3%82%AF%E3%83%8B%E3%83%83%E3%82%AF%281%E4%BA%BA%E7%94%A8%29

Visual references were inspected from the official site and store listings during development, but no original screenshots, skins, logos, promotional art, or other game assets are bundled in this repository.

## Confirmed Public Facts

### Core Loop

- Players control blobs in a bounded arena.
- Blobs grow by collecting small dots and consuming smaller player blobs.
- Larger blobs move slower than smaller blobs.
- The goal in FFA/basic mode is to become the biggest blob and climb the server leaderboard.

### Supported Basic Features

- Online multiplayer is supported, with the current Android listing saying up to 32 players per game.
- Offline single-player exists.
- FFA, Timed FFA, FFA Ultra, FFA Classic, Teams, Timed Teams, Capture the Flag, Survival, Soccer, Domination, Mayhem, Battle Royale, Squid Game, and RPG are listed, but this project will implement only the basic FFA/classic-style cell-eating game.
- Space and grid visual themes exist.
- Multiple control schemes exist.

### Controls

- Touch control pad moves the blob.
- Split button launches some of the player's mass in the direction of movement.
- Eject button ejects mass in the current movement direction.
- Ejected mass can move black holes.
- Splitting gives a short speed/escape boost.

### Split and Recombine

- Public community system note: splitting is possible from score/mass 20 or above.
- Public community system note: classic split cap is 8 pieces.
- Official FAQ and store text both confirm split pieces eventually recombine.
- Public community system note: recombine wait grows with score/mass and can reach about 40 seconds.
- Current ecosystem also has 16x/32x/64x split options in some modes/contexts, but basic mode target should start with 8 pieces unless FFA Ultra/custom rules are explicitly enabled.

### Natural Mass Decay

- Public community system note: blob score naturally decreases by a constant proportion over time.
- The note says very small blobs below 100 may look stable, but fractional loss is still happening internally.
- The note gives an example that around 15,000 score, delaying can quickly lose about 1,000 score.

### Ejected Mass

- Public community system note: ejection is available when score/mass is at least 20.
- Ejected pellet mass scales with the source blob mass.
- Ejection has loss: mass consumed by the source is greater than the mass gained by the ejected pellet.
- Ejection direction follows current movement direction.
- Ejected mass can push/move black holes.

### Eating

- Public community system note: when two blobs overlap, one consumes the other if it is sufficiently larger.
- Consuming grants the victim score/mass.
- Exact ratio is not public in the sources found so far.

### Black Holes

- Black holes are present in the field.
- Small blobs can use black holes as refuge.
- Black holes affect blobs only if the blob is larger than the hole.
- Large blobs that collide with/try to absorb black holes split/explode into smaller blobs and become vulnerable.
- Community wiki gives a key threshold around mass 242/243:
  - At about mass 242 or above, eating/overlapping a normal black hole splits the blob into 8 pieces and reduces mass.
  - If already at the split cap, the blob loses mass by releasing small food instead.
  - Cyan/blue black holes give +75 mass when touched below mass 243, but act like normal black holes at mass 243 or above.
- Black holes drift naturally.
- Ejected mass moves black holes; larger ejected mass appears to push them more.

### FFA Classic

- Community wiki says FFA Classic is FFA without displaying names, skins, or levels.
- For this project's default "basic" implementation, use regular FFA gameplay rules and expose a display toggle that can approximate FFA Classic.

### HUD and Visual Style

- Gameplay uses a dark space backdrop with star/dot noise.
- Player blobs have circular outlines, skin fills, glow/halo effects, name text, clan/badge text, and numeric score/mass underneath or near center.
- Top-left HUD shows level, score, and recombine countdown.
- Top-right HUD shows leaderboard entries with names and scores.
- Spectator mode shows "Spectating", score, and recombine values.
- A translucent circular joystick/control pad appears near the lower/right side in some layouts.
- Split/eject controls appear as square/circular action buttons depending on layout.
- Black holes/nova objects are swirling circular sprites, usually blue/cyan, green, purple, or black/gray.
- Dots are small multicolor pellets scattered densely across the arena.
- Boundary lines appear as thin cyan/green vertical/horizontal walls in some screenshots.

## Inferred Implementation Targets

These values should be treated as tunable hypotheses until judged against live gameplay/video.

- Server sim tick: 20 to 30 Hz authority tick.
- Client render: 60 Hz, support 120 Hz rendering if the platform allows.
- Snapshot send: 10 to 20 Hz with interpolation.
- Basic FFA max players: default 32.
- Split cap: 8 for basic/Classic; optional constants for 16/32/64 variants.
- Minimum split/eject mass: 20.
- Black hole danger threshold: 243.
- Blue/cyan black hole small-contact reward: +75 mass.
- Recombine cooldown: increasing function capped near 40 seconds.
- Eat ratio: begin with 1.10 to 1.25 mass ratio and tune by visual/gameplay tests.
- Consume overlap: require attacker center to overlap victim by a meaningful fraction, not just rim contact.
- Radius formula: use `radius = base_radius * sqrt(mass)` style, tune against screenshots.
- Speed formula: inverse mass curve with minimum speed clamp; small split pieces must feel significantly quicker.
- Natural decay: proportional per second above all sizes, but visually subtle under mass 100.
- Eject loss: source loss greater than pellet mass, pellet mass scales sublinearly or stepwise with source mass.

## Godot Architecture Implications

- Do not rely on Godot physics for blob collision. Use deterministic circle math.
- Keep sim data separate from view nodes:
  - `BlobPartState`
  - `PlayerState`
  - `PelletState`
  - `BlackHoleState`
  - `SimWorld`
  - `SpatialHash`
- Use fixed-step simulation.
- Use spatial hash for pellets, blobs, ejected mass, and black holes.
- Render blobs as procedural circles with placeholder generated skins/glows unless original assets are supplied or licensed.
- Authoritative multiplayer should be server-side from the beginning of the data model, even if the first milestone is offline.

## Milestone Plan

### M1: Public-Spec Sandbox

- Create Godot 4 project.
- Implement `MassMath`, `GameConstants`, `SpatialHash`, and deterministic `SimWorld`.
- Render dark space arena, dots, one player blob, boundaries, camera zoom, HUD score.
- Implement movement by target direction/control vector.
- Implement mass-to-radius and mass-to-speed curves as tunable constants.

### M2: Core Combat

- Implement blob-vs-pellet consumption.
- Implement blob-vs-blob consumption with tunable ratio and overlap threshold.
- Implement split at mass >= 20.
- Implement split impulse, split cap 8, recombine cooldown, and recombine countdown.
- Implement natural mass decay.

### M3: Eject and Black Holes

- Implement ejected mass at mass >= 20 with mass loss.
- Implement black hole drift and ejected-mass impulse.
- Implement normal black hole split/shrink behavior at mass >= 243.
- Implement safe refuge behavior below threshold.
- Implement blue/cyan black hole +75 mass below threshold and destructive behavior at/above threshold.

### M4: Basic FFA Feel

- Add bots using the same input interface.
- Add leaderboard.
- Add FFA Classic display toggle: hide names/skins/levels.
- Add mobile control layout and desktop mouse/keyboard mapping.
- Tune camera zoom, UI scale, starfield density, pellet density, and glow style against public screenshots.

### M5: Multiplayer Skeleton

- Add Godot headless authoritative server.
- Client sends input direction, split, eject.
- Server sends visible-entity snapshots.
- Client interpolates snapshots and locally smooths own player.
- Add reconnect/spectator/spectating mode.

### M6: Verification Harness

- Unit tests for mass conservation, split cap, recombine timer, black hole threshold, ejection loss, and natural decay.
- Bot stress tests at 32 players plus thousands of pellets.
- Screenshot tests for desktop landscape and mobile landscape aspect ratios.
- Manual comparison against official screenshots and public gameplay clips.

## Known Gaps After First Pass

- Exact mass-to-radius formula.
- Exact mass-to-speed formula.
- Exact eat ratio and overlap requirement.
- Exact split launch distance/impulse curve.
- Exact ejected-mass size, loss, and cooldown.
- Exact natural decay percentage.
- Exact black hole mass/size and split mass distribution.
- Exact map sizes by room type, including "huge" maps.
- Exact network protocol and server tickrate.
- Current live basic mode UI may differ from older official screenshot gallery.

## Research Decision

The first playable Godot build should be a clean-room approximation with all uncertain mechanics exposed in `GameConstants.gd`. The true test is not whether Codex can invent these systems, but whether it can converge toward the original by iterating against publicly observable gameplay without private constants.
