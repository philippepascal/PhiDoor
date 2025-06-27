//
//  OpenDoorIntent.swift
//  PhiDoor
//
//  Created by Philippe Pascal on 2025/6/26.
//

import AppIntents

struct OpenDoorIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Door"

    func perform() async throws -> some IntentResult {
        DoorAccessManager.shared.openDoor()
        return .result()
    }
}
