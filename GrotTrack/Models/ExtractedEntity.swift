import Foundation

enum EntityType: String, Codable, CaseIterable {
    case url
    case date
    case phoneNumber
    case address
    case personName
    case organizationName
    case issueKey       // JIRA-123, GH #42
    case filePath       // /path/to/file.swift
    case gitBranch      // feature/foo-bar
    case meetingLink    // zoom.us/j/*, meet.google.com/*
}

struct ExtractedEntity: Codable, Equatable {
    let type: EntityType
    let value: String
}
