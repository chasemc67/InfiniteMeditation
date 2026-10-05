//
//  SessionHistoryView.swift
//  Shared by the iPhone and Apple Watch apps.
//

import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var store: SessionHistoryStore
    var showsDoneButton: Bool
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "clock")
                } description: {
                    Text("Completed meditations appear here, newest first.")
                }
            } else {
                List {
                    Section {
                    ForEach(store.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(TimeFormat.clock(entry.duration))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete(perform: delete)
                    } footer: {
                        Text("Duration leaves out pauses. Deleting a row does not remove it from Apple Health.")
                    }
                }
            }
        }
        .navigationTitle("History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { store.entries[$0].id }
        ids.forEach(onDelete)
    }
}
