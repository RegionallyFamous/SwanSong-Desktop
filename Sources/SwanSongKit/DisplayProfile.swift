import Foundation

public struct DisplayProfileParameters: Equatable, Sendable {
    public let saturation: Float
    public let contrast: Float
    public let brightness: Float
    public let pixelGridStrength: Float
    public let responsePersistence: Float
    public let tintRed: Float
    public let tintGreen: Float
    public let tintBlue: Float

    public init(
        saturation: Float,
        contrast: Float,
        brightness: Float,
        pixelGridStrength: Float,
        responsePersistence: Float,
        tintRed: Float,
        tintGreen: Float,
        tintBlue: Float
    ) {
        self.saturation = saturation
        self.contrast = contrast
        self.brightness = brightness
        self.pixelGridStrength = pixelGridStrength
        self.responsePersistence = responsePersistence
        self.tintRed = tintRed
        self.tintGreen = tintGreen
        self.tintBlue = tintBlue
    }
}

public enum DisplayProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case purePixels = "Pure Pixels"
    case wonderSwanLCD = "WonderSwan LCD"
    case colorLCD = "Color LCD"
    case swanCrystalLCD = "SwanCrystal LCD"

    public var id: String { rawValue }

    public var detail: String {
        switch self {
        case .purePixels:
            "Unaltered nearest-neighbor pixels"
        case .wonderSwanLCD:
            "Warm monochrome panel with gentle pixel separation"
        case .colorLCD:
            "Soft color and contrast of the original reflective LCD"
        case .swanCrystalLCD:
            "Brighter color and the cleaner SwanCrystal panel"
        }
    }

    public var parameters: DisplayProfileParameters {
        switch self {
        case .purePixels:
            DisplayProfileParameters(
                saturation: 1,
                contrast: 1,
                brightness: 0,
                pixelGridStrength: 0,
                responsePersistence: 0,
                tintRed: 1,
                tintGreen: 1,
                tintBlue: 1
            )
        case .wonderSwanLCD:
            DisplayProfileParameters(
                saturation: 0,
                contrast: 0.86,
                brightness: 0.06,
                pixelGridStrength: 0.07,
                responsePersistence: 0.14,
                tintRed: 0.88,
                tintGreen: 0.96,
                tintBlue: 0.78
            )
        case .colorLCD:
            DisplayProfileParameters(
                saturation: 0.88,
                contrast: 0.94,
                brightness: 0.025,
                pixelGridStrength: 0.055,
                responsePersistence: 0.10,
                tintRed: 1.03,
                tintGreen: 1,
                tintBlue: 0.91
            )
        case .swanCrystalLCD:
            DisplayProfileParameters(
                saturation: 1.06,
                contrast: 1.04,
                brightness: 0.005,
                pixelGridStrength: 0.025,
                responsePersistence: 0.035,
                tintRed: 0.99,
                tintGreen: 1.01,
                tintBlue: 1.04
            )
        }
    }
}
