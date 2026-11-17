//
//  AppIdentifiers.swift
//  rootshell
//
//  Identifiers that must track a contributor's own Apple Developer team and
//  org identifier (see Configuration/Identity.xcconfig). Each value is signed
//  into the bundle via an Info.plist key, so it stays in lockstep with the
//  entitlements the process actually holds.
//
//  Compiled into every target that needs it, including the extensions -- see
//  the membershipExceptions in project.pbxproj. The one target it can't reach
//  is rootshell-helper, whose source tree is separate; it carries its own
//  equivalent lookup.
//

import Foundation
import Security

nonisolated enum AppIdentifiers {
    /// The app group shared with the VPN extension, the widget, and the
    /// helper. Not region-specific: those targets sign against this group even
    /// in a China build, where the app and the push service use the
    /// `.cn`-suffixed `RootshellAppGroup` instead.
    static let defaultAppGroupID: String = plist("RootshellDefaultAppGroup") ?? "group.com.kk2.ghostty"

    #if SIDELOAD
    /// A sideloading tool re-signs the app under its own team, which changes
    /// the team prefix of the keychain group, so ask the keychain which group
    /// the process was actually signed with.
    static let keychainAccessGroup: String = signedKeychainAccessGroup()
        ?? plist("RootshellKeychainAccessGroup") ?? "D97ZME3ET2.com.kk2.ghostty-ios"
    #else
    static let keychainAccessGroup: String = plist("RootshellKeychainAccessGroup") ?? "D97ZME3ET2.com.kk2.ghostty-ios"
    #endif

    static let iCloudContainerID: String = plist("RootshellICloudContainer") ?? "iCloud.rootshell"

    #if SIDELOAD
    /// The access group the keychain gives an item stored without one: the
    /// first entry of the signed `keychain-access-groups`.
    private static func signedKeychainAccessGroup() -> String? {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "rootshell.keychain-group-probe",
            kSecAttrAccount as String: "rootshell.keychain-group-probe",
        ]
        var query = probe
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var item = query
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessGroup as String] as? String
    }
    #endif

    private static func plist(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
