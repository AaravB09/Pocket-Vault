import SwiftUI

// Android's finished-goal showcase. Keep the native scene deliberately
// declarative: the Scene owns its camera gestures and every node is declared
// directly in its content block (SceneScope), so SceneView removes and
// destroys it before the Build tab's engine/loaders are disposed.
#if SKIP
import androidx.compose.runtime.Composable
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

    // FIX (red/yellow "glitch square" flash on entering Build): confirmed
    // from screen recording — the instant this view mounts, a solid,
    // wrong-colored rectangle briefly fills exactly where the 3D scene
    // renders, then resolves into the actual car. That flash itself is a
    // real, unavoidable SurfaceView property (it shows whatever garbage was
    // already sitting in its GPU buffer until Filament's first real frame
    // lands), and pinning `.id(goalKind)` in BuildStudioView correctly stops
    // the view from being torn down/recreated unnecessarily.
    //
    // A first attempt tried to hide that first-mount flash with an opaque
    // plate drawn as a ZStack sibling on top of the scene. That did
    // *nothing* — confirmed against real behavior, not just theory: by
    // default `Scene`'s backing surface is a raw Android `SurfaceView`,
    // which punches a transparent hole through the window and is
    // compositied by SurfaceFlinger *outside* Compose's normal draw pass.
    // Ordinary Compose-drawn siblings (a `Color` box, an `.opacity()`
    // animation) aren't reliably able to paint over that hole — which is
    // exactly why SceneView's own docs recommend an opt-in `surfaceType` for
    // this. Below, `surfaceType: SurfaceType.TextureSurface, isOpaque: false`
    // switches the backing surface to a `TextureView`, which *does*
    // composite through the normal Compose layer — so it actually respects
    // z-order and alpha, and the cover plate below now genuinely covers it.
    @State private var isReady = false

    var body: some View {
        #if SKIP
        if let assetPath = Self.assetPath(for: goalKind) {
            ZStack {
                ComposeView { context in
                    AndroidShowcaseComposable(assetPath: assetPath, modifier: context.modifier)
                }
                .opacity(isReady ? 1.0 : 0.0)

                // Matches the plinth/scene's own dark backdrop so the
                // cover is invisible in its own right — it should just
                // look like the scene took a beat to appear, not like a
                // separate box popped in.
                SwiftUI.Color.black
                    .opacity(isReady ? 0.0 : 1.0)
                    .allowsHitTesting(false)
            }
            .animation(.easeIn(duration: 0.15), value: isReady)
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
func AndroidShowcaseComposable(assetPath: String, modifier: Modifier) {
    let engine = rememberEngine()
    let modelLoader = rememberModelLoader(engine)
    let materialLoader = rememberMaterialLoader(engine)
    let environmentLoader = rememberEnvironmentLoader(engine)

    // This handles orbit and pinch zoom without a second SwiftUI gesture.
    // Its target is fixed at the model center, so zooming cannot drift the
    // completed model away from the middle of its presentation.
    let cameraManipulator = rememberCameraManipulator(
        targetPosition: Position(x: Float(0.0), y: Float(0.32), z: Float(0.0)),
        orbitHomePosition: Position(x: Float(0.0), y: Float(0.48), z: Float(3.4))
    )

    // TextureSurface + isOpaque: false is the load-bearing part of the
    // actual fix (see the comment on `isReady` above) — it's what lets the
    // cover plate in `body` genuinely paint over this scene instead of a
    // SurfaceView hole-punch ignoring it.
    Scene(
        modifier: modifier,
        surfaceType: SurfaceType.TextureSurface,
        isOpaque: false,
        engine: engine,
        modelLoader: modelLoader,
        cameraManipulator: cameraManipulator,
        environment: environmentLoader.createEnvironment()
    ) {
        let plinthMaterial = materialLoader.createColorInstance(
            color: Color(red: Float(0.26), green: Float(0.23), blue: Float(0.19), alpha: Float(1.0)),
            metallic: Float(0.0), roughness: Float(0.8), reflectance: Float(0.2)
        )
        CylinderNode(
            radius: Float(0.72), height: Float(0.035), materialInstance: plinthMaterial,
            position: Position(x: Float(0.0), y: Float(-0.018), z: Float(0.0)),
            apply: { isShadowReceiver = true }
        )

        // These bundled GLBs were authored Z-up (their car's vertical
        // bounds are Z≈0.008...1.02). SceneView is Y-up, so we rotate -90°
        // about X. `centerOrigin` does the grounding/centering natively in
        // Kotlin against the model's own authored (pre-rotation) axes, so
        // "bottom" here means the minimum on the authored Z axis, and X/Y
        // are centered — avoiding any Swift-side boundingBox field access,
        // which isn't accessible as plain x/y/z from this side.
        if let instance = rememberModelInstance(modelLoader, assetPath) {
            ModelNode(
                modelInstance: instance,
                scaleToUnits: Float(1.25),
                centerOrigin: Position(x: Float(0.0), y: Float(0.0), z: Float(-1.0)),
                position: Position(x: Float(0.0), y: Float(0.018), z: Float(0.0)),
                rotation: Rotation(x: Float(-90.0)),
                apply: {
                    isShadowCaster = true
                    isShadowReceiver = true
                }
            )
        }
    }
}
#endif
