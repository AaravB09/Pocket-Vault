import SwiftUI
#if !SKIP
import RealityKit
#endif

enum GoalKind: String, CaseIterable {
    case flight
    case car
    case gamingRig
    case emergencyFund
    case furniture
    case house
    case jewelry
    case custom

    static func from(presetName: String) -> GoalKind {
        switch presetName {
        case "Plane Ticket to Mexico": return .flight
        case "New Car": return .car
        case "Gaming Rig": return .gamingRig
        case "Emergency Fund": return .emergencyFund
        default: return .custom
        }
    }

    var displayIcon: String {
        switch self {
        case .flight: return "paperplane"
        case .car: return "car.side"
        case .gamingRig: return "cpu"
        case .emergencyFund: return "shield"
        case .furniture: return "shippingbox.fill"
        case .house: return "house.fill"
        case .jewelry: return "diamond.fill"
        case .custom: return "sparkles"
        }
    }

    // FIX: `displayIcon` was being handed straight to `Image(systemName:)`
    // at its call sites (ContentView's goal picker button, Goalpickerbar) —
    // not routed through `Image.platformSymbol(_:android:)` like every
    // other icon in the app. Per Platformsymbol.swift, "car.side", "cpu",
    // "shield", and "sparkles" specifically are outside Skip's Android
    // fallback table, so those 4 of the 8 GoalKind cases were rendering as
    // the "symbol not found" warning triangle instead of the actual goal
    // icon — i.e. exactly the cases that make a running goal (a car, a
    // gaming rig, an emergency fund, a custom/gift goal) identifiable at a
    // glance. Reusing the same Android stand-ins SetupGoalView's
    // GoalPreset already established for these identical icon names
    // (cpu -> gearshape.fill, car.side -> cart.fill, shield -> lock.fill)
    // plus the sparkles -> star.fill substitution used everywhere else in
    // the app. `.flight`/`.furniture`/`.house`/`.jewelry` aren't in the
    // documented unsupported list (and shippingbox.fill/diamond.fill are
    // already used unwrapped elsewhere, e.g. ParticleBurst.swift), so
    // those four just pass the same name through unchanged.
    var androidDisplayIcon: String {
        switch self {
        case .flight: return "paperplane"
        case .car: return "cart.fill"
        case .gamingRig: return "gearshape.fill"
        case .emergencyFund: return "lock.fill"
        case .furniture: return "shippingbox.fill"
        case .house: return "house.fill"
        case .jewelry: return "diamond.fill"
        case .custom: return "star.fill"
        }
    }
}

enum VoxelMeshKind {
    case cube
    case cylinder
    case cone
    case flatSlab

    /// Parses the mesh name an AI-generated blueprint uses (see
    /// `AIVoxelPart`) — case-insensitive, with a couple of reasonable
    /// spelling variants. Returns nil for anything unrecognized so the
    /// caller can drop that one part rather than guess.
    init?(aiString: String) {
        switch aiString.lowercased() {
        case "cube", "box": self = .cube
        case "cylinder": self = .cylinder
        case "cone": self = .cone
        case "flatslab", "flat_slab", "slab": self = .flatSlab
        default: return nil
        }
    }
}

/// One part of an AI-generated voxel sculpture — see
/// AIGoalBuilderService, which prompts the model to describe a specific
/// custom goal (e.g. "cat food", "a guitar") as a small list of these
/// instead of always falling back to the generic gift box. Stored
/// verbatim as JSON on `Goal.customVoxelBlueprintJSON` so the same
/// sculpture persists across app launches instead of being regenerated
/// (and possibly changing shape) every time.
struct AIVoxelPart: Codable {
    let x: Double
    let y: Double
    let z: Double
    let mesh: String
    let color: String
    let metallic: Bool
}

private enum HexColorParser {
    /// Parses a "#RRGGBB" or "RRGGBB" hex string. Returns nil (rather than
    /// silently defaulting to black) so the caller can drop a part with
    /// a malformed color instead of rendering it wrong.
    static func parse(hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        
        guard cleaned.count == 6 else { return nil }
        
        var value = 0
        for char in cleaned.utf8 {
            value *= 16
            let c = Int(char)
            if c >= 48 && c <= 57 {
                value += c - 48 // 0-9
            } else if c >= 65 && c <= 70 {
                value += c - 55 // A-F (65 - 10 = 55)
            } else if c >= 97 && c <= 102 {
                value += c - 87 // a-f (97 - 10 = 87)
            } else {
                return nil
            }
        }
        
        let r = CGFloat((value / 65536) % 256) / CGFloat(255.0)
        let g = CGFloat((value / 256) % 256) / CGFloat(255.0)
        let b = CGFloat(value % 256) / CGFloat(255.0)
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}


/// A lightweight, fully cross-platform stand-in for `SIMD3<Float>`.
/// `SIMD3` comes from Apple's `simd` framework, which isn't available
/// under Skip, so `VoxelUnit` — which has to compute its `voxels.count`
/// on Android too, for the "X OF Y PIECES PLACED" label in
/// BuildStudioView — uses this instead of `SIMD3<Float>` for both
/// `position` and `VoxelOrientation.axis`. BuildStudioView's iOS-only
/// `spawnVoxel` converts it back to a real `SIMD3<Float>` right before
/// handing it to RealityKit. A single plain initializer only (no
/// `ExpressibleByArrayLiteral`/variadic init) — every call site below
/// uses `Vector3(x, y, z)` explicitly, since Skip's transpiler has
/// trouble disambiguating overloaded/variadic constructs.
struct Vector3 {
    var x: Float
    var y: Float
    var z: Float

    init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = Vector3(Float(0.0), Float(0.0), Float(0.0))
}

/// A lightweight, fully cross-platform stand-in for RealityKit's
/// `simd_quatf` (axis + angle rotation). `simd_quatf` itself comes from
/// Apple's `simd` framework, which isn't available under Skip, so
/// `VoxelUnit` — which has to compute its `voxels.count` on Android too,
/// for the "X OF Y PIECES PLACED" label in BuildStudioView — uses this
/// instead. BuildStudioView's iOS-only `spawnVoxel` converts it back to
/// a real `simd_quatf` right before handing it to RealityKit.
struct VoxelOrientation {
    var angle: Float
    var axis: Vector3

    static let identity = VoxelOrientation(angle: Float(0.0), axis: Vector3(Float(0.0), Float(1.0), Float(0.0)))
}

struct VoxelUnit {
    let position: Vector3
    let mesh: VoxelMeshKind
    let color: UIColor
    let isMetallic: Bool
    var orientation: VoxelOrientation
}

struct GoalBuildLibrary {
    /// Every GoalKind case is handled explicitly (no `default:` branch) so
    /// adding a new case that forgets a build won't silently fall back to
    /// the plane — the compiler will flag the missing switch case instead.
    ///
    /// `trimColor` is the app's current theme accent, converted to a
    /// UIColor at the call site (see BuildStudioView) — trim/accent
    /// pieces across every build reuse whichever color the user picked
    /// in Appearance instead of always being champagne gold.
    static func voxels(for kind: GoalKind, trimColor: UIColor = defaultTrimColor) -> [VoxelUnit] {
        switch kind {
        case .flight:
            return flightVoxels(trimColor: trimColor)
        case .car:
            return carVoxels(trimColor: trimColor)
        case .gamingRig:
            return gamingRigVoxels(trimColor: trimColor)
        case .emergencyFund:
            return emergencyFundVoxels(trimColor: trimColor)
        case .furniture:
            return furnitureVoxels(trimColor: trimColor)
        case .house:
            return houseVoxels(trimColor: trimColor)
        case .jewelry:
            return jewelryVoxels(trimColor: trimColor)
        case .custom:
            return giftVoxels(trimColor: trimColor)
        }
    }

    // MARK: - AI-Generated Custom Build
    /// Turns a stored AI blueprint (JSON-encoded `[AIVoxelPart]`) into
    /// real voxels for a custom goal the model was able to picture
    /// specifically — a bag of cat food, a guitar, a bike — instead of
    /// the generic gift box.
    ///
    /// Validates aggressively before trusting anything the model
    /// returned: bad JSON, a wildly wrong part count, out-of-bounds
    /// coordinates, or an unrecognized mesh/color all fall back to
    /// `giftVoxels` (with those bad parts simply dropped, or the whole
    /// thing discarded if too much survives filtering) rather than risk
    /// showing a broken or absurdly oversized sculpture.
    static func customVoxels(fromBlueprintJSON json: String, trimColor: UIColor) -> [VoxelUnit] {
        guard
            let data = json.data(using: .utf8),
            let parts = try? JSONDecoder().decode([AIVoxelPart].self, from: data),
            parts.count >= 6, parts.count <= 30
        else {
            return giftVoxels(trimColor: trimColor)
        }

        let bound = 0.6
        var units: [VoxelUnit] = []
        units.reserveCapacity(parts.count)

        for part in parts {
            guard
                part.x >= -bound, part.x <= bound, part.y >= -0.05, part.y <= bound, part.z >= -bound, part.z <= bound,
                let mesh = VoxelMeshKind(aiString: part.mesh),
                let color = HexColorParser.parse(hex: part.color)
            else {
                continue
            }
            units.append(VoxelUnit(
                position: Vector3(Float(part.x), Float(part.y), Float(part.z)),
                mesh: mesh,
                color: color,
                isMetallic: part.metallic,
                orientation: .identity
            ))
        }

        // If validation dropped too much of the shape, it's probably
        // broken — fall back rather than show a sparse, half-formed build.
        guard units.count >= 6 else { return giftVoxels(trimColor: trimColor) }
        return units
    }

    // MARK: - Palette
    // Structural pieces are non-metallic so they read as color under
    // direct light (metallic materials need environment reflections,
    // which this scene doesn't have — they'd render near-black otherwise).
    // Metallic is reserved for the gold/crimson trim, where the sheen matters.
    private static let charcoal = UIColor(red: 0.13, green: 0.15, blue: 0.2, alpha: 1.0)
    private static let indigo = UIColor(red: 0.2, green: 0.28, blue: 0.5, alpha: 1.0)
    private static let ivory = UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1.0)
    /// Fallback trim color when no theme accent is supplied (e.g. previews,
    /// or call sites that haven't been updated to pass one).
    static let defaultTrimColor = UIColor(red: 0.82, green: 0.72, blue: 0.52, alpha: 1.0)
    private static let crimson = UIColor(red: 0.72, green: 0.2, blue: 0.24, alpha: 1.0)
    // NOTE(skip): Skip's UIColor compatibility shim doesn't implement the
    // grayscale `init(white:alpha:)` overload — only `init(red:green:blue:alpha:)`.
    // Kotlin was matching this call against the RGB initializer instead,
    // finding no `white:` parameter, and then reporting `green`/`blue` as
    // missing too. Spelling out equal R/G/B is the same color either way.
    private static let frostedGlass = UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 0.75)

    // MARK: - Aircraft: ~32 bricks, gear -> fuselage (2 bricks tall) -> wing panels -> tail -> nose reveal
    //
    // FIX ("just a bunch of cubes floating around" — the actual reported
    // shape, this build): the old version was a single-brick-wide spine
    // crossed with a single-brick-wide row of loose wing cubes — a thin
    // 3D "plus sign" skeleton with no bulk anywhere. Even with every
    // brick touching its neighbor (see the mesh-size fix in
    // BuildStudioView.spawnVoxel), a shape that's only ever one brick
    // thick in cross-section reads as a scattered line of blocks, not a
    // recognizable fuselage, because it has no width or depth of its
    // own to catch light on multiple sides at once.
    //
    // Two changes give it real volume without changing the unlock
    // mechanic (still just an ordered array — `unlockedCount` in
    // BuildStudioView doesn't care how many pieces there are):
    // 1. The fuselage is now two bricks tall (a lower body row added
    //    beneath the original spine) instead of one, so it reads as a
    //    solid tube instead of a wire.
    // 2. The outer wing sections are `.flatSlab` panels (the same mesh
    //    the car build already uses for its spoiler) instead of a row of
    //    individual cubes — a real flat wing shape, not five separate
    //    dots trailing off from the fuselage.
    // The old pedestal (a short stand directly under the fuselage) is
    // now proper landing gear one level further down, so it doesn't
    // collide with the new lower fuselage row occupying the space it
    // used to sit in.
    private static func flightVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.092) // brick pitch

        // Landing gear (4 bricks, charcoal, non-metallic) — dropped one
        // level below the fuselage body, since the old pedestal's spot
        // (y = 0) is now the lower fuselage row.
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), -u, Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Fuselage lower row (8 bricks, ivory, non-metallic) — NEW: gives
        // the body a second row of height so it reads as a boxy tube
        // instead of a single-file line.
        for i in -4...3 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        }

        // Fuselage upper row / spine (8 bricks, ivory, non-metallic)
        for i in -4...3 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), u, Float(i) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        }

        // Wing roots (2 bricks, indigo) bridging the fuselage to each
        // wing panel, plus the wing panels themselves (2 `.flatSlab`
        // pieces, indigo) — real flat wing shapes instead of a trailing
        // row of separate cubes.
        for side in [Float(1.0), Float(-1.0)] {
            units.append(VoxelUnit(position: Vector3(side * u, u, Float(0.0)), mesh: .cube, color: indigo, isMetallic: false, orientation: .identity))
            units.append(VoxelUnit(position: Vector3(side * u * Float(3.0), u, Float(0.0)), mesh: .flatSlab, color: indigo, isMetallic: false, orientation: .identity))
        }

        // Tail assembly (5 bricks)
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.0), Float(3.0) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(3.0), Float(3.0) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(-u, u * Float(2.0), Float(3.0) * u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(u, u * Float(2.0), Float(3.0) * u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(0.0), u, Float(4.0) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))

        // Turbine accents (2 bricks, charcoal cylinders under the wings)
        units.append(VoxelUnit(position: Vector3(Float(-2.0) * u, Float(0.0), u * Float(0.5)), mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))
        units.append(VoxelUnit(position: Vector3(Float(2.0) * u, Float(0.0), u * Float(0.5)), mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))

        // Nose cone — final reveal piece, glass + gold-lit
        units.append(VoxelUnit(position: Vector3(Float(0.0), u, Float(-5.0) * u), mesh: .cone, color: frostedGlass, isMetallic: false,
                                orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))

        return units
    }

    // MARK: - Car: ~21 bricks, chassis -> wheels -> body -> roof -> spoiler reveal
    private static func carVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.096)

        // Chassis (6 bricks, charcoal, non-metallic)
        for i in -3...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Wheels (4 bricks, charcoal cylinders at the corners)
        for x in [Float(-1.4), Float(1.4)] {
            for z in [Float(-2.0), Float(1.5)] {
                units.append(VoxelUnit(position: Vector3(x * u, -u * Float(0.4), z * u), mesh: .cylinder, color: charcoal, isMetallic: false,
                                        orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(0.0), Float(0.0), Float(1.0)))))
            }
        }

        // Body shell (6 bricks, crimson, non-metallic — the car's dominant color)
        for i in -2...3 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), u, Float(i) * u), mesh: .cube, color: crimson, isMetallic: false, orientation: .identity))
        }

        // Roof (3 bricks, ivory)
        for i in -1...1 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.0), Float(i) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        }

        // Side mirrors accent (2 bricks, gold, metallic)
        units.append(VoxelUnit(position: Vector3(Float(-1.3) * u, u * Float(1.6), u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.3) * u, u * Float(1.6), u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))

        // Spoiler — final reveal piece, gold, metallic
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.2), Float(3.0) * u), mesh: .flatSlab, color: trimColor, isMetallic: true, orientation: .identity))

        return units
    }

    // MARK: - Gaming Rig: ~20 bricks, desk -> tower -> RGB glow -> monitor/keyboard -> power button reveal
    private static func gamingRigVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Desk pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Tower body — vertical stack, offset to one side (5 bricks, indigo)
        for i in 0...4 {
            units.append(VoxelUnit(position: Vector3(Float(-2.0) * u, Float(i) * u, Float(0.0)), mesh: .cube, color: indigo, isMetallic: false, orientation: .identity))
        }

        // RGB glow strip up the tower's edge (4 bricks, crimson — reads
        // better as flat color here than metallic under this lighting rig)
        for i in 0...3 {
            units.append(VoxelUnit(position: Vector3(Float(-2.6) * u, Float(i) * u + u * Float(0.3), Float(0.0)), mesh: .cube, color: crimson, isMetallic: false, orientation: .identity))
        }

        // Monitor: stand + two-piece screen (3 bricks)
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, u * Float(0.5), Float(-1.0) * u), mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, u * Float(1.6), Float(-1.0) * u), mesh: .flatSlab, color: ivory, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, u * Float(2.1), Float(-1.0) * u), mesh: .flatSlab, color: ivory, isMetallic: false, orientation: .identity))

        // Keyboard (1 brick, low flat slab)
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, u * Float(0.15), Float(1.0) * u), mesh: .flatSlab, color: charcoal, isMetallic: false, orientation: .identity))

        // Tower top vents (2 bricks, charcoal)
        units.append(VoxelUnit(position: Vector3(Float(-2.0) * u, Float(5.0) * u, Float(-0.5) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(-2.0) * u, Float(5.0) * u, Float(0.5) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))

        // Power button — final reveal piece, glowing gold on top of the tower
        units.append(VoxelUnit(position: Vector3(Float(-2.0) * u, Float(5.6) * u, Float(0.0)), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))

        return units
    }

    // MARK: - Emergency Fund: ~18 bricks, base -> shield body -> trim -> lock -> point reveal
    private static func emergencyFundVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Shield body — widest at the shoulders, narrowing toward the
        // point (9 bricks, indigo)
        let shieldRows: [(y: Int, width: Int)] = [(1, 3), (2, 3), (3, 2), (4, 1)]
        for row in shieldRows {
            let half = row.width - 1
            for x in -half...half {
                units.append(VoxelUnit(position: Vector3(Float(x) * u, Float(row.y) * u, Float(0.0)), mesh: .cube, color: indigo, isMetallic: false, orientation: .identity))
            }
        }

        // Ivory trim along the shield's top edge (2 bricks)
        units.append(VoxelUnit(position: Vector3(Float(-1.0) * u, Float(1.0) * u, Float(0.6) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, Float(1.0) * u, Float(0.6) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))

        // Lock body + shackle, center-front (2 bricks)
        units.append(VoxelUnit(position: Vector3(Float(0.0), Float(2.0) * u, Float(0.7) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(0.0), Float(2.7) * u, Float(0.7) * u), mesh: .cylinder, color: trimColor, isMetallic: true,
                                orientation: VoxelOrientation(angle: Float.pi / Float(2.0), axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))

        // Final reveal — gold point at the shield's tip
        units.append(VoxelUnit(position: Vector3(Float(0.0), Float(4.0) * u, Float(0.0)), mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: VoxelOrientation(angle: Float.pi, axis: Vector3(Float(1.0), Float(0.0), Float(0.0)))))

        return units
    }

    // MARK: - Furniture: ~22 bricks, base -> legs -> tabletop -> trim -> centerpiece reveal.
    // For furniture/home-goods goals — a table, chair, desk, sofa, etc.
    private static func furnitureVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Four legs — upright cylinders at the corners (indigo)
        for x in [Float(-1.3), Float(1.3)] {
            for z in [Float(-1.3), Float(1.3)] {
                units.append(VoxelUnit(position: Vector3(x * u, u * Float(0.9), z * u), mesh: .cylinder, color: indigo, isMetallic: false, orientation: .identity))
            }
        }

        // Tabletop — wide flat slab spanning the legs, 3x3 (9 bricks, ivory)
        for x in -1...1 {
            for z in -1...1 {
                units.append(VoxelUnit(position: Vector3(Float(x) * u, u * Float(2.0), Float(z) * u), mesh: .flatSlab, color: ivory, isMetallic: false, orientation: .identity))
            }
        }

        // Edge trim along two sides (2 bricks, gold, metallic)
        units.append(VoxelUnit(position: Vector3(Float(-1.0) * u, u * Float(2.05), Float(0.0)), mesh: .flatSlab, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, u * Float(2.05), Float(0.0)), mesh: .flatSlab, color: trimColor, isMetallic: true, orientation: .identity))

        // Centerpiece — final reveal piece, gold, set on top
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.35), Float(0.0)), mesh: .cone, color: trimColor, isMetallic: true, orientation: .identity))

        return units
    }

    // MARK: - House: ~22 bricks, base -> walls -> roof -> door/windows -> weathervane reveal.
    // For home down payments, house, or apartment goals.
    private static func houseVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Walls — 3x3 footprint, 2 layers tall (9 bricks, ivory)
        for x in -1...1 {
            for z in -1...1 {
                units.append(VoxelUnit(position: Vector3(Float(x) * u, u, Float(z) * u), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))
            }
        }

        // Roof — three cones narrowing toward the peak (crimson)
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.6), Float(0.0)), mesh: .cone, color: crimson, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(-0.7) * u, u * Float(2.3), Float(0.0)), mesh: .cone, color: crimson, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(0.7) * u, u * Float(2.3), Float(0.0)), mesh: .cone, color: crimson, isMetallic: false, orientation: .identity))

        // Door (charcoal) + windows (indigo)
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(0.6), Float(1.05) * u), mesh: .flatSlab, color: charcoal, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(-1.05) * u, u * Float(1.5), Float(0.0)), mesh: .flatSlab, color: indigo, isMetallic: false, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.05) * u, u * Float(1.5), Float(0.0)), mesh: .flatSlab, color: indigo, isMetallic: false, orientation: .identity))

        // Chimney (charcoal)
        units.append(VoxelUnit(position: Vector3(Float(0.9) * u, u * Float(2.2), Float(-0.9) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))

        // Weathervane — final reveal piece, gold, at the roof peak
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(3.0), Float(0.0)), mesh: .cone, color: trimColor, isMetallic: true, orientation: .identity))

        return units
    }

    // MARK: - Jewelry: ~13 bricks, base -> ring band -> prong -> gem reveal.
    // For a ring, wedding/engagement fund, watch, or other jewelry.
    private static func jewelryVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Ring band — cubes arranged in a circle (gold, metallic).
        // Precomputed (cos, sin) pairs for 10 points evenly spaced around
        // the circle (36° apart), rather than calling cos()/sin() at
        // runtime: Skip's transpiler still can't disambiguate those calls
        // even when fed an explicit Double (see the cascade this caused
        // across the whole file), so the values are just baked in here.
        let bandRadius = Float(1.4)
        let bandOffsets: [(cos: Float, sin: Float)] = [
            (Float(1.0), Float(0.0)),
            (Float(0.809017), Float(0.587785)),
            (Float(0.309017), Float(0.951057)),
            (Float(-0.309017), Float(0.951057)),
            (Float(-0.809017), Float(0.587785)),
            (Float(-1.0), Float(0.0)),
            (Float(-0.809017), Float(-0.587785)),
            (Float(-0.309017), Float(-0.951057)),
            (Float(0.309017), Float(-0.951057)),
            (Float(0.809017), Float(-0.587785))
        ]
        for offset in bandOffsets {
            let x = offset.cos * bandRadius * u
            let z = offset.sin * bandRadius * u
            units.append(VoxelUnit(position: Vector3(x, u * Float(1.4), z), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))
        }

        // Prong setting (ivory)
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(1.9), Float(0.0)), mesh: .cube, color: ivory, isMetallic: false, orientation: .identity))

        // Gem — final reveal piece, frosted glass, catching the light
        units.append(VoxelUnit(position: Vector3(Float(0.0), u * Float(2.3), Float(0.0)), mesh: .cone, color: frostedGlass, isMetallic: false, orientation: .identity))

        return units
    }

    // MARK: - Gift (generic fallback): ~22 bricks, base -> box -> ribbon -> bow reveal.
    // Used only for custom goals that don't fit any category above — a
    // wrapped present reads as "something you're saving up for" without
    // implying a specific item.
    private static func giftVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u = Float(0.09)

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: Vector3(Float(0.0), Float(0.0), Float(i) * u), mesh: .cube, color: charcoal, isMetallic: false, orientation: .identity))
        }

        // Box body — 3x2 footprint, 2 layers tall (12 bricks, crimson)
        for x in -1...1 {
            for z in -1...0 {
                units.append(VoxelUnit(position: Vector3(Float(x) * u, u, Float(z) * u), mesh: .cube, color: crimson, isMetallic: false, orientation: .identity))
                units.append(VoxelUnit(position: Vector3(Float(x) * u, Float(2.0) * u, Float(z) * u), mesh: .cube, color: crimson, isMetallic: false, orientation: .identity))
            }
        }

        // Ribbon — gold cross-strap over the top and down both sides (4 bricks)
        units.append(VoxelUnit(position: Vector3(Float(0.0), Float(2.0) * u, Float(-1.0) * u), mesh: .flatSlab, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(0.0), Float(2.0) * u, Float(0.0)), mesh: .flatSlab, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(-1.0) * u, Float(1.5) * u, Float(-0.5) * u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))
        units.append(VoxelUnit(position: Vector3(Float(1.0) * u, Float(1.5) * u, Float(-0.5) * u), mesh: .cube, color: trimColor, isMetallic: true, orientation: .identity))

        // Bow — two angled cones on top, final reveal piece (2 bricks)
        units.append(VoxelUnit(position: Vector3(Float(-0.4) * u, Float(2.6) * u, Float(-0.5) * u), mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: VoxelOrientation(angle: Float.pi * Float(0.15), axis: Vector3(Float(0.0), Float(0.0), Float(1.0)))))
        units.append(VoxelUnit(position: Vector3(Float(0.4) * u, Float(2.6) * u, Float(-0.5) * u), mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: VoxelOrientation(angle: -Float.pi * Float(0.15), axis: Vector3(Float(0.0), Float(0.0), Float(1.0)))))

        return units
    }
}
