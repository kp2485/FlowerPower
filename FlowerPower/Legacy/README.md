# Legacy

The original 2023 model layer, kept for reference until the new engine has been
run on device.

These files are superseded by the `FlowerPowerCore` package, which took over
their responsibilities and fixed the bugs in them:

| Old file | Replaced by | What changed |
|---|---|---|
| `BeeModel.swift` | `Model/Bee.swift` | Value type with identity, condition, wear, and summer/winter physiology. |
| `WorkerModel.swift` | `Model/Bee.swift` (`WorkerJob`) | Job ranges are tested independently instead of in a first-match-wins `switch`, which had made guard bees and foragers unreachable. |
| `HiveModel.swift` | `Model/Hive.swift`, `Model/Comb.swift` | The hive keeps its location, comb is modelled as cell types, and the twenty-odd hand-written `total…` counters collapsed into two generic queries. |
| `BiomeModel.swift` | `Core/Season.swift`, `Core/Weather.swift`, `Model/Threats.swift` | The biome was never instantiated. Its content became seasons, weather and a predator model that the simulation actually uses. |
| `HiveView.swift` | `Views/NestView.swift` | A single-column list of hexagons became a concentric comb laid out the way a colony really organises its nest. |
| `ContentView.swift` | `Views/ContentView.swift` | Was still Xcode's "Hello, world!" template. |

**These files are excluded from every build target.** `project.yml` lists this
folder under `excludes`, so `xcodegen generate` will not pick it up.

That was not always true. Until 2026-09 the checked-in `project.pbxproj` still
compiled five of these files, at their old paths one level up — which is why
the project would not build at all after the pivot moved them here. The
generated project has no such stale references by construction.

Delete the folder once the new app has been run on device and nothing here is
wanted.
