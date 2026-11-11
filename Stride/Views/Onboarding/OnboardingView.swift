import SwiftUI
import SwiftData
import StrideCore

struct OnboardingView: View {
    let done: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(HealthImporter.self) private var importer
    @Query private var activities: [Activity]
    @AppStorage(Keys.maxHR) private var maxHR = 0.0
    @AppStorage(Keys.restHR) private var restHR = 0.0
    @AppStorage(Keys.units) private var units = "metric"
    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                welcome.tag(0)
                health.tag(1)
                profile.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.snappy, value: page)
        }
        .background(DS.canvas)
        .interactiveDismissDisabled()
    }

    private func page(icon: String, tint: Color, title: String, text: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon).font(.system(size: 64, weight: .semibold)).foregroundStyle(tint.gradient)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            content()
            Spacer()
            Spacer()
        }
        .padding(28)
    }

    private var welcome: some View {
        page(icon: "figure.run.circle.fill", tint: DS.accent, title: "Welcome to Stride",
             text: "Deep analysis of every workout — splits, heart-rate zones, grade-adjusted pace, fitness & fatigue, personal records and your own segments.") {
            VStack(alignment: .leading, spacing: 12) {
                feature("waveform.path.ecg", "Linked charts for pace, heart rate, elevation, cadence and power")
                feature("trophy.fill", "Automatic personal records, race predictions and segment leaderboards")
                feature("lock.fill", "Private — your data never leaves this iPhone")
            }
            .padding(.top, 8)
            Button("Get started") { page = 1 }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var health: some View {
        page(icon: "heart.text.square.fill", tint: .red, title: "Connect Apple Health",
             text: "Stride reads your workouts with their routes, heart rate, running dynamics, cadence and power. It never writes to Health.") {
            if importer.isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: importer.progress)
                    Text(importer.status).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            } else if !activities.isEmpty {
                Label("\(activities.count) activities ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                Button("Continue") { page = 2 }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button {
                    Task { await importer.importNew(into: context); if !activities.isEmpty { page = 2 } }
                } label: { Label("Connect Apple Health", systemImage: "heart.fill") }
                .buttonStyle(.borderedProminent).controlSize(.large)
                if let e = importer.errorMessage { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                #if DEBUG
                Button("Try with demo data") { DemoData.insert(into: context); page = 2 }
                #endif
                Button("Skip for now") { page = 2 }.foregroundStyle(.secondary)
            }
        }
    }

    private var profile: some View {
        page(icon: "person.crop.circle.badge.checkmark", tint: .blue, title: "Your profile",
             text: "Heart-rate zones and Relative Effort are personal. We pre-filled what Apple Health knows — adjust if needed.") {
            VStack(spacing: 12) {
                Stepper(value: Binding { Profile.maxHR } set: { maxHR = $0 }, in: 140...220) {
                    LabeledContent("Maximum heart rate", value: "\(Int(Profile.maxHR)) bpm")
                }
                Stepper(value: Binding { Profile.restHR } set: { restHR = $0 }, in: 35...100) {
                    LabeledContent("Resting heart rate", value: "\(Int(Profile.restHR)) bpm")
                }
                Picker("Units", selection: $units) { Text("Metric").tag("metric"); Text("Imperial").tag("imperial") }
                    .pickerStyle(.segmented)
            }
            .padding()
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
            Button("Start exploring") {
                Maintenance.recomputeLoads(context)
                done()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon).foregroundStyle(DS.accent).frame(width: 26) }
    }
}
