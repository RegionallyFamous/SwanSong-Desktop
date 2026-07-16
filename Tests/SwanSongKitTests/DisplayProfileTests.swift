import Testing
@testable import SwanSongKit

@Suite("Display profiles")
struct DisplayProfileTests {
    @Test("Smart Color activates only for monochrome hardware")
    func smartColorHardwareGuard() {
        #expect(DisplayProfile.smartColor.parameters(for: .wonderSwan).smartColorStrength == 1)
        #expect(DisplayProfile.smartColor.parameters(for: .pocketChallengeV2).smartColorStrength == 1)
        #expect(
            DisplayProfile.smartColor.parameters(for: .wonderSwanColor)
                == DisplayProfile.purePixels.parameters
        )
        #expect(
            DisplayProfile.smartColor.parameters(for: .swanCrystal)
                == DisplayProfile.purePixels.parameters
        )
        #expect(
            DisplayProfile.smartColor.parameters(for: .automatic)
                == DisplayProfile.purePixels.parameters
        )
    }

    @Test("Existing profiles never enable Smart Color")
    func existingProfilesStayUncolorized() {
        for profile in DisplayProfile.allCases where profile != .smartColor {
            #expect(profile.parameters.smartColorStrength == 0)
        }
    }
}
