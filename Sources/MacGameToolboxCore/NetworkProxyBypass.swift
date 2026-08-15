import Foundation

public struct ProxyBypassSnapshot: Codable, Equatable, Sendable {
    public var services: [String: [String]]

    public init(services: [String: [String]] = [:]) {
        self.services = services
    }
}

public struct ProxyBypassAssignment: Equatable, Sendable {
    public var service: String
    public var domains: [String]

    public init(service: String, domains: [String]) {
        self.service = service
        self.domains = domains
    }
}

public struct ProxyBypassApplyPlan: Equatable, Sendable {
    public var snapshot: ProxyBypassSnapshot
    public var assignments: [ProxyBypassAssignment]

    public init(snapshot: ProxyBypassSnapshot, assignments: [ProxyBypassAssignment]) {
        self.snapshot = snapshot
        self.assignments = assignments
    }
}

public enum NetworkProxyBypass {
    public static let emptyToken = "Empty"

    public static func enabledServices(from listOutput: String) -> [String] {
        var lines = listOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.first?.localizedCaseInsensitiveContains("asterisk") == true {
            lines.removeFirst()
        }
        return lines.filter { !$0.hasPrefix("*") }
    }

    public static func parseBypassDomains(_ output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("** error") { return [] }
        if lowered.contains("aren't any bypass") { return [] }
        return trimmed.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
    }

    public static func merging(existing: [String], extra: [String]) -> [String] {
        var seen = Set(existing.map { $0.lowercased() })
        var result = existing
        for domain in extra where seen.insert(domain.lowercased()).inserted {
            result.append(domain)
        }
        return result
    }

    public static func removing(_ existing: [String], managed: [String]) -> [String] {
        let blocked = Set(managed.map { $0.lowercased() })
        return existing.filter { !blocked.contains($0.lowercased()) }
    }

    public static func setArguments(service: String, domains: [String]) -> [String] {
        ["-setproxybypassdomains", service] + (domains.isEmpty ? [emptyToken] : domains)
    }

    public static func planApply(
        currentByService: [String: [String]],
        existingSnapshot: ProxyBypassSnapshot?,
        extra: [String]
    ) -> ProxyBypassApplyPlan {
        var snapshotServices = existingSnapshot?.services ?? [:]
        var assignments: [ProxyBypassAssignment] = []
        for service in currentByService.keys.sorted() {
            let current = currentByService[service] ?? []
            if snapshotServices[service] == nil {
                snapshotServices[service] = current
            }
            let merged = merging(existing: current, extra: extra)
            if merged != current {
                assignments.append(ProxyBypassAssignment(service: service, domains: merged))
            }
        }
        return ProxyBypassApplyPlan(snapshot: ProxyBypassSnapshot(services: snapshotServices), assignments: assignments)
    }

    public static func planRestore(
        snapshot: ProxyBypassSnapshot?,
        currentByService: [String: [String]],
        managed: [String]
    ) -> [ProxyBypassAssignment] {
        if let snapshot {
            return snapshot.services.keys.sorted().map { service in
                ProxyBypassAssignment(service: service, domains: snapshot.services[service] ?? [])
            }
        }
        return currentByService.keys.sorted().compactMap { service in
            let current = currentByService[service] ?? []
            let restored = removing(current, managed: managed)
            guard restored != current else { return nil }
            return ProxyBypassAssignment(service: service, domains: restored)
        }
    }
}
