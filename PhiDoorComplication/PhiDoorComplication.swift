//
//  PhiDoorComplication.swift
//  PhiDoorComplication
//
//  Created by Philippe Pascal on 2025/6/26.
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct PhiDoorComplicationEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        Image(systemName: "key.fill")
            .resizable()
            .scaledToFit()
            .padding(6)
            .widgetURL(URL(string: "phidoor://open"))
    }
}

@main
struct PhiDoorComplication: Widget {
    let kind: String = "PhiDoorComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(watchOS 10.0, *) {
                PhiDoorComplicationEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                PhiDoorComplicationEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}
