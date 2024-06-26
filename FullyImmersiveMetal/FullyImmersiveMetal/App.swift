import SwiftUI
import CompositorServices

struct MetalLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration)
    {
        let supportsFoveation = capabilities.supportsFoveation
        let supportedLayouts = capabilities.supportedLayouts(options: supportsFoveation ? [.foveationEnabled] : [])

        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .shared

        configuration.layout = .shared
        //configuration.layout = .dedicated // not supporting it for now
//        configuration.layout = .layered
        if(configuration.layout == .shared)
        {
            configuration.isFoveationEnabled = false
        }
        else
        {
            configuration.isFoveationEnabled = false
        }
        
        
        configuration.colorFormat = .bgra8Unorm_srgb// .rgba16Float
        configuration.depthFormat = .depth32Float_stencil8
    }
}

//func myEnginePushSpatialEvents([Spatial ]) -> Void
//{
//
//}

func mySpatialEvent(_ event : SpatialEventCollection.Event) -> Void
{
    var s = event.location.x;
    s += event.location.y;
    print(s)
}

@main
struct FullyImmersiveMetalApp: App {
    var body: some Scene {
        WindowGroup(id: "Menu"){
            ContentView()
        }
	
        ImmersiveSpace(id: "ImmersiveSpace") {
            CompositorLayer(configuration: MetalLayerConfiguration()) { layerRenderer in
                SpatialRenderer_InitAndRun(layerRenderer)
                
                layerRenderer.onSpatialEvent = { eventCollection in
                    var events = eventCollection.map { mySpatialEvent($0) }
                  //  myEnginePushSpatialEvents(engine, &events, events.count)
                }
            }
        }.immersionStyle(selection: .constant(.full), in: .full)
    }
}
