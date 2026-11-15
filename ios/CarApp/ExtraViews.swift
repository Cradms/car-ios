import SwiftUI
import MapKit

// MARK: - 今日行车轨迹
struct TrackView: View {
    @State private var pts: [CLLocationCoordinate2D] = []
    @State private var loading = true
    @State private var err = ""

    var body: some View {
        ZStack {
            TrackMap(points: pts)
                .ignoresSafeArea(edges: .bottom)
            if loading {
                ProgressView("加载轨迹…")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if pts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 34)).foregroundColor(C.faint)
                    Text(err.isEmpty ? "今天还没有行车轨迹" : err)
                        .font(.system(size: 13)).foregroundColor(C.muted)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("今日行车轨迹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(C.blue)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        CarAPI.shared.trackPoints { p in
            pts = p.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
            if p.isEmpty { err = "" }
            loading = false
        }
    }
}

/// MKMapView 包装（iOS 16 没有 MapPolyline）
struct TrackMap: UIViewRepresentable {
    let points: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let v = MKMapView()
        v.delegate = context.coordinator
        v.showsUserLocation = false
        return v
    }

    func updateUIView(_ v: MKMapView, context: Context) {
        v.removeOverlays(v.overlays)
        v.removeAnnotations(v.annotations)
        guard points.count > 1 else {
            if let p = points.first {
                v.setRegion(MKCoordinateRegion(center: p, latitudinalMeters: 1200,
                                               longitudinalMeters: 1200), animated: true)
                v.addAnnotation(MKPointAnnotation.custom(p, "车辆"))
            }
            return
        }
        let line = MKPolyline(coordinates: points, count: points.count)
        v.addOverlay(line)
        let a = MKPointAnnotation.custom(points[0], "起点")
        let b = MKPointAnnotation.custom(points[points.count - 1], "终点")
        v.addAnnotations([a, b])
        v.setVisibleMapRect(line.boundingMapRect,
                            edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                            animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let l = overlay as? MKPolyline else { return MKOverlayRenderer() }
            let r = MKPolylineRenderer(polyline: l)
            r.strokeColor = UIColor(red: 47/255, green: 111/255, blue: 181/255, alpha: 1)
            r.lineWidth = 5
            r.lineCap = .round
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let id = "pin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.canShowCallout = true
            return v
        }
    }
}

extension MKPointAnnotation {
    static func custom(_ c: CLLocationCoordinate2D, _ title: String) -> MKPointAnnotation {
        let a = MKPointAnnotation()
        a.coordinate = c
        a.title = title
        return a
    }
}

// MARK: - 操作记录
struct HistoryView: View {
    @State private var rows: [[String: Any]] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if rows.isEmpty {
                Text("暂无控车记录").foregroundColor(C.muted)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 10) {
                        Image(systemName: icon((r["name"] as? String) ?? ""))
                            .font(.system(size: 15))
                            .foregroundColor(C.blue)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((r["name"] as? String) ?? "控车操作")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(C.txt)
                            Text((r["time"] as? String) ?? "")
                                .font(.system(size: 11)).foregroundColor(C.faint)
                        }
                        Spacer()
                        let st = (r["status"] as? String) ?? ""
                        Text(statusText(st))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor(st))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("操作记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(C.blue)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        CarAPI.shared.controlHistory { r in
            rows = r
            loading = false
        }
    }

    private func statusText(_ s: String) -> String {
        if s.isEmpty { return "" }
        if s == "1" || s.lowercased() == "true" || s == "成功" || s.lowercased() == "success" { return "成功" }
        if s == "0" || s.lowercased() == "false" { return "失败" }
        return s
    }

    private func statusColor(_ s: String) -> Color {
        let t = statusText(s)
        if t == "成功" { return C.green }
        if t == "失败" { return C.red }
        return C.muted
    }

    private func icon(_ name: String) -> String {
        if name.contains("锁") && name.contains("解") { return "lock.open" }
        if name.contains("锁") { return "lock.fill" }
        if name.contains("窗") { return "rectangle.split.3x1" }
        if name.contains("天窗") { return "sun.max" }
        if name.contains("空调") { return "snowflake" }
        if name.contains("发动机") || name.contains("启动") { return "power" }
        if name.contains("笛") { return "speaker.wave.2.fill" }
        if name.contains("灯") { return "lightbulb" }
        return "car"
    }
}

// MARK: - 全景照片
struct PhotoView: View {
    @State private var items: [[String: Any]] = []
    @State private var loading = true
    @State private var preview: String?

    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(.top, 60)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34)).foregroundColor(C.faint)
                    Text("车机还没上传全景照片")
                        .font(.system(size: 13)).foregroundColor(C.muted)
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        let url = (it["thumb"] as? String) ?? ""
                        Button { preview = (it["url"] as? String) ?? url } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: URL(string: url)) { ph in
                                    if let img = ph.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(C.bg)
                                            .overlay(ProgressView())
                                    }
                                }
                                .frame(height: 130)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text((it["time"] as? String) ?? "")
                                    .font(.system(size: 10.5)).foregroundColor(C.faint)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("全景照片")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { preview.map { URLBox(url: $0) } },
            set: { if $0 == nil { preview = nil } })) { box in
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: URL(string: box.url)) { ph in
                    if let img = ph.image {
                        img.resizable().scaledToFit()
                    } else { ProgressView() }
                }
            }
            .background(Color.black)
        }
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        CarAPI.shared.panorama { r in
            items = r
            loading = false
        }
    }
}

struct URLBox: Identifiable {
    let url: String
    var id: String { url }
}
