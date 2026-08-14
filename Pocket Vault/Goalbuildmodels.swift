import SwiftUI
import RealityKit

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

private extension UIColor {
    /// Parses a "#RRGGBB" or "RRGGBB" hex string. Fails (rather than
    /// silently defaulting to black) so the caller can drop a part with
    /// a malformed color instead of rendering it wrong.
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

struct VoxelUnit {
    let position: SIMD3<Float>
    let mesh: VoxelMeshKind
    let color: UIColor
    let isMetallic: Bool
    var orientation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
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
                abs(part.x) <= bound, part.y >= -0.05, part.y <= bound, abs(part.z) <= bound,
                let mesh = VoxelMeshKind(aiString: part.mesh),
                let color = UIColor(hex: part.color)
            else {
                continue
            }
            units.append(VoxelUnit(
                position: [Float(part.x), Float(part.y), Float(part.z)],
                mesh: mesh,
                color: color,
                isMetallic: part.metallic
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
    private static let frostedGlass = UIColor(white: 0.97, alpha: 0.75)

    // MARK: - Aircraft: ~27 bricks, base -> fuselage -> wings -> tail -> nose reveal
    private static func flightVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.092 // brick pitch

        // Pedestal base (4 bricks, charcoal, non-metallic)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Fuselage spine (8 bricks, ivory, non-metallic)
        for i in -4...3 {
            units.append(VoxelUnit(position: [0, u, Float(i) * u], mesh: .cube, color: ivory, isMetallic: false))
        }

        // Wings, symmetric, built outward (8 bricks, indigo, non-metallic)
        for i in [1, -1, 2, -2, 3, -3, 4, -4] {
            units.append(VoxelUnit(position: [Float(i) * u, u, 0], mesh: .cube, color: indigo, isMetallic: false))
        }

        // Tail assembly (5 bricks)
        units.append(VoxelUnit(position: [0, u * 2, 3 * u], mesh: .cube, color: ivory, isMetallic: false))
        units.append(VoxelUnit(position: [0, u * 3, 3 * u], mesh: .cube, color: ivory, isMetallic: false))
        units.append(VoxelUnit(position: [-u, u * 2, 3 * u], mesh: .cube, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [u, u * 2, 3 * u], mesh: .cube, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [0, u, 4 * u], mesh: .cube, color: charcoal, isMetallic: false))

        // Turbine accents (2 bricks, charcoal cylinders under the wings)
        units.append(VoxelUnit(position: [-2 * u, 0, u * 0.5], mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
        units.append(VoxelUnit(position: [2 * u, 0, u * 0.5], mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))

        // Nose cone — final reveal piece, glass + gold-lit
        units.append(VoxelUnit(position: [0, u, -5 * u], mesh: .cone, color: frostedGlass, isMetallic: false,
                                orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))

        return units
    }

    // MARK: - Car: ~21 bricks, chassis -> wheels -> body -> roof -> spoiler reveal
    private static func carVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.096

        // Chassis (6 bricks, charcoal, non-metallic)
        for i in -3...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Wheels (4 bricks, charcoal cylinders at the corners)
        for x in [-1.4, 1.4] as [Float] {
            for z in [-2.0, 1.5] as [Float] {
                units.append(VoxelUnit(position: [x * u, -u * 0.4, z * u], mesh: .cylinder, color: charcoal, isMetallic: false,
                                        orientation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1])))
            }
        }

        // Body shell (6 bricks, crimson, non-metallic — the car's dominant color)
        for i in -2...3 {
            units.append(VoxelUnit(position: [0, u, Float(i) * u], mesh: .cube, color: crimson, isMetallic: false))
        }

        // Roof (3 bricks, ivory)
        for i in -1...1 {
            units.append(VoxelUnit(position: [0, u * 2, Float(i) * u], mesh: .cube, color: ivory, isMetallic: false))
        }

        // Side mirrors accent (2 bricks, gold, metallic)
        units.append(VoxelUnit(position: [-1.3 * u, u * 1.6, u], mesh: .cube, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [1.3 * u, u * 1.6, u], mesh: .cube, color: trimColor, isMetallic: true))

        // Spoiler — final reveal piece, gold, metallic
        units.append(VoxelUnit(position: [0, u * 2.2, 3 * u], mesh: .flatSlab, color: trimColor, isMetallic: true))

        return units
    }

    // MARK: - Gaming Rig: ~20 bricks, desk -> tower -> RGB glow -> monitor/keyboard -> power button reveal
    private static func gamingRigVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Desk pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Tower body — vertical stack, offset to one side (5 bricks, indigo)
        for i in 0...4 {
            units.append(VoxelUnit(position: [-2 * u, Float(i) * u, 0], mesh: .cube, color: indigo, isMetallic: false))
        }

        // RGB glow strip up the tower's edge (4 bricks, crimson — reads
        // better as flat color here than metallic under this lighting rig)
        for i in 0...3 {
            units.append(VoxelUnit(position: [-2.6 * u, Float(i) * u + u * 0.3, 0], mesh: .cube, color: crimson, isMetallic: false))
        }

        // Monitor: stand + two-piece screen (3 bricks)
        units.append(VoxelUnit(position: [1 * u, u * 0.5, -1 * u], mesh: .cylinder, color: charcoal, isMetallic: false,
                                orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
        units.append(VoxelUnit(position: [1 * u, u * 1.6, -1 * u], mesh: .flatSlab, color: ivory, isMetallic: false))
        units.append(VoxelUnit(position: [1 * u, u * 2.1, -1 * u], mesh: .flatSlab, color: ivory, isMetallic: false))

        // Keyboard (1 brick, low flat slab)
        units.append(VoxelUnit(position: [1 * u, u * 0.15, 1 * u], mesh: .flatSlab, color: charcoal, isMetallic: false))

        // Tower top vents (2 bricks, charcoal)
        units.append(VoxelUnit(position: [-2 * u, 5 * u, -0.5 * u], mesh: .cube, color: charcoal, isMetallic: false))
        units.append(VoxelUnit(position: [-2 * u, 5 * u, 0.5 * u], mesh: .cube, color: charcoal, isMetallic: false))

        // Power button — final reveal piece, glowing gold on top of the tower
        units.append(VoxelUnit(position: [-2 * u, 5.6 * u, 0], mesh: .cube, color: trimColor, isMetallic: true))

        return units
    }

    // MARK: - Emergency Fund: ~18 bricks, base -> shield body -> trim -> lock -> point reveal
    private static func emergencyFundVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Shield body — widest at the shoulders, narrowing toward the
        // point (9 bricks, indigo)
        let shieldRows: [(y: Int, width: Int)] = [(1, 3), (2, 3), (3, 2), (4, 1)]
        for row in shieldRows {
            let half = row.width - 1
            for x in -half...half {
                units.append(VoxelUnit(position: [Float(x) * u, Float(row.y) * u, 0], mesh: .cube, color: indigo, isMetallic: false))
            }
        }

        // Ivory trim along the shield's top edge (2 bricks)
        units.append(VoxelUnit(position: [-1 * u, 1 * u, 0.6 * u], mesh: .cube, color: ivory, isMetallic: false))
        units.append(VoxelUnit(position: [1 * u, 1 * u, 0.6 * u], mesh: .cube, color: ivory, isMetallic: false))

        // Lock body + shackle, center-front (2 bricks)
        units.append(VoxelUnit(position: [0, 2 * u, 0.7 * u], mesh: .cube, color: charcoal, isMetallic: false))
        units.append(VoxelUnit(position: [0, 2.7 * u, 0.7 * u], mesh: .cylinder, color: trimColor, isMetallic: true,
                                orientation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))

        // Final reveal — gold point at the shield's tip
        units.append(VoxelUnit(position: [0, 4 * u, 0], mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: simd_quatf(angle: .pi, axis: [1, 0, 0])))

        return units
    }

    // MARK: - Furniture: ~22 bricks, base -> legs -> tabletop -> trim -> centerpiece reveal.
    // For furniture/home-goods goals — a table, chair, desk, sofa, etc.
    private static func furnitureVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Four legs — upright cylinders at the corners (indigo)
        for x in [-1.3, 1.3] as [Float] {
            for z in [-1.3, 1.3] as [Float] {
                units.append(VoxelUnit(position: [x * u, u * 0.9, z * u], mesh: .cylinder, color: indigo, isMetallic: false))
            }
        }

        // Tabletop — wide flat slab spanning the legs, 3x3 (9 bricks, ivory)
        for x in -1...1 {
            for z in -1...1 {
                units.append(VoxelUnit(position: [Float(x) * u, u * 2, Float(z) * u], mesh: .flatSlab, color: ivory, isMetallic: false))
            }
        }

        // Edge trim along two sides (2 bricks, gold, metallic)
        units.append(VoxelUnit(position: [-1 * u, u * 2.05, 0], mesh: .flatSlab, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [1 * u, u * 2.05, 0], mesh: .flatSlab, color: trimColor, isMetallic: true))

        // Centerpiece — final reveal piece, gold, set on top
        units.append(VoxelUnit(position: [0, u * 2.35, 0], mesh: .cone, color: trimColor, isMetallic: true))

        return units
    }

    // MARK: - House: ~22 bricks, base -> walls -> roof -> door/windows -> weathervane reveal.
    // For home down payments, house, or apartment goals.
    private static func houseVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Walls — 3x3 footprint, 2 layers tall (9 bricks, ivory)
        for x in -1...1 {
            for z in -1...1 {
                units.append(VoxelUnit(position: [Float(x) * u, u, Float(z) * u], mesh: .cube, color: ivory, isMetallic: false))
            }
        }

        // Roof — three cones narrowing toward the peak (crimson)
        units.append(VoxelUnit(position: [0, u * 2.6, 0], mesh: .cone, color: crimson, isMetallic: false))
        units.append(VoxelUnit(position: [-0.7 * u, u * 2.3, 0], mesh: .cone, color: crimson, isMetallic: false))
        units.append(VoxelUnit(position: [0.7 * u, u * 2.3, 0], mesh: .cone, color: crimson, isMetallic: false))

        // Door (charcoal) + windows (indigo)
        units.append(VoxelUnit(position: [0, u * 0.6, 1.05 * u], mesh: .flatSlab, color: charcoal, isMetallic: false))
        units.append(VoxelUnit(position: [-1.05 * u, u * 1.5, 0], mesh: .flatSlab, color: indigo, isMetallic: false))
        units.append(VoxelUnit(position: [1.05 * u, u * 1.5, 0], mesh: .flatSlab, color: indigo, isMetallic: false))

        // Chimney (charcoal)
        units.append(VoxelUnit(position: [0.9 * u, u * 2.2, -0.9 * u], mesh: .cube, color: charcoal, isMetallic: false))

        // Weathervane — final reveal piece, gold, at the roof peak
        units.append(VoxelUnit(position: [0, u * 3, 0], mesh: .cone, color: trimColor, isMetallic: true))

        return units
    }

    // MARK: - Jewelry: ~13 bricks, base -> ring band -> prong -> gem reveal.
    // For a ring, wedding/engagement fund, watch, or other jewelry.
    private static func jewelryVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Ring band — cubes arranged in a circle (gold, metallic)
        let bandRadius: Float = 1.4
        let bandPoints = 10
        for i in 0..<bandPoints {
            let angle = Float(i) / Float(bandPoints) * 2 * Float.pi
            let x = cos(angle) * bandRadius * u
            let z = sin(angle) * bandRadius * u
            units.append(VoxelUnit(position: [x, u * 1.4, z], mesh: .cube, color: trimColor, isMetallic: true))
        }

        // Prong setting (ivory)
        units.append(VoxelUnit(position: [0, u * 1.9, 0], mesh: .cube, color: ivory, isMetallic: false))

        // Gem — final reveal piece, frosted glass, catching the light
        units.append(VoxelUnit(position: [0, u * 2.3, 0], mesh: .cone, color: frostedGlass, isMetallic: false))

        return units
    }

    // MARK: - Gift (generic fallback): ~22 bricks, base -> box -> ribbon -> bow reveal.
    // Used only for custom goals that don't fit any category above — a
    // wrapped present reads as "something you're saving up for" without
    // implying a specific item.
    private static func giftVoxels(trimColor: UIColor) -> [VoxelUnit] {
        var units: [VoxelUnit] = []
        let u: Float = 0.09

        // Base pedestal (4 bricks, charcoal)
        for i in -1...2 {
            units.append(VoxelUnit(position: [0, 0, Float(i) * u], mesh: .cube, color: charcoal, isMetallic: false))
        }

        // Box body — 3x2 footprint, 2 layers tall (12 bricks, crimson)
        for x in -1...1 {
            for z in -1...0 {
                units.append(VoxelUnit(position: [Float(x) * u, u, Float(z) * u], mesh: .cube, color: crimson, isMetallic: false))
                units.append(VoxelUnit(position: [Float(x) * u, 2 * u, Float(z) * u], mesh: .cube, color: crimson, isMetallic: false))
            }
        }

        // Ribbon — gold cross-strap over the top and down both sides (4 bricks)
        units.append(VoxelUnit(position: [0, 2 * u, -1 * u], mesh: .flatSlab, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [0, 2 * u, 0], mesh: .flatSlab, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [-1 * u, 1.5 * u, -0.5 * u], mesh: .cube, color: trimColor, isMetallic: true))
        units.append(VoxelUnit(position: [1 * u, 1.5 * u, -0.5 * u], mesh: .cube, color: trimColor, isMetallic: true))

        // Bow — two angled cones on top, final reveal piece (2 bricks)
        units.append(VoxelUnit(position: [-0.4 * u, 2.6 * u, -0.5 * u], mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: simd_quatf(angle: .pi * 0.15, axis: [0, 0, 1])))
        units.append(VoxelUnit(position: [0.4 * u, 2.6 * u, -0.5 * u], mesh: .cone, color: trimColor, isMetallic: true,
                                orientation: simd_quatf(angle: -.pi * 0.15, axis: [0, 0, 1])))

        return units
    }
}
