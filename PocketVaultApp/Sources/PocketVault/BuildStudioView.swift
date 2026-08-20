import SwiftUI
#if !SKIP
import RealityKit
#endif

struct BuildStudioView: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var goalTitle: String
    @Binding var goalKindRaw: String
    @Binding var currentSavings: Double
    @Binding var targetGoal: Double
    // JSON blueprint for an AI-generated custom sculpture (see
    // Goal.customVoxelBlueprintJSON) — when present, this exact shape is
    // used instead of goalKind's static build, so a goal like "cat food"
    // actually looks like cat food instead of the generic gift box.
    @Binding var customVoxelBlueprint: String?

    // Explicitly cast to Float so Skip/Kotlin doesn't interpret 0.0 as a Double
    @State private var rotationY: Float = Float(0.0)
    @State private var lastDragTranslation: CGFloat = 0.0
    @State private var lastUnlockedCount: Int = 0

    private var goalKind: GoalKind { GoalKind(rawValue: goalKindRaw) ?? .flight }

    // FIX: Apple's UIKit ships a special `UIColor(Color)` bridging
    // initializer (SwiftUI -> UIKit) that Skip's Android `UIColor`
    // compatibility shim does not implement — the shim only provides the
    // plain component initializers (e.g. `UIColor(white:alpha:)`, used
    // further down for the base/light entities, which is why those calls
    // aren't flagged). Calling `UIColor(theme.accent)` therefore gets
    // matched against `UIColor(red:green:blue:alpha:)` with only one
    // positional argument, producing "actual type is 'Color', but
    // 'Double' was expected" plus "No value passed for parameter
    // 'green'/'blue'/'alpha'".
    //
    // The follow-up attempt — resolving the `Color` into RGBA via
    // `Color.resolve(in:)` and building the `UIColor` from that — hits
    // the same wall one call earlier: that API isn't implemented by Skip
    // on Android either ("This API is not yet available in Skip"). There
    // is no way to introspect a `Color`'s components on both platforms.
    //
    // So don't: take the RGB `theme.accent` was built from in the first
    // place. `ThemeManager.accentRGB` (see ThemeManager.swift) exposes
    // exactly those numbers, already resolved for light/dark — no
    // `Color`/`UIColor` bridging involved at all.
    private func trimUIColor(from components: (r: Double, g: Double, b: Double)) -> UIColor {
        UIColor(red: components.r, green: components.g, blue: components.b, alpha: 1.0)
    }

    // FIX: `voxels` used to be a computed property, which meant every
    // single read rebuilt the whole piece list from scratch — for a
    // custom AI-generated goal that includes a full JSONDecoder pass
    // every time. It's read from several places in this same view
    // (unlockedCount, isComplete, the piece-count text, the Android 2D
    // stand-in's ForEach), and unlockedCount itself reads voxels too, so
    // inside voxelStandIn2D's ForEach the whole array was being rebuilt
    // once PER PIECE, on every body re-render. Dragging to rotate the
    // sculpture changes rotationY, which re-renders the body dozens of
    // times a second — none of which actually changes the sculpture's
    // shape — so this was redoing that full rebuild (JSON decode
    // included) far more than needed, laggy on iOS and enough of a
    // main-thread backlog to trip Android's ANR watchdog.
    //
    // Cache it instead: only recompute when something that actually
    // changes the shape changes (goal kind, blueprint, or trim color),
    // not on every re-render.
    @State private var cachedVoxels: [VoxelUnit] = []

    private func recomputeVoxels() {
        let trimColor = trimUIColor(from: theme.accentRGB)
        if let blueprint = customVoxelBlueprint, !blueprint.isEmpty {
            cachedVoxels = GoalBuildLibrary.customVoxels(fromBlueprintJSON: blueprint, trimColor: trimColor)
        } else {
            cachedVoxels = GoalBuildLibrary.voxels(for: goalKind, trimColor: trimColor)
        }
    }

    // FIX: nested `min(max(...))` over Doubles is the same generic-
    // overload pattern that broke AmountScrubPicker, BudgetTrackerView,
    // and TransactionRow — Skip's Kotlin codegen can't resolve the
    // overload and reports it as an argument type mismatch / "Number &
    // Comparable<CapturedType(*)>". Clamp with plain comparisons instead.
    private var progressRatio: Double {
        let safeTarget = targetGoal > 1.0 ? targetGoal : 1.0
        let raw = currentSavings / safeTarget
        if raw < 0.0 { return 0.0 }
        if raw > 1.0 { return 1.0 }
        return raw
    }

    // Goal-Gradient Effect: the moment a goal exists, the first brick is
    // already placed — a real, visible "step 1" credit (like the 2
    // pre-stamped punches on a coffee card), not a faked dollar figure.
    // Nothing here pretends any money has been saved; it's purely "you
    // started" momentum.
    private var unlockedCount: Int {
        let earned = Int((progressRatio * Double(cachedVoxels.count)).rounded(.down))
        return min(cachedVoxels.count, max(earned, 1))
    }

    private var isComplete: Bool { unlockedCount >= cachedVoxels.count }

    var body: some View {
        ZStack {
            sculptureView

            VStack {
                VStack(spacing: 4) {
                    Text("BUILD STUDIO")
                        .font(theme.font(10, weight: .bold))
                        .tracking(3)
                        .foregroundStyle(theme.accent)

                    Text(goalTitle.isEmpty ? "MODEL STAGE" : goalTitle.uppercased())
                        .font(theme.font(14, weight: .light))
                        .foregroundStyle(.primary.opacity(0.8))

                    Text(currentSavings > 0.0
                        ? "\(unlockedCount) OF \(cachedVoxels.count) PIECES PLACED"
                        : "1 OF \(cachedVoxels.count) PIECES PLACED · STARTER PIECE")
                        .font(theme.font(9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary) // was .tertiary — unsupported by Skip
                        .padding(.top, 2)
                }
                .padding(.top, 60)

                Spacer()

                // Reveals once the sculpture finishes — names what was
                // actually built, so the payoff of finishing isn't just
                // an abstract voxel shape with no label.
                if isComplete {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image.platformSymbol("checkmark.seal.fill", android: "checkmark.circle.fill")
                            Text("SCULPTURE COMPLETE")
                        }
                        .font(theme.font(10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.accent)

                        Text(completedModelName)
                            .font(theme.font(16, weight: .light))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    // NOTE(skip): .ultraThinMaterial has no Android/Compose
                    // equivalent and was unresolved, cascading into the
                    // .clipShape right below it.
                    .background(theme.isLight ? Color.white.opacity(0.7) : Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.4), lineWidth: 1))
                    .padding(.bottom, 110)
                }
            }
        }
        .themedSurface(ignoresSafeArea: true)
        .onChange(of: currentSavings) { newValue in
            if unlockedCount > lastUnlockedCount {
                #if !SKIP
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                #endif
            }
            lastUnlockedCount = unlockedCount
        }
        .onChange(of: goalKindRaw) { _ in recomputeVoxels() }
        .onChange(of: customVoxelBlueprint) { _ in recomputeVoxels() }
        .onChange(of: theme.accent) { _ in recomputeVoxels() }
        .onAppear {
            recomputeVoxels()
            lastUnlockedCount = unlockedCount
        }
    }

    /// What the completion card names as the model — based on the build
    /// style (goalKind), not the user's own goal title, since those are
    /// two different things (a goal named "Save for concert tickets"
    /// still visually builds a plane, a gift box, etc., not a "concert").
    private var completedModelName: String {
        if let blueprint = customVoxelBlueprint, !blueprint.isEmpty {
            return "YOUR \(goalTitle.isEmpty ? "CREATION" : goalTitle.uppercased())"
        }
        switch goalKind {
        case .flight: return "YOUR PLANE"
        case .car: return "YOUR CAR"
        case .gamingRig: return "YOUR GAMING RIG"
        case .emergencyFund: return "YOUR SAFETY NET"
        case .furniture: return "YOUR FURNITURE"
        case .house: return "YOUR HOUSE"
        case .jewelry: return "YOUR JEWELRY"
        case .custom: return "YOUR GIFT"
        }
    }

    @ViewBuilder
    private var sculptureView: some View {
        #if !SKIP
        if #available(iOS 18.0, *) {
            RealityView { content in
                let baseMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.6)
                let baseMat = SimpleMaterial(color: UIColor(white: 0.16, alpha: 1.0), isMetallic: false)
                let baseEntity = ModelEntity(mesh: baseMesh, materials: [baseMat])
                baseEntity.position = [0, -0.2, -0.85]
                baseEntity.name = "assemblyBase"
                content.add(baseEntity)

                // Key light — without this, materials (especially metallic ones)
                // render close to black regardless of the color assigned.
                let keyLight = Entity()
                keyLight.components.set(DirectionalLightComponent(color: UIColor.white, intensity: 4000))
                keyLight.look(at: [0, -0.3, -1.3], from: [0.6, 0.7, -0.3], relativeTo: nil)
                content.add(keyLight)

                // Soft fill light so the shadowed side of the sculpture isn't pure black.
                let fillLight = Entity()
                fillLight.components.set(PointLightComponent(color: UIColor.white, intensity: 3500, attenuationRadius: 4))
                fillLight.position = [-0.5, 0.2, -0.8]
                content.add(fillLight)
            } update: { content in
                guard let baseEntity = content.entities.first(where: { $0.name == "assemblyBase" }) else { return }
                baseEntity.orientation = simd_quatf(angle: rotationY, axis: [0, 1, 0])

                let unlocked = unlockedCount
                for (index, unit) in cachedVoxels.enumerated() where index < unlocked {
                    spawnVoxel(index: index, unit: unit, on: baseEntity)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Explicitly cast to Float so Skip doesn't complain about matching types
                        let delta = Float(value.translation.width - lastDragTranslation) * Float(0.006)
                        rotationY += delta
                        lastDragTranslation = value.translation.width
                    }
                    .onEnded { _ in lastDragTranslation = 0 }
            )
        } else {
            // Fallback for earlier iOS versions
            EmptyView()
        }
        #else
        // Android fallback: RealityKit itself doesn't exist under Skip
        // (this used to just be an EmptyView(), which is why Build
        // Studio looked completely blank on Android). This renders a
        // flat, isometric-style stand-in built from the exact same
        // `voxels` data the iOS 3D view consumes — same piece count,
        // same colors, same unlock progression, same drag-to-rotate
        // feel — using only plain SwiftUI shapes, which is the closest
        // Android can get without a 3D engine.
        voxelStandIn2D
        #endif
    }

    #if SKIP
    /// Simple isometric-style projection of a voxel's 3D position onto
    /// the 2D canvas: x and z both contribute to the horizontal axis (z
    /// also nudges vertically for a sense of depth), y is height.
    private func projectedVoxelPoint(_ p: Vector3, center: CGPoint) -> CGPoint {
        let scale: CGFloat = 300.0
        let x = CGFloat(p.x) * scale
        let y = CGFloat(p.y) * scale
        let z = CGFloat(p.z) * scale
        return CGPoint(x: center.x + x + (z * 0.4), y: center.y - y - (z * 0.25))
    }

    @ViewBuilder
    private func voxelChip(_ unit: VoxelUnit) -> some View {
        let isRound = unit.mesh == .cylinder || unit.mesh == .cone
        let size: CGFloat = unit.mesh == .flatSlab ? 26.0 : 16.0
        let height: CGFloat = unit.mesh == .flatSlab ? 8.0 : size
        Group {
            if isRound {
                Circle().fill(Color(unit.color))
            } else {
                RoundedRectangle(cornerRadius: 3.0).fill(Color(unit.color))
            }
        }
        .frame(width: size, height: height)
        .shadow(color: Color.black.opacity(0.3), radius: 2.0, y: 1.0)
    }

    private var voxelStandIn2D: some View {
        let unlocked = unlockedCount
        return GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2.0, y: geo.size.height * 0.62)
            ZStack {
                // Base platform, matching the iOS cylinder base.
                Ellipse()
                    .fill(Color(white: 0.16))
                    .frame(width: 170.0, height: 46.0)
                    .position(x: center.x, y: center.y + 34.0)

                ForEach(Array(cachedVoxels.enumerated()), id: \.offset) { index, unit in
                    if index < unlocked {
                        voxelChip(unit)
                            .position(projectedVoxelPoint(unit.position, center: center))
                    }
                }
            }
            .rotation3DEffect(.degrees(Double(rotationY) * 6.0), axis: (x: 0.0, y: 1.0, z: 0.0))
        }
        .frame(height: 260.0)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let delta = Float(value.translation.width - lastDragTranslation) * Float(0.02)
                    rotationY += delta
                    lastDragTranslation = value.translation.width
                }
                .onEnded { _ in lastDragTranslation = 0 }
        )
    }
    #endif

    // Keep the entire RealityKit function hidden from Android and gated by iOS 18
    #if !SKIP
    @available(iOS 18.0, *)
    private func spawnVoxel(index: Int, unit: VoxelUnit, on base: Entity) {
        let position = SIMD3<Float>(unit.position.x, unit.position.y, unit.position.z)
        let axis = SIMD3<Float>(unit.orientation.axis.x, unit.orientation.axis.y, unit.orientation.axis.z)
        let name = "voxel_\(index)"
        guard base.findEntity(named: name) == nil else { return }

        let mesh: MeshResource
        switch unit.mesh {
        case .cube:
            mesh = .generateBox(size: 0.08, cornerRadius: 0.012)
        case .cylinder:
            mesh = .generateCylinder(height: 0.08, radius: 0.038)
        case .cone:
            mesh = .generateCone(height: 0.17, radius: 0.07)
        case .flatSlab:
            mesh = .generateBox(size: [0.25, 0.018, 0.07], cornerRadius: 0.006)
        }

        let material = SimpleMaterial(color: unit.color, isMetallic: unit.isMetallic)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.orientation = simd_quatf(angle: unit.orientation.angle, axis: axis)

        entity.position = position + SIMD3<Float>(0, 0.3, 0)
        entity.scale = [0.15, 0.15, 0.15]
        base.addChild(entity)

        var finalTransform = entity.transform
        finalTransform.translation = position
        finalTransform.scale = [1, 1, 1]

        entity.move(to: finalTransform, relativeTo: base, duration: 0.5, timingFunction: .easeOut)
    }
    #endif // !SKIP
}
