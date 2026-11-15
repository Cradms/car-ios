import SwiftUI

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CarHomeView()
                .tabItem {
                    Label("车控", systemImage: "car.fill")
                }
                .tag(0)

            NavigationView { LocationView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("位置", systemImage: "map.fill")
                }
                .tag(1)

            NavigationView { FuelView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("油耗", systemImage: "fuelpump.fill")
                }
                .tag(2)

            NavigationView { MaintainView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("维保", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(3)

            NavigationView { MoreView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(4)
        }
        .tint(C.blue)
    }
}
