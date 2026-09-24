import CodometerCore
import CoreGraphics
import Foundation

/// Displays for the selection and policy tests: a built-in main display, one to its left (negative origin) and one above.
enum Displays {
    static let mainID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    static let leftID = "11111111-2222-3333-4444-555555555555"
    static let aboveID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    static func id(_ raw: String) -> DisplayID {
        guard let id = try? DisplayID(raw) else { preconditionFailure("fixture display id \(raw) is invalid") }
        return id
    }

    static func display(_ raw: String, name: String, frame: CGRect, isMain: Bool = false, isBuiltIn: Bool = false) -> DisplayDescriptor {
        DisplayDescriptor(
            id: id(raw),
            name: name,
            frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 20),
            isMain: isMain,
            isBuiltIn: isBuiltIn,
            notch: nil
        )
    }

    /// Built-in main display at the origin, an external one to its left (negative origin) and one above.
    static let builtIn = display(mainID, name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isMain: true, isBuiltIn: true)
    static let left = display(leftID, name: "LG UltraFine", frame: CGRect(x: -2560, y: -200, width: 2560, height: 1440))
    static let above = display(aboveID, name: "Studio Display", frame: CGRect(x: 0, y: 982, width: 1512, height: 900))
    static let all = [builtIn, left, above]
}
