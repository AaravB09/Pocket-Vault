import SwiftUI

// Android progressive build-scene: per-node glTF visibility via SceneView/Filament.
#if SKIP
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import io.github.sceneview.Scene
import io.github.sceneview.SurfaceType
import io.github.sceneview.node.CylinderNode
import io.github.sceneview.node.ModelNode
import io.github.sceneview.rememberCameraManipulator
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberEnvironmentLoader
import io.github.sceneview.rememberMaterialLoader
import io.github.sceneview.rememberModelInstance
import io.github.sceneview.rememberModelLoader
import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
#endif // SKIP

struct AndroidGoalShowcaseView: View {
    let goalKind: GoalKind
    let progressRatio: Double
    @State private var isReady = false
    
    var body: some View {
        #if SKIP
        if let assetPath = Self.assetPath(for: goalKind) {
            ZStack {
                ComposeView { context in
                    AndroidShowcaseComposable(
                        assetPath: assetPath,
                        goalKind: goalKind,
                        progressRatio: progressRatio,
                        modifier: context.modifier
                    )
                }
                .opacity(isReady ? 1.0 : 0.0)
                
                SwiftUI.Color.black.opacity(isReady ? 0.0 : 1.0).allowsHitTesting(false)
            }
            .animation(Animation.easeIn(duration: 0.15), value: isReady)
            .onAppear {
                isReady = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isReady = true
                }
            }
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
    
    private static func assetPath(for goalKind: GoalKind) -> String? {
        switch goalKind {
        case .car: return "pocket/vault/Resources/Models/car.glb"
        case .house: return "pocket/vault/Resources/Models/house.glb"
        default: return nil
        }
    }
}

#if SKIP
@Composable
func AndroidShowcaseComposable(assetPath: String, goalKind: GoalKind,
    progressRatio: Double, modifier: Modifier) {
    
    let engine = rememberEngine()
    let modelLoader = rememberModelLoader(engine)
    let materialLoader = rememberMaterialLoader(engine)
    let environmentLoader = rememberEnvironmentLoader(engine)

    // Clamp progressRatio to [0.0, 1.0]
    let clampedProgress: Double
    if progressRatio < 0.0 { clampedProgress = 0.0 }
    else if progressRatio > 1.0 { clampedProgress = 1.0 }
    else { clampedProgress = progressRatio }

    // Source of truth for the ordered node list
    let showcaseParts: [String] = GoalShowcaseModels.showcaseBuildOrder[goalKind] ?? []

    let cameraManipulator = rememberCameraManipulator(
        targetPosition: Position(x: Float(0.0), y: Float(0.32), z: Float(0.0)),
        orbitHomePosition: Position(x: Float(0.0), y: Float(0.48), z: Float(3.4)))

    // Capture the ModelNode reference once constructed so SideEffect can
    // walk and mutate its renderable children on every progress change.
    @State var showcaseNode: ModelNode? = nil

    Scene(
        modifier: modifier,
        surfaceType: SurfaceType.TextureSurface,
        isOpaque: false,
        engine: engine,
        modelLoader: modelLoader,
        cameraManipulator: cameraManipulator,
        environment: environmentLoader.createEnvironment()) {

        let plinthMaterial = materialLoader.createColorInstance(
            color: Color(red: Float(0.26), green: Float(0.23), blue: Float(0.19), alpha: Float(1.0)),
            metallic: Float(0.0), roughness: Float(0.8), reflectance: Float(0.2))
        CylinderNode(
            radius: Float(0.72),
            height: Float(0.035),
            materialInstance: plinthMaterial,
            position: Position(x: Float(0.0), y: Float(-0.018), z: Float(0.0)),
            apply: { isShadowReceiver = true }
        )

        let baseTransform = Position(x: Float(0.0), y: Float(0.018), z: Float(0.0))
        let baseRotation = Rotation(x: Float(-90.0))

        let baseInstance = rememberModelInstance(modelLoader, assetPath)
        if baseInstance != nil {

            // ONE ModelNode for the whole asset — no per-part instances.
            // The apply: closure receives self (the ModelNode) so we can
            // capture a reference and do the initial visibility setup.
            ModelNode(
                modelInstance: baseInstance,
                scaleToUnits: Float(1.25),
                centerOrigin: Position(x: Float(0.0), y: Float(0.0), z: Float(-1.0)),
                position: baseTransform,
                rotation: baseRotation,
                apply: { [showcaseNode] capturedNode in
                    // Capture the ModelNode reference for SideEffect.
                    showcaseNode = capturedNode

                    // One-shot diagnostic: log all renderable node names on first load
                    // so we can verify they match the strings in showcaseBuildOrder.
                    let allNames: [String] = capturedNode.renderableNodes.map { $0.name ?? "(null)" }
                    print("[nodeNames] all=\(allNames)")

                    // Initial visibility: show only the parts that pass their
                    // checkpoint at this progress ratio. Unrevealed parts are
                    // hidden immediately so the car/house assembles correctly.
                    for partName in showcaseParts {
                        let shouldReveal = GoalShowcaseModels.isRevealed(
                            nodeName: partName, for: goalKind, progressRatio: clampedProgress)
                        let foundNode = capturedNode.renderableNodes.getOrNull(name: partName)
                        if let foundNode {
                            foundNode.isVisible = shouldReveal
                        }
                    }

                    isShadowCaster = true
                    isShadowReceiver = true
                }
            )
        }
    } // Closes: Scene

    // SideEffect re-fires whenever clampedProgress changes (deposits landing,
    // savings deducted, etc.) and mutates the already-constructed ModelNode's
    // renderable children in-place. This is the same pattern iOS uses in
    // BuildStudioView's update: closure — a reactive mutation that doesn't
    // recreate the model.
    SideEffect {
        guard let node = showcaseNode else { return }
        for partName in showcaseParts {
            let shouldReveal = GoalShowcaseModels.isRevealed(
                nodeName: partName, for: goalKind, progressRatio: clampedProgress)
            let foundNode = node.renderableNodes.getOrNull(name: partName)
            if let foundNode {
                foundNode.isVisible = shouldReveal
            }
        }
    }
} // Closes: func AndroidShowcaseComposable
#endif // SKIP
