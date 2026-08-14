import SwiftUI
import RealityKit

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

    @State private var rotationY: Float = 0.0
    @State private var lastDragTranslation: CGFloat = 0.0
    @State private var lastUnlockedCount: Int = 0

    private var goalKind: GoalKind { GoalKind(rawValue: goalKindRaw) ?? .flight }
    // The 3D build's trim/accent pieces (gold bow ribbon, spoiler, lock
    // shackle, etc.) now follow whichever accent color the user picked in
    // Appearance instead of always rendering champagne gold — same accent
    // driving every 2D screen also drives the trim color here.
    private var voxels: [VoxelUnit] {
        if let blueprint = customVoxelBlueprint, !blueprint.isEmpty {
            return GoalBuildLibrary.customVoxels(fromBlueprintJSON: blueprint, trimColor: UIColor(theme.accent))
        }
        return GoalBuildLibrary.voxels(for: goalKind, trimColor: UIColor(theme.accent))
    }

    private var progressRatio: Double {
        min(max(currentSavings / max(targetGoal, 1.0), 0.0), 1.0)
    }

    // Goal-Gradient Effect: the moment a goal exists, the first brick is
    // already placed — a real, visible "step 1" credit (like the 2
    // pre-stamped punches on a coffee card), not a faked dollar figure.
    // Nothing here pretends any money has been saved; it's purely "you
    // started" momentum.
    private var unlockedCount: Int {
        let earned = Int((progressRatio * Double(voxels.count)).rounded(.down))
        return min(voxels.count, max(earned, 1))
    }

    private var isComplete: Bool { unlockedCount >= voxels.count }

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

                    Text(currentSavings > 0
                         ? "\(unlockedCount) OF \(voxels.count) PIECES PLACED"
                         : "1 OF \(voxels.count) PIECES PLACED · STARTER PIECE")
                        .font(theme.font(9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.tertiary)
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
                            Image(systemName: "checkmark.seal.fill")
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
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.4), lineWidth: 1))
                    .padding(.bottom, 110)
                }
            }
        }
        .themedSurface(theme)
        .onChange(of: currentSavings) { _, _ in
            if unlockedCount > lastUnlockedCount {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            lastUnlockedCount = unlockedCount
        }
        .onAppear {
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

    private var sculptureView: some View {
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
            keyLight.components.set(DirectionalLightComponent(color: .white, intensity: 4000))
            keyLight.look(at: [0, -0.3, -1.3], from: [0.6, 0.7, -0.3], relativeTo: nil)
            content.add(keyLight)

            // Soft fill light so the shadowed side of the sculpture isn't pure black.
            let fillLight = Entity()
            fillLight.components.set(PointLightComponent(color: .white, intensity: 3500, attenuationRadius: 4))
            fillLight.position = [-0.5, 0.2, -0.8]
            content.add(fillLight)
        } update: { content in
            guard let baseEntity = content.entities.first(where: { $0.name == "assemblyBase" }) else { return }
            baseEntity.orientation = simd_quatf(angle: rotationY, axis: [0, 1, 0])

            for (index, unit) in voxels.enumerated() where index < unlockedCount {
                spawnVoxel(index: index, unit: unit, on: baseEntity)
            }
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture()
                .onChanged { value in
                    let delta = Float(value.translation.width - lastDragTranslation) * 0.006
                    rotationY += delta
                    lastDragTranslation = value.translation.width
                }
                .onEnded { _ in lastDragTranslation = 0 }
        )
    }

    private func spawnVoxel(index: Int, unit: VoxelUnit, on base: Entity) {
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
        entity.orientation = unit.orientation

        entity.position = unit.position + SIMD3<Float>(0, 0.3, 0)
        entity.scale = [0.15, 0.15, 0.15]
        base.addChild(entity)

        var finalTransform = entity.transform
        finalTransform.translation = unit.position
        finalTransform.scale = [1, 1, 1]

        entity.move(to: finalTransform, relativeTo: base, duration: 0.5, timingFunction: .easeOut)
    }
}
