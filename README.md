# Cell Bloom Arena

Godot 4.6 clean-room prototype for a basic cell-growth FFA arena. The prototype was built from public research into Nebulous.io-style mechanics, but it does not bundle original game assets, screenshots, skins, logos, or promotional artwork.

## Run

```sh
godot --path .
```

## Controls

- Mouse or WASD: move
- Space: split eligible blobs
- E: eject mass
- C: toggle classic display, hiding in-world names and procedural skin patterns
- G: toggle grid overlay
- P: pause
- R: respawn local player

## Current Scope

- Dark space arena with boundary.
- Procedural pellets, ejected mass, bots, leaderboard, and HUD.
- Fixed-step deterministic simulation.
- Mass-to-radius, mass-to-speed, recombine timer, camera zoom, and ejection loss math.
- Pellet consumption.
- Blob-vs-blob consumption with tunable mass ratio and overlap threshold.
- Basic split cap of 8 pieces.
- Recombine cooldown that scales with mass and caps near 40 seconds.
- Natural mass decay.
- Ejected mass with lossy conversion.
- Normal and blue black holes.
- Large blobs split/shrink on black holes around the public 243 mass threshold.
- Blue black holes grant +75 mass below threshold.
- Spatial hash broad phase for pellets, ejected mass, black holes, and blob contacts.

All public-research constants are centralized in `scripts/core/GameConstants.gd`.

## Verification

```sh
godot --headless --path . --script tests/sim_tests.gd
godot --headless --path . --quit-after 90
```

The first command runs simulation assertions. The second command boots the main scene for 90 frames in headless mode to catch scene/runtime errors.

## Research

The public-source research dossier is in `research/nebulous_io_public_research.md`. It links to public sources and records implementation assumptions. It intentionally avoids bundling original visual assets.

## License

MIT. See `LICENSE`.
