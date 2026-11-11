import SwiftUI
import SwiftData
import StrideCore

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthImporter.self) private var importer
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @AppStorage(Keys.maxHR) private var maxHR = 0.0
    @AppStorage(Keys.restHR) private var restHR = 0.0
    @AppStorage(Keys.units) private var units = "metric"
    @AppStorage(Keys.autoImport) private var autoImport = true
    @State private var confirmDelete = false
    @State private var recompute: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        total("\(activities.count)", "activities")
                        total(String(format: "%.0f", Fmt.distanceValue(activities.reduce(0) { $0 + $1.distance })), Fmt.distanceLabel)
                        total(String(format: "%.0f", activities.reduce(0) { $0 + $1.activeTime } / 3600), "hours")
                        total(String(format: "%.0f", Fmt.elevationValue(activities.reduce(0) { $0 + $1.elevationGain })), "\(Fmt.elevationLabel) climbed")
                    }
                    .padding(.vertical, 6)
                } header: { Text("All time") }

                Section {
                    Stepper(value: maxHRBinding, in: 140...220) {
                        LabeledContent("Maximum heart rate", value: "\(Int(Profile.maxHR)) bpm")
                    }
                    Stepper(value: restHRBinding, in: 35...100) {
                        LabeledContent("Resting heart rate", value: "\(Int(Profile.restHR)) bpm")
                    }
                    ZonesPreview(zones: Profile.zones)
                    Button {
                        Task { await importer.refreshProfile(); maxHR = 0; scheduleRecompute() }
                    } label: { Label("Fill from Apple Health", systemImage: "heart.text.square") }
                } header: {
                    Text("Heart rate")
                } footer: {
                    Text("Zones and Relative Effort use heart-rate reserve (Karvonen). Maximum heart rate defaults to 208 − 0.7 × age when your birth year is in Apple Health.")
                }

                Section("Preferences") {
                    Picker("Units", selection: $units) {
                        Text("Metric (km, m)").tag("metric")
                        Text("Imperial (mi, ft)").tag("imperial")
                    }
                    NavigationLink { GearListView() } label: { Label("Gear", systemImage: "shoeprints.fill") }
                }

                Section {
                    Button {
                        Task { await importer.importNew(into: context) }
                    } label: {
                        Label(HealthImporter.wasAuthorized ? "Sync now" : "Connect Apple Health", systemImage: "heart.fill")
                    }
                    .disabled(importer.isImporting)
                    Toggle("Sync automatically", isOn: $autoImport)
                    if importer.isImporting { ProgressView(value: importer.progress) }
                    if !importer.status.isEmpty { Text(importer.status).font(.footnote).foregroundStyle(.secondary) }
                    if let e = importer.errorMessage { Text(e).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Stride reads workouts, routes, heart rate, running dynamics, cadence and power. Everything stays on this device.")
                }

                Section("Data") {
                    if !activities.isEmpty {
                        ShareLink(item: Exporter.csv(activities), preview: SharePreview("stride-activities.csv")) {
                            Label("Export all activities (CSV)", systemImage: "tablecells")
                        }
                    }
                    #if DEBUG
                    Button { DemoData.insert(into: context) } label: { Label("Load demo data", systemImage: "wand.and.stars") }
                    #endif
                    Button("Delete all activities", role: .destructive) { confirmDelete = true }.disabled(activities.isEmpty)
                }
            }
            .navigationTitle("You")
            .confirmationDialog("Delete all imported activities?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    try? context.delete(model: SegmentEffort.self)
                    try? context.delete(model: Activity.self)
                }
            } message: {
                Text("Removes Stride's copy only. Segments, gear and goals are kept. Apple Health is not changed.")
            }
        }
    }

    private var maxHRBinding: Binding<Double> {
        Binding { Profile.maxHR } set: { maxHR = $0; scheduleRecompute() }
    }
    private var restHRBinding: Binding<Double> {
        Binding { Profile.restHR } set: { restHR = $0; scheduleRecompute() }
    }

    /// Debounced: refresh Relative Effort after the user stops tapping.
    private func scheduleRecompute() {
        recompute?.cancel()
        recompute = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            Maintenance.recomputeLoads(context)
        }
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ZonesPreview: View {
    let zones: HeartZones

    var body: some View {
        VStack(spacing: 4) {
            ForEach((0..<5).reversed(), id: \.self) { z in
                let r = zones.range(of: z)
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(DS.zoneColors[z]).frame(width: 6, height: 16)
                    Text("Zone \(z + 1) · \(HeartZones.names[z])").font(.caption)
                    Spacer()
                    Text("\(Int(r.lowerBound))–\(Int(r.upperBound)) bpm").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Gear

extension Gear {
    var totalKm: Double { startingKm + activities.reduce(0) { $0 + $1.distance } / 1000 }
    var needsReplacing: Bool { !retired && retireAtKm > 0 && totalKm >= retireAtKm }
    var icon: String { kindRaw == "bike" ? "bicycle" : "shoeprints.fill" }
}

struct GearListView: View {
    @Query(sort: \Gear.createdAt) private var gear: [Gear]
    @Environment(\.modelContext) private var context
    @State private var editing: Gear?
    @State private var adding = false

    var body: some View {
        List {
            if gear.isEmpty {
                Text("Track shoe and bike mileage. New activities are assigned automatically to the default gear for their sport.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(gear) { g in
                Button { editing = g } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(g.name, systemImage: g.icon).font(.subheadline.weight(.semibold))
                            if g.retired { MetricPill(icon: "archivebox", text: "Retired") }
                            if g.needsReplacing { MetricPill(icon: "exclamationmark.triangle.fill", text: "Time to replace", tint: .orange) }
                            Spacer()
                            Text(String(format: "%.0f %@", Fmt.distanceValue(g.totalKm * 1000), Fmt.distanceLabel)).monospacedDigit()
                        }
                        if g.retireAtKm > 0 {
                            ProgressView(value: min(g.totalKm / g.retireAtKm, 1))
                                .tint(g.needsReplacing ? .orange : .green)
                        }
                        Text("\(g.activities.count) activities\(g.defaultSportRaw.flatMap { Sport(rawValue: $0) }.map { " · default for \($0.label.lowercased())s" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { $0.forEach { context.delete(gear[$0]) } }
        }
        .navigationTitle("Gear")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { GearEditor(gear: nil) }
        .sheet(item: $editing) { GearEditor(gear: $0) }
    }
}

struct GearEditor: View {
    let gear: Gear?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = "shoes"
    @State private var defaultSport: Sport? = .run
    @State private var retireAt = 700.0
    @State private var starting = 0.0
    @State private var retired = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (for example, Pegasus 41)", text: $name)
                Picker("Type", selection: $kind) {
                    Label("Shoes", systemImage: "shoeprints.fill").tag("shoes")
                    Label("Bike", systemImage: "bicycle").tag("bike")
                }
                Picker("Default for", selection: $defaultSport) {
                    Text("None").tag(Sport?.none)
                    ForEach(Sport.allCases.filter { $0.gearKind == kind }) { Text($0.label).tag(Sport?.some($0)) }
                }
                Stepper(value: $retireAt, in: 0...50_000, step: 50) {
                    LabeledContent("Replace after", value: retireAt > 0 ? "\(Int(retireAt)) km" : "Never")
                }
                Stepper(value: $starting, in: 0...50_000, step: 10) {
                    LabeledContent("Starting distance", value: "\(Int(starting)) km")
                }
                if gear != nil { Toggle("Retired", isOn: $retired) }
            }
            .navigationTitle(gear == nil ? "New Gear" : "Edit Gear")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: kind) { defaultSport = kind == "bike" ? .ride : .run; retireAt = kind == "bike" ? 0 : 700 }
            .onAppear {
                if let g = gear {
                    name = g.name; kind = g.kindRaw; defaultSport = g.defaultSportRaw.flatMap { Sport(rawValue: $0) }
                    retireAt = g.retireAtKm; starting = g.startingKm; retired = g.retired
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let g = gear ?? Gear(name: name, kindRaw: kind, defaultSportRaw: nil, retireAtKm: retireAt)
        if gear == nil {
            context.insert(g)
            // Assign existing activities of the default sport that have no gear yet.
            if let s = defaultSport {
                let raw = s.rawValue
                let acts = (try? context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.sportRaw == raw }))) ?? []
                acts.filter { $0.gear == nil }.forEach { $0.gear = g }
            }
        }
        g.name = name; g.kindRaw = kind; g.defaultSportRaw = defaultSport?.rawValue
        g.retireAtKm = retireAt; g.startingKm = starting; g.retired = retired
    }
}
