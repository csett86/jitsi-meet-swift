//
//  FixtureLoader.swift
//  JitsiSignalingTests
//
//  Created for Jitsi Native macOS Client
//

import Foundation

class FixtureLoader {
    
    static func loadFixture(named name: String) -> [String: Any]? {
        let bundle = Bundle(for: FixtureLoader.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("Error loading fixture \(name): \(error)")
            return nil
        }
    }
    
    static func loadFixtureArray(named name: String) -> [[String: Any]]? {
        let bundle = Bundle(for: FixtureLoader.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            print("Error loading fixture \(name): \(error)")
            return nil
        }
    }
    
    static func loadFixtureString(named name: String) -> String? {
        let bundle = Bundle(for: FixtureLoader.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            return nil
        }
        
        do {
            return try String(contentsOf: url)
        } catch {
            print("Error loading fixture \(name): \(error)")
            return nil
        }
    }
}
