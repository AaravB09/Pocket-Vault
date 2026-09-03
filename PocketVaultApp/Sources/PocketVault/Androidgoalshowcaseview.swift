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
import io.github.sceneview.node.Node // Imported to ensure Skip resolves child nodes correctly
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

    // Store reference to the created ModelNode
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
            ModelNode(
                modelInstance: baseInstance,
                scaleToUnits: Float(1.25),
                centerOrigin: Position(x: Float(0.0), y: Float(0.0), z: Float(-1.0)),
                position: baseTransform,
                rotation: baseRotation,
                apply: {
                    // Save reference to self (ModelNode) for SideEffect updates
                    showcaseNode = self

                    // Initial node visibility setup using SceneView's 'childNodes'.
                    // Using a direct for-loop prevents Skip closure mapping errors.
                    for childNode in childNodes {
                        if let childName = childNode.name, showcaseParts.contains(childName) {
                            childNode.isVisible = GoalShowcaseModels.isRevealed(
                                nodeName: childName, for: goalKind, progressRatio: clampedProgress)
                        }
                    }

                    isShadowCaster = true
                    isShadowReceiver = true
                }
            )
        }
    }

    // Reactive updates when progressRatio changes
    SideEffect {
        guard let node = showcaseNode else { return }
        
        for childNode in node.childNodes {
            if let childName = childNode.name, showcaseParts.contains(childName) {
                childNode.isVisible = GoalShowcaseModels.isRevealed(
                    nodeName: childName, for: goalKind, progressRatio: clampedProgress)
            }
        }
    }
}
#endif // SKIP
