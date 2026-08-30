import SwiftUI
#if !SKIP
import RealityKit
#endif

// Manifest for the hand-modeled "showcase" GLB meshes (car.glb, house.glb,
// ...) that progressively reveal during the build in Build Studio,
// replacing the generic voxel pile for the GoalKinds that have one.
// This is intentionally separate from GoalBuildLibrary's voxel data —
// voxels are procedural and cheap to generate for every GoalKind; these
// are one real mesh per category, hand-built and added to the bundle one
// at a time, so only SOME GoalKinds will have an entry here. Anything
// without one just keeps the voxel pile throughout the build, same as
// today.
//
// Both platforms: car.glb / house.glb are used for progressive reveal.
// RealityKit (iOS) loads the GLB directly and uses Entity.findEntity(named:)
// to grab individual named nodes. Android (SceneView / Filament) also uses
// the same GLB files; see Androidgoalshowcaseview.swift for how individual
// named glTF nodes are controlled on that side.
enum GoalShowcaseModels {
    /// The ordered list of named glTF node names for each goal kind that has
    /// a curated build asset. Reveal progresses through this list from first
    /// to last — body/chassis first (the major structural piece), then the
    /// 4 wheels, then the glass/lights (windshield, rear_window, headlight_l,
    /// headlight_r). House uses a similar structural-first ordering.
    ///
    /// Any GoalKind not in this dictionary falls back to the voxel pile
    /// for its entire build (no regression for flight, gamingRig, etc.).
    static let showcaseBuildOrder: [GoalKind: [String]] = [
        .car: [
            // 1. Chassis / body — the dominant visible structure
            "body",
            // 2–5. Four wheels in a natural reading order (left-front,
            //       left-rear, right-front, right-rear)
            "wheel_0", "wheel_1", "wheel_2", "wheel_3",
            // 6–9. Glass and lights — final details that complete the form
            "windshield", "rear_window", "headlight_l", "headlight_r",
        ],
        .house: [
            // 1. Walls — the building's primary mass
            "walls",
            // 2. Roof — rises above the walls
            "roof",
            // 3. Door
            "door",
            // 4–7. Four windows, left-to-right front face
            "window_1", "window_2", "window_3", "window_4",
            // 8. Chimney — the crowning detail
            "chimney",
        ],
    ]

    static func hasShowcase(for goalKind: GoalKind) -> Bool {
        showcaseBuildOrder[goalKind] != nil
    }

    /// Returns the GLB filename (without path/extension) for a goal kind's
    /// showcase asset. Matches the casing used in Resources/Models/ on disk.
    private static func glbName(for goalKind: GoalKind) -> String? {
        switch goalKind {
        case .car: return "car"
        case .house: return "house"
        default: return nil
        }
    }

    #if !SKIP
    // FIX ("'module' is inaccessible due to 'internal' protection
    // level"): `Bundle.module` is SPM's auto-generated accessor for a
    // package target's own resource bundle — but in this project's
    // Xcode-wrapped-package setup, this file doesn't compile as "the
    // PocketVault module" from the compiler's point of view, so that
    // synthesized `internal` accessor isn't visible here even though the
    // resources really did get copied in under Package.swift's
    // `resources: [.process("Resources")]`.
    //
    // Workaround: don't depend on Bundle.module at all. Search the set of
    // bundles that could plausibly contain it instead — Bundle.main
    // (resources copied straight into the app, which is what this
    // project's Xcode wrapping appears to actually do) first, then every
    // bundle currently loaded into the process (covers the "resources
    // ended up in a separate .bundle" case instead), matching by the
    // resource-bundle naming convention SPM uses
    // ("<PackageName>_<TargetName>.bundle").
    private static func resourceURL(for name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// Loads the full GLB entity for a goal kind (including all named
    /// child nodes), or nil if none exists yet or the load fails.
    /// Failures are logged, not thrown — a missing showcase model should
    /// silently fall back to the voxel pile, never crash Build Studio.
    ///
    /// FIX (silent iOS fallback): the original loader looked for
    /// "\(name).usdz" with lowercase names. The actual bundled files are
    /// "Car.usdc" / "House.usdc" — wrong extension (RealityKit's
    /// `Entity(contentsOf:)` does accept .usdc, but the manifest was
    /// asking for .usdz so it never matched) AND wrong case (the iOS
    /// `Bundle` URL API is case-sensitive on the resource name). The
    /// combined effect was that the load silently returned nil every
    /// single time on iOS, and the completion reveal fell back to the
    /// voxel pile for every goal kind that had a showcase asset.
    ///
    /// The new canonical path is the .glb file (already used on Android
    /// via the same Resources/Models/ folder) — same model, same nodes,
    /// no format ambiguity. We still attempt the .usdc path as a fallback
    /// for any caller that hasn't migrated to loadGLBEntity yet.
    @available(iOS 18.0, *)
    static func loadGLBEntity(for goalKind: GoalKind) async -> Entity? {
        guard let name = glbName(for: goalKind) else { return nil }
        guard let url = resourceURL(for: name, extension: "glb") else {
            print("GoalShowcaseModels: couldn't find \(name).glb in any bundle — check it's added to the PocketVault target's Resources.")
            return nil
        }
        do {
            let entity = try await Entity(contentsOf: url)
            return entity
        } catch {
            print("GoalShowcaseModels: failed to load \(name).glb — \(error)")
            return nil
        }
    }

    /// Loads the showcase entity for a goal kind using the legacy .usdc
    /// path. Kept for binary compatibility with any caller that still
    /// holds a reference to it. New code should use loadGLBEntity(for:).
    @available(iOS 18.0, *)
    @available(*, deprecated, message: "Use loadGLBEntity(for:) — loads the GLB which is the same model used on Android.")
    static func loadEntity(for goalKind: GoalKind) async -> Entity? {
        // Try the .glb path first (the canonical, shared-with-Android format).
        if let entity = await loadGLBEntity(for: goalKind) {
            return entity
        }
        // Fall back to .usdc (the old path that the original manifest was
        // trying to use, but with the right extension and case now).
        guard let name = glbName(for: goalKind) else { return nil }
        guard let url = resourceURL(for: name, extension: "usdc") else { return nil }
        do {
            return try await Entity(contentsOf: url)
        } catch {
            print("GoalShowcaseModels: failed to load \(name).usdc — \(error)")
            return nil
        }
    }
    #endif
}
