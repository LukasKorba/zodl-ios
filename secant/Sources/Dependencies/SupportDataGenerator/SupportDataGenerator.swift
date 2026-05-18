//
//  SupportDataGenerator.swift
//  secant
//
//  Created by Michal Fousek on 28.02.2023.
//

@preconcurrency import AVFoundation
import Foundation
import LocalAuthentication
import UIKit

struct SupportData: Equatable {
    let toAddress: String
    let subject: String
    var message: String
}

enum SupportDataGenerator {
    enum Constants {
        static let email = "support@zodl.com"
        static let subject = "Zodl"
        static let subjectPPE = "TEX Transaction Error"
    }
    
    static func generate(_ prefix: String? = nil) -> SupportData {
        let items: [SupportDataGeneratorItem] = [
            TimeItem(),
            AppVersionItem(),
            SystemVersionItem(),
            DeviceModelItem(),
            LocaleItem(),
            FreeDiskSpaceItem(),
            PermissionsItems()
        ]

        let message = items
            .map { $0.generate() }
            .flatMap { $0 }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")

        if let prefix {
            let finalMessage = "\(prefix)\n\(message)"
            
            return SupportData(toAddress: Constants.email, subject: Constants.subject, message: finalMessage)
        } else {
            return SupportData(toAddress: Constants.email, subject: Constants.subject, message: message)
        }
    }

    static func generateOSStatusError(osStatus: OSStatus) -> SupportData {
        let data = SupportDataGenerator.generate()
        
        let message =
        """
        OSStatus: \(osStatus)
        \(data.message)
        """
        
        return SupportData(toAddress: Constants.email, subject: Constants.subjectPPE, message: message)
    }
}

private protocol SupportDataGeneratorItem {
    func generate() -> [(String, String)]
}

private struct TimeItem: SupportDataGeneratorItem {
    let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd hh:mm:ss a ZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US")
    }

    func generate() -> [(String, String)] {
        return [("Current time", dateFormatter.string(from: Date()))]
    }
}

private struct AppVersionItem: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        let bundle = Bundle.main
        guard let infoDict = bundle.infoDictionary else { return [("App version", "Unknown")] }

        var data: [(String, String)] = []
        if let bundleIdentifier = bundle.bundleIdentifier {
            data.append(("App identifier", bundleIdentifier))
        }

        if let build = infoDict["CFBundleVersion"] as? String, let version = infoDict["CFBundleShortVersionString"] as? String {
            data.append(("App version", "\(version) (\(build))"))
        } else {
            data.append(("App version", "Unknown"))
        }

        return data
    }
}

private struct SystemVersionItem: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return [("iOS version", "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")]
    }
}

private struct DeviceModelItem: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        var systemInfo = utsname()
        uname(&systemInfo)
        var readModel: String?
        withUnsafePointer(to: &systemInfo.machine.0) { charPointer in
            readModel = String(cString: charPointer, encoding: .ascii)
        }

        return [("Device", readModel ?? "Unknown")]
    }
}

private struct LocaleItem: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        let locale = Locale.current

        return [
            ("Locale", locale.identifier),
            ("Currency grouping separator", "'\(locale.groupingSeparator ?? "Unknown")'"),
            ("Currency decimal separator", "'\(locale.decimalSeparator ?? "Unknown")'")
        ]
    }
}

private struct FreeDiskSpaceItem: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        let freeDiskSpace: String

        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let freeSpace = values.volumeAvailableCapacityForImportantUsage {
                freeDiskSpace = "\(freeSpace / 1024 / 1024) MB"
            } else {
                freeDiskSpace = "Unknown"
            }
        } catch {
            LoggerProxy.debug("Can't get free disk space: \(error)")
            freeDiskSpace = "Unknown"
        }

        return [("Usable storage", freeDiskSpace)]
    }
}

private struct PermissionsItems: SupportDataGeneratorItem {
    func generate() -> [(String, String)] {
        let cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

        let bioAuthContext = LAContext()
        let biometricAuthAvailable = bioAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        return [
            ("Permissions", ""),
            ("Camera access", cameraAuthorized ? "Yes" : "No"),
            ("FaceID available", biometricAuthAvailable && bioAuthContext.biometryType == .faceID ? "Yes" : "No"),
            ("TouchID available", biometricAuthAvailable && bioAuthContext.biometryType == .touchID ? "Yes" : "No")
        ]
    }
}
