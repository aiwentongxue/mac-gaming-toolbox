import Testing
@testable import AppDropCore

@Suite struct SharedConstantsTests {
    @Test func sharedConstantsAreConsistent() {
        #expect(SharedConstants.applicationSupportContainerName == "MacGameToolbox")
        #expect(SharedConstants.storageDirectoryName == "AppDrop")
        #expect(SharedConstants.supportedCountryCodes == [
            "us", "cn", "hk", "tw", "jp", "gb", "de", "ca", "au",
            "fr", "kr", "sg", "tr", "ng", "ar", "br", "in"
        ])
        #expect(SharedConstants.supportedCountryCodes == StoreCountry.codes)
        #expect(SharedConstants.isSupportedCountry("US"))
        #expect(SharedConstants.isSupportedCountry("GB"))
        #expect(SharedConstants.isSupportedCountry("tw"))
        #expect(!SharedConstants.isSupportedCountry("zz"))
        #expect(SharedConstants.helperBundleIdentifier == "com.iven.macgametoolbox.appdrop.helper")
        #expect(SharedConstants.helperAgentPlistName == "com.iven.macgametoolbox.appdrop.helper.plist")
        #expect(SharedConstants.wishdropFormatVersion == 1)
    }
}
