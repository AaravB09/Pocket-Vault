import Foundation
import Combine

/// One point-in-time reading of a goal's balance. Recorded automatically
/// by `GoalStore.mutateActive` whenever `currentSavings` changes (i.e. on
/// every deposit), so the sequence of snapshots is effectively a balance
/// history — the same idea as an investment app logging a snapshot on
/// every price/holding change to plot a performance chart. See
/// SavingsTrendChart.swift for where this gets rendered.
public struct SavingsSnapshot: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var date: Date
    public var amount: Double
}

public struct Goal: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var title: String
    public var kindRaw: String
    public var targetAmount: Double
    public var currentSavings: Double
    public var targetDate: Date
    // nil = not shared. When set, this is the id of a row in Supabase's
    // shared_goals table — see SharedBudgetManager. Older saved goals
    // decode this as nil automatically since it's Optional.
    public var sharedGoalID: String? = nil
    // Balance-over-time log for the trend chart. Optional/defaulted so
    // goals saved before this field existed decode cleanly as [].
    public var history: [SavingsSnapshot] = []
    // Raw JSON for an AI-generated voxel sculpture unique to this goal's
    // own description (a bag of cat food, a guitar, a bike) — set only
    // when AIGoalBuilderService classifies the goal as .custom and
    // manages to describe a specific-enough shape for it. nil for every
    // fixed category (flight, car, furniture, etc.) and for goals saved
    // before this existed, both of which fall back to
    // GoalBuildLibrary's static, hand-built voxels for that GoalKind.
    var customVoxelBlueprintJSON: String? = nil
}

/// Source of truth for every goal the user is tracking simultaneously.
/// Every existing screen (BuildStudioView, CalendarView, SetupGoalView,
/// SavingsCoachView, AIChatView) is unchanged — they still just receive
/// Bindings/values for "the" goal, same as before. The only difference is
/// those bindings now route through here and point at whichever goal is
/// currently active, via `mutateActive`.
@MainActor
public final class GoalStore: ObservableObject {
    @Published public var goals: [Goal] = []
    @Published public var activeGoalID: UUID?

    private let defaults = UserDefaults.standard
    private let goalsKey: String
    private let activeGoalKey: String

    /// `namespace` isolates one account's (or one guest session's) goals
    /// from every other — see AuthManager.storageNamespace. Without this,
    /// signing out and continuing as a guest would load whatever goals
    /// the previous signed-in account had saved.
    public init(namespace: String) {
        goalsKey = "\(namespace)_pv_goals_v1"
        activeGoalKey = "\(namespace)_pv_activeGoalID_v1"
        load()
        if activeGoalID == nil {
            activeGoalID = goals.first?.id
        }
    }

    public var activeGoal: Goal? {
        if let id = activeGoalID, let match = goals.first(where: { $0.id == id }) {
            return match
        }
        return goals.first
    }

    private var activeIndex: Int? {
        guard let goal = activeGoal else { return nil }
        return goals.firstIndex(where: { $0.id == goal.id })
    }

    public func addGoal(title: String, kindRaw: String, targetAmount: Double, targetDate: Date, customVoxelBlueprintJSON: String? = nil) {
        var goal = Goal(title: title, kindRaw: kindRaw, targetAmount: targetAmount, currentSavings: 0, targetDate: targetDate, customVoxelBlueprintJSON: customVoxelBlueprintJSON)
        goal.history = [SavingsSnapshot(date: Date(), amount: 0)]
        goals.append(goal)
        activeGoalID = goal.id
        persist()
    }

    public func setActive(_ id: UUID) {
        guard goals.contains(where: { $0.id == id }) else { return }
        activeGoalID = id
        persist()
    }

    func removeGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
        if activeGoalID == id { activeGoalID = goals.first?.id }
        persist()
    }

    /// Central write path for every field on the active goal. Every
    /// Binding in MainTabView routes through this, so persistence happens
    /// automatically no matter which field changed or which screen changed it.
    func mutateActive(_ transform: (inout Goal) -> Void) {
        guard let idx = activeIndex else { return }
        let previousSavings = goals[idx].currentSavings
        transform(&goals[idx])
        // A changed balance is a new data point for the trend chart —
        // append it here, in the one place every write path funnels
        // through, rather than making each caller (deposits, imports,
        // future editors) remember to log it separately.
        if goals[idx].currentSavings != previousSavings {
            goals[idx].history.append(SavingsSnapshot(date: Date(), amount: goals[idx].currentSavings))
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(goals) {
            defaults.set(data, forKey: goalsKey)
        }
        defaults.set(activeGoalID?.uuidString, forKey: activeGoalKey)
    }

    private func load() {
        if let data = defaults.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([Goal].self, from: data) {
            goals = decoded
        }
        if let idString = defaults.string(forKey: activeGoalKey), let id = UUID(uuidString: idString) {
            activeGoalID = id
        }
    }
}
