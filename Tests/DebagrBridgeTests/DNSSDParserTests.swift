import DebagrCore
import Foundation
import Testing

@testable import DebagrBridge

@Suite("DNS-SD Output Parsers")
struct DNSSDParserTests {
  @Test("Parses dns-sd -B and -L output cleanly")
  func parsesBrowseAndLookup() {
    let browseSample = """
      Browsing for _apple-mobdev2._tcp.local.
      DATE: ---Mon 23 Nov 2026---
      11:02:01.100  ...STARTING...
      11:02:01.210  Add        2  14 local.               _apple-mobdev2._tcp. 12:34:56:78:9a:bc@deadbeefcafebabe
      11:02:01.215  Add        2  15 local.               _apple-mobdev2._tcp. 12:34:56:78:9a:bc@deadbeefcafebabe
      """

    let instances = SystemDNSSDController.parseBrowseInstances(from: browseSample)
    #expect(instances == ["12:34:56:78:9a:bc@deadbeefcafebabe"])

    let lookupSample = """
      Lookup 12:34:56:78:9a:bc@deadbeefcafebabe._apple-mobdev2._tcp.local.
      DATE: ---Mon 23 Nov 2026---
      11:02:02.010  12:34:56:78:9a:bc@deadbeefcafebabe._apple-mobdev2._tcp.local. can be reached at 00008140-001E45990413C01C.local.:62078 (interface 14)
       flags=0x0
      """

    let record = SystemDNSSDController.parseLookupOutput(
      instanceName: instances[0],
      serviceType: WirelessIdentity.mobdevServiceType,
      domain: "local.",
      output: lookupSample
    )
    #expect(record != nil)
    #expect(record?.hostTarget == "00008140-001E45990413C01C.local.")
    #expect(record?.port == 62078)
    #expect(record?.txtRecords["flags"] == "0x0")
  }
}
