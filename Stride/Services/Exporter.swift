import Foundation
import SwiftUI
import UniformTypeIdentifiers
import StrideCore

/// A file generated lazily when the user actually shares it.
struct ExportFile: Transferable {
    let filename: String
    let type: UTType
    let make: @Sendable () -> String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try file.make().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

enum Exporter {
    static func gpx(_ a: Activity) -> ExportFile {
        let name = a.name, type = a.sport.gpxType, pts = a.route, hr = a.heartRates
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return ExportFile(filename: "\(safe).gpx", type: .xml) {
            GPX.document(name: name, type: type, points: pts, heartRate: hr)
        }
    }

    static func csv(_ activities: [Activity]) -> ExportFile {
        let rows: [String] = activities.map { a in
            let fields: [String] = [
                ISO8601DateFormatter().string(from: a.start), a.sport.label, "\"\(a.name.replacingOccurrences(of: "\"", with: "\"\""))\"",
                String(format: "%.0f", a.distance), String(format: "%.0f", a.duration), String(format: "%.0f", a.activeTime),
                String(format: "%.0f", a.elevationGain), a.avgHR.map { String(format: "%.0f", $0) } ?? "",
                a.maxHR.map { String(format: "%.0f", $0) } ?? "", String(format: "%.0f", a.energy),
                String(format: "%.0f", a.relativeEffort), a.avgCadence.map { String(format: "%.0f", $0) } ?? "",
                a.avgPower.map { String(format: "%.0f", $0) } ?? "", a.rpe.map(String.init) ?? "", a.gear?.name ?? "",
            ]
            return fields.joined(separator: ",")
        }
        let header = "start,sport,name,distance_m,elapsed_s,moving_s,elevation_m,avg_hr,max_hr,kcal,relative_effort,avg_cadence,avg_power,rpe,gear"
        let text = ([header] + rows).joined(separator: "\n")
        return ExportFile(filename: "stride-activities.csv", type: .commaSeparatedText) { text }
    }
}
