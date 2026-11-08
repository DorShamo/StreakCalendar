import SwiftUI
import AppKit

// MARK: - Dates

enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = 1 // Sunday
        return c
    }()

    static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }
    static func date(_ k: String) -> Date? { keyFormatter.date(from: k) }
    static func add(_ n: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    static func startOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }
}

// MARK: - Saved data

struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var days: [String]
}

final class Store: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var habits: [Habit] {
        didSet { persist() }
    }
    @Published var selectedID: UUID {
        didSet { defaults.set(selectedID.uuidString, forKey: "selectedHabit") }
    }

    init() {
        var loaded: [Habit] = []
        if let data = defaults.data(forKey: "habits"),
           let decoded = try? JSONDecoder().decode([Habit].self, from: data) {
            loaded = decoded
        }
        if loaded.isEmpty {
            // Carry over the habit from the first version of the app
            loaded = [Habit(name: defaults.string(forKey: "habitName") ?? "",
                            days: defaults.stringArray(forKey: "doneDays") ?? [])]
        }
        habits = loaded
        let saved = defaults.string(forKey: "selectedHabit").flatMap { UUID(uuidString: $0) }
        selectedID = loaded.first(where: { $0.id == saved })?.id ?? loaded[0].id
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(habits) {
            defaults.set(data, forKey: "habits")
        }
    }

    private var index: Int { habits.firstIndex { $0.id == selectedID } ?? 0 }

    var name: String {
        get { habits[index].name }
        set { habits[index].name = newValue }
    }

    var days: Set<String> { Set(habits[index].days) }

    func label(_ h: Habit) -> String {
        let n = h.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Untitled habit" : n
    }

    var currentLabel: String { label(habits[index]) }

    func toggle(_ k: String) {
        var s = days
        if s.contains(k) { s.remove(k) } else { s.insert(k) }
        habits[index].days = s.sorted()
    }

    func addHabit() {
        let h = Habit(name: "", days: [])
        habits.append(h)
        selectedID = h.id
    }

    func deleteCurrent() {
        guard habits.count > 1 else { return }
        let i = index
        habits.remove(at: i)
        selectedID = habits[max(0, i - 1)].id
    }

    func clearCurrent() {
        habits[index].days = []
    }

    func currentStreak(today: Date) -> Int {
        var d = today
        if !days.contains(Day.key(d)) { d = Day.add(-1, to: d) }
        var count = 0
        while days.contains(Day.key(d)) {
            count += 1
            d = Day.add(-1, to: d)
        }
        return count
    }

    func longestStreak() -> Int {
        var best = 0, run = 0
        var prev: Date? = nil
        for k in days.sorted() {
            guard let d = Day.date(k) else { continue }
            if let p = prev, Day.key(Day.add(1, to: p)) == k { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    func count(inMonth month: Date) -> Int {
        let prefix = String(Day.key(month).prefix(7))
        return days.filter { $0.hasPrefix(prefix) }.count
    }
}

// MARK: - Look

extension Color {
    static let streak = Color(red: 0.18, green: 0.55, blue: 0.34)
}

// MARK: - Views

struct StatView: View {
    let value: Int
    let label: String
    var highlight = false

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(highlight ? .streak : .primary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct DayCell: View {
    let day: Int
    let done: Bool
    let isToday: Bool
    let future: Bool
    let linkLeft: Bool
    let linkRight: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            // chain links between consecutive marked days
            HStack(spacing: 0) {
                Rectangle().fill(linkLeft ? Color.streak : Color.clear).frame(height: 8)
                Rectangle().fill(linkRight ? Color.streak : Color.clear).frame(height: 8)
            }
            Button(action: action) {
                Text("\(day)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(done ? .white : .primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(done ? Color.streak : Color.clear))
                    .overlay(Circle().stroke(isToday ? Color.streak : Color.clear, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(future)
            .opacity(future ? 0.35 : 1)
            .help(done ? "Done — click to unmark" : "Click to mark as done")
        }
        .frame(height: 40)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var today = Day.cal.startOfDay(for: Date())
    @State private var month = Day.startOfMonth(Date())
    @State private var confirmClear = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var isCurrentMonth: Bool { Day.startOfMonth(today) == month }

    private var leadingBlanks: Int {
        (Day.cal.component(.weekday, from: month) - Day.cal.firstWeekday + 7) % 7
    }

    private var daysInMonth: Int {
        Day.cal.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private func date(for day: Int) -> Date { Day.add(day - 1, to: month) }

    private func isDone(_ day: Int) -> Bool {
        guard day >= 1 && day <= daysInMonth else { return false }
        return store.days.contains(Day.key(date(for: day)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TRACKING")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        ForEach(store.habits) { h in
                            Button {
                                store.selectedID = h.id
                            } label: {
                                if h.id == store.selectedID {
                                    Label(store.label(h), systemImage: "checkmark")
                                } else {
                                    Text(store.label(h))
                                }
                            }
                        }
                        Divider()
                        Button("New habit") { newHabit() }
                        Button("Delete this habit…") { confirmDelete = true }
                            .disabled(store.habits.count < 2)
                    } label: {
                        Text("Habits (\(store.habits.count))")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                TextField("Name your habit", text: $store.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .focused($nameFocused)
            }
            .alert("Delete \u{201C}\(store.currentLabel)\u{201D}?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteCurrent() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This habit and all its marked days will be removed. It can't be undone.")
            }

            HStack(spacing: 0) {
                StatView(value: store.currentStreak(today: today), label: "Current streak", highlight: true)
                Divider()
                StatView(value: store.longestStreak(), label: "Longest")
                Divider()
                StatView(value: store.count(inMonth: month), label: "This month")
                Divider()
                StatView(value: store.days.count, label: "Total days")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))

            VStack(spacing: 8) {
                HStack {
                    Text(Day.monthFormatter.string(from: month))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(isCurrentMonth)
                }

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdays, id: \.self) { w in
                        Text(w)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 6)
                    }
                    ForEach(0..<leadingBlanks, id: \.self) { i in
                        Color.clear.frame(height: 40).id("blank\(i)")
                    }
                    ForEach(1...daysInMonth, id: \.self) { day in
                        let d = date(for: day)
                        let col = (leadingBlanks + day - 1) % 7
                        let done = isDone(day)
                        DayCell(
                            day: day,
                            done: done,
                            isToday: d == today,
                            future: d > today,
                            linkLeft: done && col > 0 && isDone(day - 1),
                            linkRight: done && col < 6 && isDone(day + 1),
                            action: { store.toggle(Day.key(d)) }
                        )
                    }
                }
                .id(month)

                Text("Click a day to mark that you did it. Days in a row link into a chain.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if !isCurrentMonth {
                    Button("Back to today") { month = Day.startOfMonth(today) }
                }
                Spacer()
                Button("Clear all days…") { confirmClear = true }
            }
            .font(.system(size: 12))
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 400, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            today = Day.cal.startOfDay(for: Date())
        }
        .alert("Clear all marked days?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { store.clearCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every day you've marked. It can't be undone.")
        }
    }

    private func newHabit() {
        store.addHabit()
        month = Day.startOfMonth(today)
        DispatchQueue.main.async { nameFocused = true }
    }

    private func shiftMonth(_ n: Int) {
        if let m = Day.cal.date(byAdding: .month, value: n, to: month) {
            if n > 0 && m > Day.startOfMonth(today) { return }
            month = m
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct StreakCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Streak Calendar") {
            ContentView().environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Habit") { store.addHabit() }
                    .keyboardShortcut("n")
            }
        }
    }
}
