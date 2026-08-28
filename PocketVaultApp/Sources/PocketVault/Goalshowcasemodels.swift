import SwiftUI
#if !SKIP
import RealityKit
#endif

// Manifest for the hand-modeled "showcase" meshes (car.usdz, house.usdz,
// ...) that replace the voxel pile as the completion reveal in Build
// Studio. This is intentionally separate from GoalBuildLibrary's voxel
// data — voxels are procedural and cheap to generate for every GoalKind;
// these are one real mesh per category, hand-built and added to the
// bundle one at a time, so only SOME GoalKinds will have an entry here.
// Anything without one just keeps the voxel pile as its "finished" state,
// same as today.
//
// iOS-only for now — see the note in BuildStudioView.swift on why Android
// doesn't have an equivalent path yet.
enum GoalShowcaseModels {
    /// Filenames (without extension) of the .usdz files this maps to,
    /// as placed in Sources/PocketVault/Resources/Models/. Add an entry
    /// here the same day you add the .usdz to that folder — the two
    /// need to stay in sync or `hasShowcase` will say yes and the load
    /// will silently fail at runtime.
    private static let usdzNameByGoalKind: [GoalKind: String] = [
        .car: "car",
        .house: "house",
        // .flight: "plane",   // uncomment once plane.usdz is added
    ]

    static func hasShowcase(for goalKind: GoalKind) -> Bool {
        usdzNameByGoalKind[goalKind] != nil
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

    /// Loads the showcase entity for a goal kind, or nil if none exists
    /// yet or the load fails. Failures are logged, not thrown — a missing
    /// showcase model should silently fall back to the voxel pile, never
    /// crash Build Studio.
    @available(iOS 18.0, *)
    static func loadEntity(for goalKind: GoalKind) async -> Entity? {
        guard let name = usdzNameByGoalKind[goalKind] else { return nil }
        guard let url = resourceURL(for: name, extension: "usdz") else {
            print("GoalShowcaseModels: couldn't find \(name).usdz in any bundle — check it's added to the PocketVault target's Resources.")
            return nil
        }
        do {
            let entity = try await Entity(contentsOf: url)
            return entity
        } catch {
            print("GoalShowcaseModels: failed to load \(name).usdz — \(error)")
            return nil
        }
    }
    #endif
}
