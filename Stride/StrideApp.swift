import SwiftUI
import SwiftData

@main
struct StrideApp: App {
    @State private var importer = HealthImporter()
    @State private var records = RecordStore()
    private let container = StrideStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(importer)
                .environment(records)
                .tint(DS.accent)
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable { case home, training, explore, records, you }

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthImporter.self) private var importer
    @AppStorage(Keys.hasOnboarded) private var hasOnboarded = false
    @AppStorage(Keys.units) private var units = "metric"
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(AppTab.home)
            TrainingView()
                .tabItem { Label("Training", systemImage: "waveform.path.ecg") }.tag(AppTab.training)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "map.fill") }.tag(AppTab.explore)
            RecordsView()
                .tabItem { Label("Records", systemImage: "trophy.fill") }.tag(AppTab.records)
            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }.tag(AppTab.you)
        }
        .id(units)   // re-render all formatted values when units change
        .task {
            #if DEBUG
            applyDebugLaunchArguments()
            #endif
            Maintenance.backfill(context)
            importer.startObserving(context.container)
        }
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            OnboardingView { hasOnboarded = true }
        }
    }
}

#if DEBUG
extension RootView {
    /// `-demoData` seeds demo activities and skips onboarding; `-tab training|explore|records|you` picks a tab.
    func applyDebugLaunchArguments() {
        let args = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            hasOnboarded = true
            if ((try? context.fetchCount(FetchDescriptor<Activity>())) ?? 0) == 0 { DemoData.insert(into: context) }
        }
        switch args.string(forKey: "tab") {
        case "training": tab = .training
        case "explore": tab = .explore
        case "records": tab = .records
        case "you": tab = .you
        default: break
        }
    }
}
#endif
