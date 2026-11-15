import SwiftUI
import MapKit

struct CarLocation: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}

struct LocationView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.8629, longitude: 106.9606),
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
    @State private var pin: CarLocation?
    @State private var address = "定位中…"
    @State private var city = ""
    @State private var gpsTime = ""
    @State private var speed = ""
    @State private var loading = true
    @State private var errMsg: String?

    private let api = CarAPI.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 地图
                ZStack(alignment: .bottomLeading) {
                    if let p = pin {
                        Map(coordinateRegion: $region,
                            annotationItems: [p]) { item in
                            MapAnnotation(coordinate: item.coord) {
                                ZStack {
                                    Circle()
                                        .fill(C.blue.opacity(0.18))
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .fill(C.blue)
                                        .frame(width: 15, height: 15)
                                        .overlay(Circle().stroke(.white, lineWidth: 3))
                                }
                                .shadow(color: C.blue.opacity(0.35), radius: 6, y: 2)
                            }
                        }
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(C.bg)
                            .frame(height: 300)
                            .overlay {
                                if loading {
                                    ProgressView()
                                } else {
                                    Text(errMsg ?? "没有位置数据")
                                        .font(.system(size: 13))
                                        .foregroundColor(C.faint)
                                }
                            }
                    }

                    // 右下角刷新
                    Button { load() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(C.blue)
                            .frame(width: 34, height: 34)
                            .background(.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // 地址卡
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 16))
                                .foregroundColor(C.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(address)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(C.txt)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !city.isEmpty || !gpsTime.isEmpty {
                                    Text([city, gpsTime].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 11))
                                        .foregroundColor(C.faint)
                                }
                            }
                            Spacer()
                        }

                        if let p = pin {
                            Divider().opacity(0.5)
                            HStack(spacing: 0) {
                                info("纬度", String(format: "%.6f", p.coord.latitude))
                                Divider().frame(height: 24).opacity(0.5)
                                info("经度", String(format: "%.6f", p.coord.longitude))
                                Divider().frame(height: 24).opacity(0.5)
                                info("速度", speed.isEmpty ? "--" : "\(speed) km/h")
                            }
                        }
                    }
                }

                // 操作按钮
                if let p = pin {
                    HStack(spacing: 10) {
                        Button { openAMap(p.coord) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                Text("导航到车辆")
                                    .font(.system(size: 14.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(C.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        Button {
                            UIPasteboard.general.string =
                                "\(p.coord.latitude),\(p.coord.longitude)"
                            toast("坐标已复制")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundColor(C.blue)
                                .frame(width: 48, height: 48)
                                .background(C.card)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13)
                                    .stroke(C.border, lineWidth: 1))
                        }
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(C.bg.ignoresSafeArea())
        .navigationTitle("车辆位置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(C.txt)
            Text(title).font(.system(size: 9.5)).foregroundColor(C.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func toast(_ s: String) {
        let a = UIAlertController(title: nil, message: s, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(a, animated: true)
        }
    }

    private func load() {
        loading = true
        errMsg = nil
        api.location { d in
            DispatchQueue.main.async {
                loading = false
                guard let d = d else { errMsg = "取位置失败"; return }
                func num(_ k: String) -> Double? {
                    if let v = d[k] as? Double { return v }
                    if let v = d[k] as? Int { return Double(v) }
                    if let v = d[k] as? String { return Double(v) }
                    return nil
                }
                address = (d["address"] as? String) ?? "未知位置"
                city = (d["city"] as? String) ?? ""
                gpsTime = (d["gpsTime"] as? String) ?? ""
                if let sp = num("speed") { speed = String(format: "%.0f", sp) }

                let lat = num("lat") ?? num("latitude") ?? 0
                let lng = num("lng") ?? num("lon") ?? num("longitude") ?? 0
                guard lat != 0, lng != 0 else { errMsg = "坐标为空"; return }
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                pin = CarLocation(coord: coord)
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
            }
        }
    }

    private func openAMap(_ c: CLLocationCoordinate2D) {
        // 1) 优先高德 App
        let amap = "iosamap://path?sourceApplication=CarApp&dlat=\(c.latitude)&dlon=\(c.longitude)&dname=车辆位置&dev=0&t=0"
        if let u = URL(string: amap), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
            return
        }
        // 2) 退回 Apple 地图
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = "车辆位置"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
