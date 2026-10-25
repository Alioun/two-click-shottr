import Foundation
import ScreenCaptureKit

struct CaptureFailure: LocalizedError {
    enum Kind { case general, screenRecordingDenied }
    enum Stage { case discovery, geometry, acquisition, encoding, handoff }
    let message: String
    var kind: Kind = .general
    var stage: Stage = .handoff
    var underlying: NSError?
    var errorDescription: String? { message }
    var isCaptureFailure: Bool { stage != .encoding && stage != .handoff }

    static func native(_ error: Error, stage: Stage) -> Error {
        if error is CancellationError { return error }
        let cause = error as NSError
        var candidate: NSError? = cause
        for _ in 0..<8 {
            guard let current = candidate else { break }
            if current.domain == SCStreamErrorDomain {
                if current.code == SCStreamError.Code.userStopped.rawValue { return CancellationError() }
                if current.code == SCStreamError.Code.userDeclined.rawValue {
                    return CaptureFailure(
                        message: "Screen Recording permission is required.",
                        kind: .screenRecordingDenied, stage: stage, underlying: cause)
                }
            }
            candidate = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return CaptureFailure(
            message: "\(stage): \(cause.localizedDescription) [\(cause.domain) \(cause.code)]",
            stage: stage, underlying: cause)
    }
}
