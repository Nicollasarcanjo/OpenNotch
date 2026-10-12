import EventKit
import SwiftUI

final class CalendarManager: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.refresh()
            }
        }
    }

    /// Eventos de hoje que ainda não terminaram.
    func refresh() {
        guard status == .fullAccess else { return }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }
}

struct CalendarView: View {
    @EnvironmentObject var calendar: CalendarManager
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date(), format: .dateTime.weekday(.wide))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.red).textCase(.uppercase)
            Text(Date(), format: .dateTime.day().month(.wide))
                .font(.system(size: 20, weight: .semibold))

            switch calendar.status {
            case .fullAccess:
                if calendar.events.isEmpty {
                    Text("Sem mais eventos hoje").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(calendar.events.prefix(max(prefs.int(.calMaxEvents), 1)), id: \.eventIdentifier) { event in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.title ?? L("Evento")).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(event.isAllDay ? L("Dia inteiro")
                                     : event.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            case .notDetermined:
                Button("Mostrar eventos do calendário", action: calendar.requestAccess)
                    .font(.caption)
            default:
                Text("Sem acesso ao calendário. Libere em Ajustes do Sistema › Privacidade › Calendários.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { calendar.refresh() }
    }
}
