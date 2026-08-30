import SwiftUI

// Android progressive build-scene: per-node glTF visibility via SceneView/Filament.
#if SKIP
import androidx.compose.runtime.Composable
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
#endif

struct AndroidGoalShowcaseView: View {
    let goalKind: GoalKind
    let progressRatio: Double
    @State private var isReady = false
    var body: some View {
        #if SKIP
        if let assetPath = Self.assetPath(for: goalKind) {
            ZStack {
                ComposeView { context in
                    AndroidShowcaseComposable(assetPath: assetPath, goalKind: goalKind,
                        progressRatio: progressRatio, modifier: context.modifier)
                }
                .opacity(isReady ? 1.0 : 0.0)
                SwiftUI.Color.black.opacity(isReady ? 0.0 : 1.0).allowsHitTesting(false)
            }
            .animation(.easeIn(duration: 0.15), value: isReady)
            .onAppear { isReady = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isReady = true } }
        } else { EmptyView() }
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

    let showcaseParts: [String] = remember(goalKind) {
        switch goalKind {
        case GoalKind.car:
            return ["body", "wheel_0", "wheel_1", "wheel_2", "wheel_3",
                "windshield", "rear_window", "headlight_l", "headlight_r"]
        case GoalKind.house:
            return ["walls", "roof", "door",
                "window_1", "window_2", "window_3", "window_4", "chimney"]
        default:
            return [String]()
        }
    }

    let totalParts: Int = showcaseParts.count
    let revealedCount: Int = totalParts > 0
        ? Swift.min(totalParts, Swift.max(0, Int(progressRatio * Double(totalParts))))
        : 0

    let cameraManipulator = rememberCameraManipulator(
        targetPosition: Position(x: Float(0.0), y: Float(0.32), z: Float(0.0)),
        orbitHomePosition: Position(x: Float(0.0), y: Float(0.48), z: Float(3.4)))

    Scene(modifier: modifier, surfaceType: SurfaceType.TextureSurface, isOpaque = false,
        engine: engine, modelLoader: modelLoader, cameraManipulator: cameraManipulator,
        environment: environmentLoader.createEnvironment()) {

        let plinthMaterial = materialLoader.createColorInstance(
            color: Color(red: Float(0.26), green: Float(0.23), blue: Float(0.19), alpha: Float(1.0)),
            metallic: Float(0.0), roughness: Float(0.8), reflectance: Float(0.2))
        CylinderNode(radius: Float(0.72), height: Float(0.035), materialInstance: plinthMaterial,
            position: Position(x: Float(0.0), y: Float(-0.018), z: Float(0.0)),
            apply: { isShadowReceiver = true })

        let baseInstance = rememberModelInstance(modelLoader, assetPath)
        if baseInstance != nil {
            let baseTransform = Position(x: Float(0.0), y: Float(0.018), z: Float(0.0))
            let baseRotation = Rotation(x: Float(-90.0))

            var hasCustomParts = false
            for (partIndex, nodeName) in zip(showcaseParts.indices, showcaseParts) {
                let isRevealed = partIndex < revealedCount
                let partInstance = rememberModelInstance(modelLoader, "\(assetPath)#\(nodeName)")
                if partInstance != nil {
                    hasCustomParts = true
                    if isRevealed {
                        ModelNode(modelInstance: partInstance, scaleToUnits: Float(1.25),
                            centerOrigin: Position(x: Float(0.0), y: Float(0.0), z: Float(-1.0)),
                            position: baseTransform, rotation: baseRotation,
                            apply: { isShadowCaster = true; isShadowReceiver = true })
                    }
                }
            }

            if !hasCustomParts {
                ModelNode(modelInstance: baseInstance, scaleToUnits: Float(1.25),
                    centerOrigin: Position(x: Float(0.0), y: Float(0.0), z: Float(-1.0)),
                    position: baseTransform, rotation: baseRotation,
                    apply: {
                        isVisible = (revealedCount > 0)
                        isShadowCaster = true
                        isShadowReceiver = true
                    })
            }
        }
    }
}
#endif
