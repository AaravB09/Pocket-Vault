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
    // Android-only momentum tracking for voxelStandIn2D's drag-to-rotate
    // (see the gesture there) — a smoothed running average of recent
    // per-frame rotation deltas, carried forward as a short spring-damped
    // spin on release instead of stopping the sculpture dead.
    @State private var dragVelocity: Float = Float(0.0)

    // iOS-only: the loaded GLB root entity (see GoalShowcaseModels) for the
    // hand-modeled reveal that progressively replaces the voxel pile during
    // the build, for the GoalKinds that have one. showcaseRootEntity is
    // nil either when "not loaded yet" or "no showcase model exists for
    // this goal kind" — showcaseLoadAttempted below is what tells those
    // two cases apart, so a genuine miss doesn't get retried every frame.
    //
    // showcaseRevealedNodes caches each child entity by its glTF node name
    // (e.g. "body", "wheel_0") after it's been resolved, so we don't pay
    // the findEntity(named:) lookup on every progress recomposition —
    // matches the existing optimization pattern of cachedVoxels.
    #if !SKIP
    @State private var showcaseRootEntity: Entity? = nil
    @State private var showcaseRevealedNodes: [String: Entity] = [:]
    #endif
    @State private var showcaseLoadAttempted: Bool = false

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

    // Switching goal kind (or blueprint) means any previously-loaded
    // showcase entity belongs to the OLD goal — drop it so the
    // update: closure loads the right one fresh instead of leaving the
    // wrong finished mesh on screen or skipping the load because
    // showcaseLoadAttempted was already true from the last goal.
    private func resetShowcaseState() {
        #if !SKIP
        showcaseRootEntity = nil
        showcaseRevealedNodes = [:]
        #endif
        showcaseLoadAttempted = false
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

    // POLISH ("clean and neat like Not So Boring Habits"): that reference
    // shot's payoff isn't just the model itself — it's the shower of gold
    // shards over it. This screen already had the mechanic for exactly
    // that (`ParticleBurstView`, used elsewhere on a successful deposit)
    // but never fired it here, so every piece unlock — and the finished
    // sculpture itself — landed with zero celebratory feedback beyond a
    // haptic tap. Wiring it in here is a small, low-risk addition (reused
    // component, not a new effect) that goes a real way toward that
    // "polished, considered" feel the flat voxel-brick shape alone can't
    // provide on its own.
    @State private var showUnlockBurst = false

    private var isComplete: Bool { unlockedCount >= cachedVoxels.count }

    var body: some View {
        ZStack {
            sculptureView

            ParticleBurstView(isActive: $showUnlockBurst)
                .allowsHitTesting(false)

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
                // Android-only: see the matching note in CalenderView.swift
                // / ContentView.swift — this fixed 60pt sat on top of the
                // real safe-area inset and read as more empty space above
                // the "BUILD STUDIO" label on Android than on iOS. Shrunk
                // further (24pt -> 10pt) since that first pass still read
                // as too much header space here.
                #if !SKIP
                .padding(.top, 60)
                #else
                .padding(.top, 10)
                #endif

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
                // Toggle true then false on the next runloop tick so a
                // second unlock right after can re-trigger it — matches
                // how ParticleBurstView is already driven at its other
                // call site (an `isActive` flip, not a one-shot event).
                showUnlockBurst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    showUnlockBurst = false
                }
            }
            lastUnlockedCount = unlockedCount
        }
        .onChange(of: goalKindRaw) { _ in
            recomputeVoxels()
            resetShowcaseState()
        }
        .onChange(of: customVoxelBlueprint) { _ in
            recomputeVoxels()
            resetShowcaseState()
        }
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
                // FIX ("just a bunch of cubes floating around"): three
                // separate root causes were stacking on top of each other
                // here, none of which are about the voxel *shapes*
                // themselves.
                //
                // 1. No explicit camera. Without one, RealityKit supplies
                //    an undocumented default (straight-on, unknown FOV),
                //    so the sculpture landed small and off-center instead
                //    of filling the frame the way a deliberate product
                //    shot (or the Android stand-in's tuned isometric
                //    projection) does.
                // 2. The base platform (`baseMat`, `white: 0.16`) was
                //    almost the exact same brightness as the app's dark
                //    theme background — effectively invisible. With
                //    nothing to read as "the ground," every voxel looked
                //    like it was hanging in empty space rather than
                //    sitting on something.
                // 3. Two lights, one key + one fill, both pure white, is a
                //    fine start but leaves the far/underside faces of each
                //    brick close to pure black — against an already near-
                //    black background, that means only the one or two lit
                //    faces per brick are visible at all, so a contiguous
                //    row of touching cubes reads as scattered bright
                //    fragments instead of one solid connected form.
                //
                // Fixed by: an explicit camera framing a 3/4 hero angle
                // (matching how the reference shot and the Android
                // isometric stand-in both frame their subject), a
                // brighter/warmer base plate that's actually visible
                // against the background, a soft dark contact-shadow disc
                // under it (the same trick `voxelStandIn2D` already uses
                // on Android), and a third warm rim light so no face of
                // the sculpture goes fully black. `spawnVoxel` below also
                // now sizes each brick to actually touch its neighbors
                // instead of leaving a visible gap between them.
                content.camera = .virtual

                let heroCamera = PerspectiveCamera()
                heroCamera.camera.fieldOfViewInDegrees = 38
                heroCamera.look(at: [0, -0.08, -0.85], from: [0.5, 0.46, 0.05], relativeTo: nil)
                content.add(heroCamera)

                // Soft contact shadow, same blurred-ellipse-under-the-
                // object language as the Android stand-in's shadow — an
                // unlit, partially transparent disc rather than a real
                // RealityKit shadow, so it reads identically regardless of
                // light direction.
                let shadowMesh = MeshResource.generatePlane(width: 0.62, depth: 0.34, cornerRadius: 0.17)
                let shadowEntity = ModelEntity(mesh: shadowMesh, materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.4))])
                shadowEntity.position = [0, -0.21, -0.85]
                content.add(shadowEntity)

                // Base platform — lightened and warmed so it actually
                // reads as a surface against the dark scene background
                // instead of disappearing into it.
                let baseMesh = MeshResource.generateCylinder(height: 0.02, radius: 0.6)
                let baseMat = SimpleMaterial(color: UIColor(red: 0.26, green: 0.23, blue: 0.19, alpha: 1.0), isMetallic: false)
                let baseEntity = ModelEntity(mesh: baseMesh, materials: [baseMat])
                baseEntity.position = [0, -0.2, -0.85]
                baseEntity.name = "assemblyBase"
                content.add(baseEntity)

                // Key light — without this, materials (especially metallic ones)
                // render close to black regardless of the color assigned.
                // Tinted warm gold (the app's own campfire-glow accent
                // convention, same read as the Android stand-in's glow and
                // the reference shot's lighting) instead of flat white.
                let keyLight = Entity()
                keyLight.components.set(DirectionalLightComponent(color: UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1.0), intensity: 4500))
                keyLight.look(at: [0, -0.3, -1.3], from: [0.6, 0.7, -0.3], relativeTo: nil)
                content.add(keyLight)

                // Soft fill light so the shadowed side of the sculpture isn't pure black.
                let fillLight = Entity()
                fillLight.components.set(PointLightComponent(color: UIColor.white, intensity: 4200, attenuationRadius: 4))
                fillLight.position = [-0.5, 0.2, -0.8]
                content.add(fillLight)

                // Warm rim/back light so the far side of the sculpture
                // (facing away from key+fill) still has SOME light on it
                // instead of going fully black and vanishing into the
                // background — this is the single biggest reason a row of
                // touching bricks used to look like separate floating
                // fragments rather than one connected shape.
                let rimLight = Entity()
                rimLight.components.set(PointLightComponent(color: UIColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1.0), intensity: 2600, attenuationRadius: 3))
                rimLight.position = [0, 0.15, -1.5]
                content.add(rimLight)
            } update: { content in
                guard let baseEntity = content.entities.first(where: { $0.name == "assemblyBase" }) else { return }
                baseEntity.orientation = simd_quatf(angle: rotationY, axis: [0, 1, 0])

                let unlocked = unlockedCount
                for (index, unit) in cachedVoxels.enumerated() where index < unlocked {
                    spawnVoxel(index: index, unit: unit, on: baseEntity)
                }

                // Progressive reveal for GoalKinds that have a curated build
                // asset (car, house). Voxels are shown for goal kinds without
                // a showcase asset (flight, gamingRig, etc.) or when a custom
                // AI-generated blueprint is active — we don't have a showcase
                // mesh for arbitrary shapes, only the curated GoalKind categories.
                // (customVoxelBlueprint is a Binding<String?>, so we unwrap via
                // `if let`-on-the-value the same way recomputeVoxels does above.)
                let blueprintJSON: String? = customVoxelBlueprint.flatMap { $0.isEmpty ? nil : $0 }
                let hasShowcase = (blueprintJSON == nil) && GoalShowcaseModels.hasShowcase(for: goalKind)
                let showcaseParts = hasShowcase ? (GoalShowcaseModels.showcaseBuildOrder[goalKind] ?? []) : []

                if hasShowcase {
                    // Show the real parts, hide the voxel pile.
                    for child in baseEntity.children where child.name.hasPrefix("voxel_") {
                        child.isEnabled = false
                    }
                    // Load the GLB once when the showcase is first reached.
                    if showcaseRootEntity == nil && !showcaseLoadAttempted {
                        showcaseLoadAttempted = true
                        Task {
                            let loaded = await GoalShowcaseModels.loadGLBEntity(for: goalKind)
                            await MainActor.run {
                                guard let loaded else { return } // load failed — silently keep voxel pile
                                loaded.name = "showcaseRoot"
                                loaded.position = [0, 0, 0]
                                loaded.scale = [1, 1, 1]
                                loaded.components.set(GroundingShadowComponent(castsShadow: true))
                                // All parts start hidden; we'll reveal them progressively below.
                                // Parent opacity doesn't affect individual child visibility, so
                                // set isEnabled on each named node directly.
                                for nodeName in showcaseParts {
                                    if let node = loaded.findEntity(named: nodeName) {
                                        node.isEnabled = false
                                    }
                                }
                                baseEntity.addChild(loaded)
                                showcaseRootEntity = loaded
                            }
                        }
                    }
                    // Reveal one part per progress stage crossed. Stages are
                    // divided evenly across showcaseParts — e.g. 9 parts for
                    // car = ~11% per stage. At 0% nothing is visible; at 100%
                    // all 9 parts form the complete car.
                    if let root = showcaseRootEntity {
                        let totalParts = showcaseParts.count
                        let revealedCount: Int = totalParts > 0
                            ? min(totalParts, max(0, Int(progressRatio * Double(totalParts))))
                            : 0
                        for (partIndex, nodeName) in showcaseParts.enumerated() {
                            let shouldBeVisible = partIndex < revealedCount
                            // Find or retrieve the cached node entity.
                            if let node = showcaseRevealedNodes[nodeName] {
                                // Already animated in — just keep it visible.
                                node.isEnabled = shouldBeVisible
                            } else if shouldBeVisible {
                                // This part just crossed into the revealed range —
                                // look it up and fly it in.
                                if let node = root.findEntity(named: nodeName) {
                                    showcaseRevealedNodes[nodeName] = node
                                    // Start offset: same pattern as spawnVoxel — offset
                                    // +0.3 on Y, scale 0.15, then animate to resting
                                    // position and scale 1.0 using the same easeOut.
                                    // The GLB nodes have their authored resting transforms
                                    // baked into the geometry, so identity = final pose.
                                    var startTransform = node.transform
                                    startTransform.translation.y += Float(0.3)
                                    startTransform.scale = SIMD3<Float>(repeating: Float(0.15))
                                    node.transform = startTransform
                                    node.isEnabled = true
                                    var finalTransform = node.transform
                                    finalTransform.translation.y -= Float(0.3)
                                    finalTransform.scale = SIMD3<Float>(repeating: Float(1.0))
                                    node.move(to: finalTransform, relativeTo: node.parent, duration: 0.5, timingFunction: .easeOut)
                                }
                            }
                        }
                    }
                } else {
                    // No showcase — show the voxel pile, hide any residual showcase nodes.
                    for child in baseEntity.children where child.name.hasPrefix("voxel_") {
                        child.isEnabled = true
                    }
                    if let root = showcaseRootEntity {
                        for nodeName in showcaseParts {
                            if let node = showcaseRevealedNodes[nodeName] {
                                node.isEnabled = false
                            }
                        }
                    }
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
        //
        // Completed curated goals use the actual GLB showcase. The
        // SceneView implementation owns all camera gestures internally;
        // unlike the earlier experiment, it does not mutate a native node
        // from a SwiftUI drag recomposition while the tab is disappearing.
        let usingCustomBlueprintAndroid = (customVoxelBlueprint?.isEmpty == false)
        // Progressive reveal on Android: the same real GLB parts used for the
        // completion reveal are now shown progressively as savings grow, using
        // per-node visibility control via the FilamentAsset's glTF node
        // hierarchy (see Androidgoalshowcaseview.swift). The `.id(goalKind)`
        // identity key prevents unnecessary SceneView teardowns during
        // particle-burst recompositions — the same fix that applied when this
        // was only at 100% completion, now running throughout the build.
        if !usingCustomBlueprintAndroid && GoalShowcaseModels.hasShowcase(for: goalKind) {
            AndroidGoalShowcaseView(goalKind: goalKind, progressRatio: progressRatio)
                .id(goalKind)
        } else {
            voxelStandIn2D
        }
        #endif
    }

    #if SKIP
    /// Simple isometric-style projection of a voxel's 3D position onto
    /// the 2D canvas: x and z both contribute to the horizontal axis (z
    /// also nudges vertically for a sense of depth), y is height.
    //
    // POLISH (Android "boring"/small-cluster-in-a-void complaint): was
    // 300.0. The individual voxel faces (voxelChip below) are sized to
    // read clearly on their own, but at this spacing the assembled
    // sculpture only filled a small fraction of its own canvas — next
    // to RealityKit's real camera framing on iOS (which fills the
    // frame with the piece by design), this stand-in read as a sparse
    // handful of cubes floating in a lot of empty space instead of one
    // cohesive object. Scaled up ~12% together with the canvas/base/
    // glow sizes just below, so the whole assembly fills its frame the
    // same way — a uniform zoom, not a change to any single mesh
    // type's calibrated proportions.
    private func projectedVoxelPoint(_ p: Vector3, center: CGPoint) -> CGPoint {
        let scale: CGFloat = 336.0
        let x = CGFloat(p.x) * scale
        let y = CGFloat(p.y) * scale
        let z = CGFloat(p.z) * scale
        return CGPoint(x: center.x + x + (z * 0.4), y: center.y - y - (z * 0.25))
    }

    // FIX(looked flat): `rotationY` used to only drive a
    // `.rotation3DEffect` on the *container* of an already-flattened
    // picture — every voxel's projected x/y and its depth-sort position
    // were computed once from the raw, un-rotated model coordinates and
    // never touched again. Dragging therefore just tilted a static
    // flat image; pieces never actually swapped which-is-in-front-of-
    // which, and the near/far size difference never shifted, both of
    // which are exactly the cues a real rotation would give — hence
    // "looks flat" even after the lighting-direction fix.
    //
    // This rotates each voxel's actual (x, z) position around the
    // vertical axis by `angle` radians — the same axis/convention as
    // iOS's real `simd_quatf(angle: rotationY, axis: [0,1,0])` in
    // sculptureView above — before it's ever projected or depth-sorted.
    // voxelStandIn2D now calls this once per voxel per render, so as
    // rotationY changes, pieces genuinely swap depth order and their
    // projected size/position shifts — real parallax instead of a
    // tilted sticker.
    private func rotatedPosition(_ p: Vector3, angle: Float) -> Vector3 {
        let c = Float(cos(Double(angle)))
        let s = Float(sin(Double(angle)))
        let rotatedX = p.x * c + p.z * s
        let rotatedZ = -p.x * s + p.z * c
        return Vector3(rotatedX, p.y, rotatedZ)
    }

    // Voxel model-space z sits roughly in [-0.5, 0.5] (see the `u` pitch
    // constants in GoalBuildLibrary — z multipliers there rarely exceed
    // ±5 units of ~0.09-0.096). Used to turn raw z into a 0...1 "how close
    // to the camera" fraction for both perspective scale and shading.
    private func depthFraction(_ z: Float) -> CGFloat {
        // FIX: same generic min/max overload-resolution problem as every
        // other clamp in this file/project (Skip's Kotlin codegen can't
        // resolve `max(Double, min(Double, Float))`) — clamp with plain
        // comparisons instead.
        let clamped: Float = z < Float(-0.5) ? Float(-0.5) : (z > Float(0.5) ? Float(0.5) : z)
        return CGFloat((clamped + 0.5) / 1.0) // 0 = farthest, 1 = nearest
    }

    // FIX(looked flat): widened from 0.8x...1.2x. That range was so
    // narrow the size difference between the front and back of the
    // sculpture barely registered — combined with the rotation bug
    // above (no actual parallax), size was nearly the only depth cue
    // available and it was too subtle to read. Real perspective on a
    // sculpture this size falls off faster than 1.5x front-to-back.
    private func perspectiveScale(_ depthT: CGFloat) -> CGFloat {
        0.62 + depthT * 0.68 // 0.62x at the back, 1.3x at the front
    }

    // FIX (weird-looking Build model on Android): this is where the
    // "weird" complaint actually came from. `unit.orientation` (the
    // `VoxelOrientation` angle/axis each piece carries — see
    // Goalbuildmodels.swift, e.g. car wheels and plane
    // turbines/nose-cone are built with a 90° rotation) was never read
    // anywhere in this 2D stand-in. Every piece drew as a plain upright
    // circle/cube regardless of how it's actually oriented in the build,
    // so wheels that should sit tipped toward the camera, and turbines/
    // nose cones that should lie on their side, all rendered standing
    // straight up instead — the RealityKit path on iOS was never wrong,
    // only this Android fallback was ignoring the data it already had.
    //
    // Exact 3D-accurate rotation isn't possible with flat SwiftUI shapes
    // (same reasoning as depthFraction/perspectiveScale above), so this
    // approximates the two rotations that actually show up in
    // GoalBuildLibrary:
    //  - a roll around the depth axis (`axis.z`) is a genuine in-plane
    //    2D rotation — maps 1:1 onto `.rotationEffect`.
    //  - a pitch around the horizontal axis (`axis.x`) tips the piece's
    //    long axis from standing (vertical) toward facing the camera —
    //    approximated by squashing it, the same "flatten toward the
    //    viewer" idea the cube's top face above already uses.
    private func chipTilt(for orientation: VoxelOrientation) -> (rollDegrees: Double, squash: CGFloat) {
            let angleDegrees = Double(orientation.angle) * 180.0 / Double.pi
            
            // Unfold abs() into plain comparisons to bypass Kotlin's generic resolution failures
            if orientation.axis.z > 0.5 || orientation.axis.z < -0.5 {
                return (angleDegrees * (orientation.axis.z < 0 ? -1.0 : 1.0), 1.0)
            }
            
            if orientation.axis.x > 0.5 || orientation.axis.x < -0.5 {
                // Unfold both abs() and min() here to be safe
                let absoluteAngle = angleDegrees > 0 ? angleDegrees : -angleDegrees
                let rawT = absoluteAngle / 90.0
                let t = rawT < 1.0 ? rawT : 1.0
                
                return (0.0, 1.0 - CGFloat(t) * 0.65)
            }
            
            return (0.0, 1.0)
        }

    // FIX (Build Studio "trashy" on Android): the actual gap between iOS
    // and Android wasn't the orientation tilt above (real, but a smaller
    // slice of it) — it was that `.cylinder` and `.cone` rendered as the
    // exact same flat dot regardless of mesh, with no taper, no visible
    // body, nothing to distinguish a bottle-shaped piece from a nose
    // cone. Every real RealityKit mesh on iOS has actual volume and a
    // silhouette; this stand-in was giving every rounded piece in the
    // sculpture the identical circle. Split into two real silhouettes
    // below (voxelCylinder / voxelCone), each with its own body, taper,
    // and lit/shadow faces, using the same upper-right key light + lower-
    // left fill light convention as the cube case already establishes.
    private struct ConeSilhouette: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    @ViewBuilder
    private func voxelCylinder(baseColor: Color, scale: CGFloat, haze: Double, isMetallic: Bool) -> some View {
        // Roughly matches GoalBuildLibrary's real proportions (height
        // 0.08 vs radius 0.038 -> a little taller than it is wide),
        // instead of the perfectly round dot every cylinder/cone piece
        // used to share.
        // FIX ("tiny speck" complaint): was 15.0/19.0 — big enough next
        // to the platform's old 170pt width, but once that base shrank
        // to match real proportions (see voxelStandIn2D), the pieces
        // themselves were still too small to read as an actual shape,
        // especially early on with only 1-2 unlocked. Bumped ~35% across
        // every mesh type below (cylinder/cone/flatSlab/cube) so a
        // single starter piece is clearly visible instead of a smudge.
        //
        // POLISH: another ~12% on top of that, matching the same bump
        // to voxelStandIn2D's projection spacing above — pieces grow
        // together with the extra room between them instead of just
        // spreading further apart at the old size, which would have
        // made the sculpture read as sparser, not more substantial.
        let width: CGFloat = 22.4 * scale
        let height: CGFloat = 28.0 * scale
        let capHeight: CGFloat = width * 0.42

        ZStack {
            // Cylindrical body.
            RoundedRectangle(cornerRadius: width * 0.22)
                .fill(baseColor)
                .frame(width: width, height: height - capHeight * 0.5)
                .offset(y: capHeight * 0.25)

            // Shadowed left face — weaker fill light only (x=-0.5), same
            // convention as the cube case below. Metallic pieces get a
            // deeper shadow (metals have a higher lit/shadow contrast
            // ratio than matte surfaces since they reflect the light
            // source directly instead of scattering it).
            RoundedRectangle(cornerRadius: width * 0.18)
                .fill(Color.black.opacity((isMetallic ? 0.4 : 0.26) + haze * 0.4))
                .frame(width: width * 0.36, height: height - capHeight * 0.5)
                .offset(x: -width * 0.32, y: capHeight * 0.25)

            // Narrow, near-white "hot" specular streak — the metallic
            // signature that was completely missing before, which made
            // gold cylinder pieces (bottle necks, ring accents) read as
            // dull matte plastic instead of metal.
            if isMetallic {
                RoundedRectangle(cornerRadius: width * 0.1)
                    .fill(Color.white.opacity(0.6 - haze))
                    .frame(width: width * 0.16, height: (height - capHeight * 0.5) * 0.8)
                    .offset(x: width * 0.18, y: capHeight * 0.25)
            }

            // Top cap — the lit, camera-facing plane, catching the key
            // light from above just like the cube's top face.
            Ellipse()
                .fill(Color.white.opacity((isMetallic ? 0.5 : 0.28) - haze))
                .frame(width: width, height: capHeight)
                .offset(y: -height / 2.0 + capHeight * 0.5)
            Ellipse()
                .stroke(Color.black.opacity(0.16 + haze * 0.2), lineWidth: 0.75)
                .frame(width: width, height: capHeight)
                .offset(y: -height / 2.0 + capHeight * 0.5)

            // Contact shadow along the base for volume.
            Ellipse()
                .fill(Color.black.opacity(0.22 + haze * 0.3))
                .frame(width: width * 0.9, height: capHeight * 0.6)
                .offset(y: height / 2.0 - capHeight * 0.3)
        }
        .frame(width: width, height: height)
        .opacity(1.0 - haze * 0.5)
        .shadow(color: .black.opacity(0.35), radius: 3.0 * scale, x: 2.0 * scale, y: 3.0 * scale)
    }

    @ViewBuilder
    private func voxelCone(baseColor: Color, scale: CGFloat, haze: Double, isMetallic: Bool) -> some View {
        // Real proportions (height 0.17 vs radius 0.07) make this the
        // tallest, most tapered piece in the build — the nose cone and
        // turbine housings depend on that taper actually reading as a
        // point, not a circle, to look like their real-world shape.
        // POLISH: ~12% bump, same reasoning as voxelCylinder above.
        let width: CGFloat = 25.8 * scale
        let height: CGFloat = 33.6 * scale
        let baseCapHeight: CGFloat = width * 0.36

        ZStack {
            ConeSilhouette()
                .fill(
                    LinearGradient(
                        colors: [baseColor, baseColor.opacity(0.72)],
                        startPoint: UnitPoint(x: 0.15, y: 0), endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                .frame(width: width, height: height - baseCapHeight * 0.5)
                .offset(y: baseCapHeight * 0.25)

            // Lit streak down the right side of the cone (key light at
            // x=+0.6), narrowing toward the apex the same way a real
            // cone's highlight would. Metallic pieces (gold reveal cones,
            // gem prongs) get this brighter and tighter — a sharp glint
            // instead of a soft sheen — which is the main visual cue that
            // was missing versus iOS's metallic SimpleMaterial.
            ConeSilhouette()
                .fill(Color.white.opacity((isMetallic ? 0.5 : 0.22) - haze))
                .frame(width: width * (isMetallic ? 0.14 : 0.22), height: (height - baseCapHeight * 0.5) * 0.85)
                .offset(x: width * 0.22, y: baseCapHeight * 0.25 + (height - baseCapHeight * 0.5) * 0.06)

            // Base ellipse the cone tapers up from.
            Ellipse()
                .fill(Color.black.opacity((isMetallic ? 0.34 : 0.24) + haze * 0.3))
                .frame(width: width, height: baseCapHeight)
                .offset(y: height / 2.0 - baseCapHeight * 0.4)
        }
        .frame(width: width, height: height)
        .opacity(1.0 - haze * 0.5)
        .shadow(color: .black.opacity(0.35), radius: 3.0 * scale, x: 2.0 * scale, y: 3.0 * scale)
    }

    /// Faux-3D voxel: instead of a single flat fill, each piece is drawn
    /// as 2-3 stacked, offset faces (a lit top plane, a shadowed side
    /// plane, a base plane) the way isometric pixel/voxel art fakes depth
    /// with no real 3D engine. `depthT` (0 = farthest, 1 = nearest) drives
    /// both size (perspectiveScale) and shading, so pieces further from
    /// the camera are smaller AND slightly darker/hazier — both depth
    /// cues SwiftUI can render with only flat shapes.
    @ViewBuilder
    private func voxelChip(_ unit: VoxelUnit, depthT: CGFloat) -> some View {
        let tilt = chipTilt(for: unit.orientation)
        voxelChipFace(unit, depthT: depthT)
            .scaleEffect(x: 1.0, y: tilt.squash, anchor: .center)
            .rotationEffect(.degrees(tilt.rollDegrees))
    }

    @ViewBuilder
    private func voxelChipFace(_ unit: VoxelUnit, depthT: CGFloat) -> some View {
        let baseColor = Color(unit.color)
        let scale = perspectiveScale(depthT)
        // Farther pieces get a touch of haze (lighter + lower contrast),
        // matching how the RealityKit key/fill lights already fall off
        // with distance on iOS.
        let haze = (1.0 - depthT) * 0.22

        switch unit.mesh {
        case .cylinder:
            voxelCylinder(baseColor: baseColor, scale: scale, haze: haze, isMetallic: unit.isMetallic)

        case .cone:
            voxelCone(baseColor: baseColor, scale: scale, haze: haze, isMetallic: unit.isMetallic)

        case .flatSlab:
            let width: CGFloat = 34.0 * scale
            let height: CGFloat = 10.5 * scale
            ZStack {
                RoundedRectangle(cornerRadius: 3.0).fill(baseColor)
                // Top edge highlight so the slab reads as a thin block,
                // not a flat painted rectangle. Metallic trim (gold
                // ribbon/edging) gets a narrower, near-white "hot" streak
                // instead of the broad soft highlight matte pieces get —
                // real metals reflect the light source itself rather than
                // scattering it, so the highlight is small and intense
                // rather than wide and gentle. Matches SimpleMaterial's
                // isMetallic look on iOS, which this fallback previously
                // ignored entirely.
                RoundedRectangle(cornerRadius: 2.0)
                    .fill(Color.white.opacity(unit.isMetallic ? 0.62 - haze : 0.24 - haze))
                    .frame(width: unit.isMetallic ? width * 0.5 : width, height: height * (unit.isMetallic ? 0.3 : 0.4))
                    .offset(x: unit.isMetallic ? -width * 0.18 : 0.0, y: -height * 0.26)
                RoundedRectangle(cornerRadius: 2.0)
                    .fill(Color.black.opacity((unit.isMetallic ? 0.32 : 0.22) + haze * 0.4))
                    .frame(height: height * 0.32)
                    .offset(y: height * 0.3)
            }
            .frame(width: width, height: height)
            .opacity(1.0 - haze * 0.5)
            .shadow(color: .black.opacity(0.3), radius: 2.0 * scale, x: 1.0 * scale, y: 2.0 * scale)

        case .cube:
            let s: CGFloat = 21.0 * scale
            ZStack {
                // Front/right face — base tone. This is the face angled
                // toward the key light (see the cylinder/cone fix above:
                // key light is at x=+0.6, camera's right), so it stays at
                // full base color rather than being darkened.
                RoundedRectangle(cornerRadius: 2.5).fill(baseColor)
                    .frame(width: s, height: s)

                // Metallic-only: a small, sharp diagonal glint across the
                // lit face. This is what previously made gold pieces
                // (ring bands, trim, bows) render as flat matte-colored
                // squares indistinguishable from charcoal/ivory pieces —
                // `unit.isMetallic` was carried on every VoxelUnit but
                // never actually read anywhere in this rendering path.
                if unit.isMetallic {
                    RoundedRectangle(cornerRadius: 1.0)
                        .fill(Color.white.opacity(0.55 - haze * 0.6))
                        .frame(width: s * 0.22, height: s * 0.85)
                        .rotationEffect(.degrees(28))
                        .offset(x: s * 0.12, y: -s * 0.05)
                        .frame(width: s, height: s)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5))
                }

                // Left face — darkened and squeezed thin, offset to the
                // left, reading as the cube's receding side plane.
                //
                // FIX: this used to be the RIGHT face that got darkened
                // (offset +s*0.34), on the same mirrored-lighting
                // assumption as the cylinder/cone highlight above. Since
                // the real key light sits at x=+0.6, the right side of
                // every voxel is the lit side on iOS, not the shadowed
                // one — the shadow plane belongs on the left, where only
                // the weaker fill light (x=-0.5) reaches.
                RoundedRectangle(cornerRadius: 2.0)
                    .fill(Color.black.opacity(0.3 + haze * 0.4))
                    .frame(width: s * 0.4, height: s)
                    .offset(x: -s * 0.34)

                // Top face — lightened, squashed flat and rotated
                // slightly, reading as the lit plane catching the key
                // light from above (matches iOS's DirectionalLightComponent).
                // Rotation direction flipped to +8° to lean toward the
                // same right-side key light as the faces above.
                RoundedRectangle(cornerRadius: 2.0)
                    .fill(Color.white.opacity(0.3 - haze))
                    .frame(width: s * 1.02, height: s * 0.4)
                    .rotationEffect(.degrees(8))
                    .offset(y: -s * 0.34)
            }
            .frame(width: s, height: s)
            .opacity(1.0 - haze * 0.5)
            .shadow(color: .black.opacity(0.35), radius: 3.0 * scale, x: 2.0 * scale, y: 3.0 * scale)
        }
    }

    /// One voxel's rotated-this-frame position, paired with its stable
    /// `offset` (for `ForEach` identity) and original `unit` data. Kept
    /// as a real struct rather than an anonymous/named tuple since
    /// Skip's transpiler is unreliable with tuple labels captured across
    /// closures (see the `Vector3`/`VoxelOrientation` notes in
    /// Goalbuildmodels.swift for the same reasoning).
    private struct ProjectedVoxel {
        let offset: Int
        let unit: VoxelUnit
        let rotatedPosition: Vector3
    }

    private var voxelStandIn2D: some View {
        let unlocked = unlockedCount
        // rotationY is a true angle in radians here (see rotatedPosition
        // above) — the same value and convention as iOS's real
        // simd_quatf rotation, just applied to 2D-projected geometry
        // instead of an actual 3D engine.
        let angle = rotationY

        let projected: [ProjectedVoxel] = cachedVoxels.enumerated()
            .filter { $0.offset < unlocked }
            .map { ProjectedVoxel(offset: $0.offset, unit: $0.element, rotatedPosition: rotatedPosition($0.element.position, angle: angle)) }

        // Painter's algorithm: draw farthest pieces first so nearer ones
        // correctly overlap them. Now sorted by each voxel's ROTATED z,
        // recomputed every render as the user drags — so which piece is
        // "in front" genuinely changes as the sculpture turns, instead
        // of a fixed build-order z that never updated.
        let depthOrdered = projected.sorted { $0.rotatedPosition.z < $1.rotatedPosition.z }

        return GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2.0, y: geo.size.height * 0.62)
            ZStack {
                // POLISH (Android "boring" complaint): this was a single
                // flat white glow, sized and tinted like a fluorescent
                // work light rather than anything that felt considered.
                // Two layers now — a wide, warm outer glow tinted with
                // the app's own accent color (the same "campfire glow"
                // read as the reference — a warm pool of light the
                // object sits in, not a cold spotlight) plus the
                // original tighter white highlight kept on top for a
                // bit of a hot center. Both sized up alongside the
                // scale bump above so the glow reads as part of the
                // same bigger, more deliberate presentation.
                RadialGradient(
                    colors: [theme.accent.opacity(0.22), Color.clear],
                    center: .center, startRadius: 8, endRadius: 170
                )
                .frame(width: 340, height: 340)
                .position(x: center.x, y: center.y - 6)

                RadialGradient(
                    colors: [Color.white.opacity(0.12), Color.clear],
                    center: .center, startRadius: 4, endRadius: 140
                )
                .frame(width: 290, height: 290)
                .position(x: center.x, y: center.y - 10)

                // Soft ambient shadow beneath the platform — iOS gets this
                // for free from RealityKit's own shadow-casting; this
                // blurred, oversized dark ellipse is the flat-shape
                // equivalent, so the whole assembly reads as sitting on
                // something instead of floating over a hard-edged disc.
                Ellipse()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 132.0, height: 28.0)
                    .blur(radius: 7)
                    .position(x: center.x, y: center.y + 28.0)

                // Base platform, matching the iOS cylinder base.
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.12)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 119.0, height: 32.0)
                    .position(x: center.x, y: center.y + 23.0)
                // Thin rim catching the key light, same upper-right
                // convention as every voxel face above.
                Ellipse()
                    .trim(from: 0.05, to: 0.45)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.25)
                    .frame(width: 119.0, height: 32.0)
                    .position(x: center.x, y: center.y + 23.0)

                ForEach(depthOrdered, id: \.offset) { item in
                    voxelChip(item.unit, depthT: depthFraction(item.rotatedPosition.z))
                        .position(projectedVoxelPoint(item.rotatedPosition, center: center))
                }
            }
        }
        .frame(height: 292.0)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // FIX(looked flat): was `* Float(0.02)` feeding a
                    // flat `.rotation3DEffect` skew — see the notes on
                    // rotatedPosition(_:angle:) and perspectiveScale
                    // above for why that read as flat regardless of
                    // sensitivity. Now that rotationY drives real
                    // per-voxel rotation, its sensitivity is set to
                    // roughly match iOS's real drag-to-rotate feel
                    // (iOS uses 0.006 rad/pt on its 3D gesture; this
                    // stand-in's screen-space projection is coarser, so
                    // a touch higher keeps the drag feeling equally
                    // responsive).
                    let delta = Float(value.translation.width - lastDragTranslation) * Float(0.01)
                    rotationY += delta
                    // Tracked per-frame so release can carry it forward
                    // as fling velocity below — smoothed (not just the
                    // latest instantaneous delta) so a slightly jittery
                    // final touch sample right at lift-off doesn't
                    // produce a jerky flick.
                    dragVelocity = dragVelocity * Float(0.7) + delta * Float(0.3)
                    lastDragTranslation = value.translation.width
                }
                .onEnded { _ in
                    lastDragTranslation = 0
                    // FIX (Android "smooth" ask): rotation used to stop
                    // dead the instant the finger lifted — every other
                    // interactive surface in the app (buttons, tab
                    // switches) eases in/out, so a hard stop here read as
                    // noticeably stiffer/cheaper than the rest of the UI.
                    // This carries the last few frames of drag speed
                    // forward as a short spring-damped spin, the same
                    // "flick and it glides to a stop" feel as a native
                    // scroll view or the reference clips' card/sheet
                    // transitions, instead of the sculpture just halting.
                    let flingDistance = dragVelocity * Float(9.0)
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                        rotationY += flingDistance
                    }
                    dragVelocity = Float(0.0)
                }
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

        // FIX ("floating cubes" — size vs. pitch mismatch): brick
        // positions come from GoalBuildLibrary at a pitch of ~0.09-0.096
        // (the `u` constant in each build), but these meshes were sized
        // at a flat 0.08 regardless of build — leaving a visible gap
        // (10-17% of a brick's width) between every adjacent pair. Two
        // bricks that are SUPPOSED to sit edge-to-edge as one solid bar
        // instead sat a hair apart with dark background showing through
        // the seam, which at this scale reads as separate floating
        // pieces rather than one connected object. Sized up ~12% (and
        // the corner radius trimmed proportionally, since a bigger
        // bevel on a bigger cube would exaggerate the per-brick "pebble"
        // look this is trying to get rid of) so neighboring bricks now
        // actually touch across every build's pitch instead of gapping.
        let mesh: MeshResource
        switch unit.mesh {
        case .cube:
            mesh = .generateBox(size: 0.09, cornerRadius: 0.008)
        case .cylinder:
            mesh = .generateCylinder(height: 0.09, radius: 0.042)
        case .cone:
            mesh = .generateCone(height: 0.19, radius: 0.078)
        case .flatSlab:
            mesh = .generateBox(size: [0.27, 0.02, 0.078], cornerRadius: 0.006)
        }

        let material = SimpleMaterial(color: unit.color, isMetallic: unit.isMetallic)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.orientation = simd_quatf(angle: unit.orientation.angle, axis: axis)
        // Lets each brick cast/receive RealityKit's real shadow, on top
        // of the whole-assembly contact shadow added in sculptureView —
        // small, but it's another cue that these pieces occupy real
        // shared space instead of each floating independently.
        entity.components.set(GroundingShadowComponent(castsShadow: true))

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
