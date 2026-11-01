import Foundation
import Testing
@testable import MacGameToolboxCore

private func diskRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("disk-regression-" + UUID().uuidString) }

@Test func mountPathValidationRejectsWhitespaceAndRelativePaths() {
    for value in ["", "   ", "relative/path", "/"] { #expect(throws: (any Error).self) { try InputValidation.normalizedAbsolutePath(value) } }
}
@Test func diskUUIDMismatchNeverMatchesReusedIdentifier() {
    let record = DiskPreset(diskIdentifier: "disk4s1", volumeUUID: "old", mountPath: "/tmp/Games")
    #expect(DiskService.matchingVolume(for: record, in: [diskFixture(uuid: "different")]) == nil)
}
@Test func mountingPreflightRejectsDuplicateOverlappingAndOccupiedPaths() throws {
    let root = diskRoot()
    let a = diskFixture(), b = diskFixture("disk5s1")
    for paths in [[root.path, root.path], [root.path, root.appendingPathComponent("nested").path]] {
        #expect(throws: (any Error).self) { try DiskService.validateMountRequests([DiskMountRequest(volume:a,path:paths[0]),DiskMountRequest(volume:b,path:paths[1])], volumes:[a,b]) }
    }
    let mounted = diskFixture("disk5s1", path:root.path)
    #expect(throws: (any Error).self) { try DiskService.validateMountRequests([DiskMountRequest(volume:a,path:root.path)],volumes:[a,mounted]) }
    let selfHosted = diskFixture(path:root.path)
    #expect(throws: (any Error).self) { try DiskService.validateMountRequests([DiskMountRequest(volume:selfHosted,path:root.appendingPathComponent("child").path)], volumes:[selfHosted]) }
}
@Test func mountingPreflightRejectsNonemptyFileAndIdentityChanges() throws {
    let root=diskRoot()
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:root) }
    let file=root.appendingPathComponent("content")
    try Data("existing user content".utf8).write(to:file)
    for path in [root.path,file.path] { #expect(throws: (any Error).self) { try DiskService.validateMountRequests([DiskMountRequest(volume:diskFixture(),path:path)],volumes:[diskFixture()]) } }
    #expect(throws: (any Error).self) { try DiskService.validateMountRequests([DiskMountRequest(volume:diskFixture(uuid:"expected"),path:root.path)],volumes:[diskFixture(uuid:"replacement")]) }
}
@Test func busyUnmountDoesNotAttemptMountOrRollback() async throws {
    let root=diskRoot(); defer { try? FileManager.default.removeItem(at:root) }
    let runner=MockRunner(paths:["disk4s1":"/Volumes/Original"])
    await runner.configure(unmount:["disk4s1"])
    let service=DiskService(runner:runner)
    let volumes=try await service.listEligibleVolumes()
    let result=await service.mountVolumes([DiskMountRequest(volume:volumes[0],path:root.path)])
    #expect(result.items[0].outcome == .failed)
    #expect(await runner.calls.filter { $0.first == "mount" }.isEmpty)
    #expect(await runner.paths["disk4s1"] == "/Volumes/Original")
}
@Test func rollbackFailureAndUnattemptedVolumesAreReported() async throws {
    let root=diskRoot(); defer { try? FileManager.default.removeItem(at:root) }
    let runner=MockRunner(failingMount:"disk5s1",ids:["disk4s1","disk5s1","disk6s1"],paths:["disk4s1":"/Volumes/Original"])
    await runner.configure(rollback:["disk4s1"])
    let service=DiskService(runner:runner), volumes=try await service.listEligibleVolumes()
    let result=await service.mountVolumes(volumes.map {DiskMountRequest(volume:$0,path:root.appendingPathComponent($0.id).path)})
    #expect(result.items.map(\.outcome) == [.rollbackFailed,.rolledBack,.notAttempted])
    #expect(!result.items[0].message.isEmpty)
    #expect(await runner.paths["disk5s1"] == nil)
}
@Test func replacementAfterUnmountIsNeverMountedOrRolledBack() async throws {
    let root=diskRoot(); defer { try? FileManager.default.removeItem(at:root) }
    let runner=MockRunner(paths:["disk4s1":"/Volumes/Original"])
    await runner.configure(identityAfterUnmount:["disk4s1"])
    let service=DiskService(runner:runner), volumes=try await service.listEligibleVolumes()
    let result=await service.mountVolumes([DiskMountRequest(volume:volumes[0],path:root.path)])
    #expect(result.items[0].outcome == .rollbackFailed)
    #expect(await runner.calls.filter { $0.first == "mount" }.isEmpty)
}
@Test func defaultRestorationContinuesAndOnlyReportsActualSuccesses() async throws {
    let runner=MockRunner(paths:["disk4s1":"/Volumes/Original-A","disk5s1":"/Volumes/Original-B"])
    await runner.configure(defaults:["disk4s1"])
    let service=DiskService(runner:runner), volumes=try await service.listEligibleVolumes()
    let result=await service.restoreVolumes(volumes)
    #expect(result.items.map(\.outcome) == [.rolledBack,.succeeded])
    #expect(await runner.paths["disk4s1"] == "/Volumes/Original-A")
    #expect(await runner.paths["disk5s1"] == "/Volumes/Default-disk5s1")
}
@Test func serviceRejectsConcurrentMountAndRestoreOperations() async throws {
    let root=diskRoot(); defer { try? FileManager.default.removeItem(at:root) }
    let runner=MockRunner()
    await runner.configure(delay:true)
    let service=DiskService(runner:runner), volumes=try await service.listEligibleVolumes()
    let first=Task {await service.mountVolumes([DiskMountRequest(volume:volumes[0],path:root.path)])}
    for _ in 0..<100 {
        if await runner.calls.contains(where:{$0.first == "mount"}) {break}
        try await Task.sleep(for:.milliseconds(2))
    }
    let second=await service.restoreVolumes([volumes[1]])
    #expect(second.preflightError != nil)
    #expect(await first.value.isSuccess)
}
@Test func reservedVolumesAreExcludedAndRemovableMediaAreIdentified() {
    let boot:[String:Any]=["DeviceIdentifier":"disk0s1","ParentWholeDisk":"disk0"]
    let base:[String:Any]=["DeviceIdentifier":"disk6s1","ParentWholeDisk":"disk6","WholeDisk":false,"VolumeName":"Not a reserved name","FilesystemType":"apfs","Internal":true,"Removable":true]
    var efi=base; efi["Content"]="EFI"
    #expect(DiskService.parseVolumeInfo(efi,bootInfo:boot) == nil)
    var role=base; role["APFSVolumeRole"]=["Preboot"]
    #expect(DiskService.parseVolumeInfo(role,bootInfo:boot) == nil)
    #expect(DiskService.parseVolumeInfo(base,bootInfo:boot)?.isRemovable == true)
}
@Test func restorationPlanDistinguishesLegacyOfflineMissingAndAlreadyMounted() throws {
    let root=diskRoot();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:root)}
    let volume=diskFixture(path:root.path)
    let records=[DiskPreset(diskIdentifier:volume.id,mountPath:root.path),DiskPreset(diskIdentifier:volume.id,volumeUUID:"OFFLINE",mountPath:root.path),DiskPreset(diskIdentifier:volume.id,volumeUUID:volume.volumeUUID,mountPath:root.appendingPathComponent("missing").path),DiskPreset(diskIdentifier:volume.id,volumeUUID:volume.volumeUUID,mountPath:root.path)]
    let plan=DiskRestorationPlan(presets:records,volumes:[volume])
    #expect(plan.requests.isEmpty)
    #expect(plan.entries.map(\.state) == [.needsAssociation,.offline,.invalidPath,.alreadyMounted])
}
@Test func configurationDeduplicatesUUIDsInsteadOfReusedDeviceNumbers() async throws {
    let root=diskRoot();defer {try? FileManager.default.removeItem(at:root)}
    let store=ConfigurationStore(configurationURL:root.appendingPathComponent("config.json"))
    var config=AppConfiguration()
    config.diskPresets=[DiskPreset(diskIdentifier:"disk4s1",volumeUUID:"FIRST"),DiskPreset(diskIdentifier:"disk4s1",volumeUUID:"SECOND"),DiskPreset(diskIdentifier:"disk8s2",volumeUUID:"first")]
    try await store.save(config)
    #expect(try await store.load(importLegacy:false).diskPresets.map(\.volumeUUID) == ["FIRST","SECOND"])
}

@Test func defaultRestorationSkipsAnAlreadyDefaultMountAndRejectsDuplicates() async throws {
    let runner=MockRunner(paths:["disk4s1":"/Volumes/Fixture-disk4s1"])
    let service=DiskService(runner:runner), volumes=try await service.listEligibleVolumes()
    let first=await service.restoreVolumes([volumes[0]])
    #expect(first.items[0].outcome == .unchanged)
    let duplicate=await service.restoreVolumes([volumes[0],volumes[0]])
    #expect(duplicate.preflightError != nil)
    #expect(await runner.calls.filter { $0.first == "unmount" || $0.first == "mount" }.isEmpty)
}

@Test func duplicateLiveUUIDsAreAmbiguousAndNeverAutomaticallyMatched() {
    let record=DiskPreset(diskIdentifier:"disk4s1",volumeUUID:"CLONED",mountPath:"/tmp/Games")
    #expect(DiskService.matchingVolume(for:record,in:[diskFixture(uuid:"CLONED"),diskFixture("disk5s1",uuid:"cloned")]) == nil)
}
private actor EFIFilterRunner: CommandRunning {
    let base=MockRunner()
    func run(_ executable:String,arguments:[String]) async throws -> CommandResult {
        if arguments.first == "list" {
            let plist:[String:Any]=["AllDisks":["disk4s1","disk6s1"],"AllDisksAndPartitions":[["DeviceIdentifier":"disk6","Partitions":[["DeviceIdentifier":"disk6s1","Content":"EFI"]]]]]
            return CommandResult(exitCode:0,standardOutput:try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0),standardError:Data())
        }
        return try await base.run(executable,arguments:arguments)
    }
}
@Test func discoverySkipsKnownEFIPartitionsBeforeQueryingTheirInfo() async throws {
    let runner=EFIFilterRunner()
    let result=try await DiskService(runner:runner).listEligibleVolumes()
    #expect(result.map(\.id)==["disk4s1"])
    #expect(await runner.base.calls.contains(["info","-plist","disk6s1"]) == false)
}
