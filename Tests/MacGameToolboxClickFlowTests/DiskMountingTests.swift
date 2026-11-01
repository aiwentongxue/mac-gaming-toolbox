#if !SWIFT_PACKAGE
import XCTest
import SwiftUI
@testable import Mac_游戏工具箱

private actor DiskHostRunner: CommandRunning {
    var calls: [[String]]=[]
    var paths: [String:String]=[:]
    let failedDefault: String?
    let failRefresh: Bool
    init(failedDefault: String? = nil, failRefresh: Bool = false) {self.failedDefault=failedDefault;self.failRefresh=failRefresh}
    func run(_ executable:String,arguments:[String]) async throws -> CommandResult {
        calls.append(arguments)
        var info:[String:Any]=[:]
        if arguments.first == "list" && failRefresh && !paths.isEmpty {throw ToolboxError.commandFailed("refresh fixture failure")}
        if arguments.first == "list" {info=["AllDisks":["disk4s1","disk5s1"]]}
        if arguments.first == "unmount" {paths[arguments.last!]=nil}
        if arguments.first == "mount" {
            let custom=arguments.contains("-mountPoint")
            let id=custom ? String(arguments.last!.dropFirst(5)) : arguments.last!
            if !custom && id == failedDefault {throw ToolboxError.commandFailed("default fixture failure")}
            paths[id]=custom ? arguments[2] : "/Volumes/Default-"+id
        }
        if arguments.first == "info",let id=arguments.last {
            if id == "/" {info=["DeviceIdentifier":"disk0s1","ParentWholeDisk":"disk0"]}
            else {info=["DeviceIdentifier":id,"ParentWholeDisk":"disk4","WholeDisk":false,"VolumeName":"Fixture-"+id,"FilesystemType":"apfs","VolumeUUID":"UUID-"+id,"MountPoint":paths[id] ?? ""]}
        }
        return CommandResult(exitCode:0,standardOutput:try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0),standardError:Data())
    }
}
@MainActor final class DiskMountingTests: XCTestCase {
    private func volume(_ id:String="disk4s1",uuid:String?=nil,path:String?=nil,name:String?=nil) -> DiskVolume {
        DiskVolume(id:id,volumeUUID:uuid ?? "UUID-"+id,name:name ?? "Fixture-"+id,fileSystem:"apfs",mountPoint:path,size:1024,wholeDisk:"disk4",isInternal:false)
    }
    private func root() -> URL {FileManager.default.temporaryDirectory.appendingPathComponent("disk-host-"+UUID().uuidString)}
    private func wait(_ model:AppModel) async throws {
        for _ in 0..<1000 {if !model.isDiskBusy && !model.isRefreshingDisks {return};try await Task.sleep(for:.milliseconds(5))}
        XCTFail("Disk task did not finish")
    }
    func testDiskSingleActionIgnoresBatchSelectionAndRefreshesMountPoint() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let runner=DiskHostRunner(), service=DiskService(runner:runner)
        let model=AppModel(configurationStore:ConfigurationStore(configurationURL:root.appendingPathComponent("config.json")),launchAutomatically:false,diskService:service)
        let volumes=try await service.listEligibleVolumes()
        model.applyDiskRefresh(volumes)
        model.activeDiskID="disk5s1";model.selectedDiskIDs=["disk4s1"]
        let target=root.appendingPathComponent("target").path
        let selected=try XCTUnwrap(volumes.first{$0.id==model.activeDiskID})
        model.mountDisks([DiskMountRequest(volume:selected,path:target)])
        // A second request while the first job is running is ignored immediately.
        model.mountDisks([DiskMountRequest(volume:volumes[0],path:root.appendingPathComponent("wrong").path)])
        try await wait(model)
        let calls=await runner.calls
        XCTAssertEqual(calls.filter{$0.first == "mount"}.map{$0.last!},["/dev/disk5s1"])
        XCTAssertEqual(model.disks.first{$0.id=="disk5s1"}?.mountPoint,target)
        XCTAssertEqual(model.configuration.restorableDiskMounts.map(\.volumeUUID),["UUID-disk5s1"])
        XCTAssertEqual(model.activeDiskID,"disk5s1")
    }
    func testDiskRefreshPreservesDraftAndFocusAcrossRenumberingButNotIdentityReuse() {
        let model=AppModel(launchAutomatically:false)
        let original=volume(uuid:"STABLE")
        model.applyDiskRefresh([original]);model.diskPaths[original.id]="/tmp/edited";model.selectedDiskIDs=[original.id]
        model.configuration.diskPresets=[DiskPreset(diskIdentifier:original.id,volumeUUID:"STABLE",mountPath:"/tmp/saved")]
        let renumbered=volume("disk8s2",uuid:"STABLE"),replacement=volume(uuid:"OTHER")
        model.applyDiskRefresh([replacement,renumbered])
        XCTAssertEqual(model.activeDiskID,renumbered.id)
        XCTAssertEqual(model.selectedDiskIDs,[renumbered.id])
        XCTAssertEqual(model.diskPaths[renumbered.id],"/tmp/edited")
        XCTAssertNil(model.diskPaths[replacement.id])
        model.applyDiskRefresh([replacement])
        XCTAssertTrue(model.selectedDiskIDs.isEmpty)
        model.applyDiskRefresh([replacement,renumbered])
        XCTAssertEqual(model.diskPaths[renumbered.id],"/tmp/edited")
    }
    func testDiskLegacyRecordsRequireExplicitAssociationAndNewPresetsStoreUUID() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let model=AppModel(configurationStore:ConfigurationStore(configurationURL:root.appendingPathComponent("config.json")),launchAutomatically:false)
        let disk=volume(),legacy=DiskPreset(diskIdentifier:disk.id,mountPath:"/tmp/legacy")
        model.configuration.diskPresets=[legacy];model.configuration.restorableDiskMounts=[legacy]
        model.applyDiskRefresh([disk])
        XCTAssertNil(model.diskPaths[disk.id]);XCTAssertNil(model.configuration.restorableDiskMounts[0].volumeUUID)
        model.associateDiskRecord(legacy,with:disk,automatic:false)
        XCTAssertEqual(model.configuration.diskPresets[0].volumeUUID,disk.volumeUUID)
        XCTAssertNil(model.configuration.restorableDiskMounts[0].volumeUUID)
        model.diskPaths[disk.id]="/tmp/updated";model.saveDiskPreset(disk.id)
        XCTAssertEqual(model.configuration.diskPresets[0].mountPath,"/tmp/updated")
        try await Task.sleep(for:.milliseconds(80))
    }
    func testDiskPartialDefaultRestorationOnlyClearsSuccessfulRecords() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let service=DiskService(runner:DiskHostRunner(failedDefault:"disk4s1"))
        let model=AppModel(configurationStore:ConfigurationStore(configurationURL:root.appendingPathComponent("config.json")),launchAutomatically:false,diskService:service)
        let disks=try await service.listEligibleVolumes()
        model.applyDiskRefresh(disks)
        model.configuration.restorableDiskMounts=disks.map{DiskPreset(diskIdentifier:$0.id,volumeUUID:$0.volumeUUID,mountPath:"/tmp/old")}
        model.restoreDisks(disks);try await wait(model)
        XCTAssertEqual(model.configuration.restorableDiskMounts.map(\.diskIdentifier),["disk4s1"])
        XCTAssertEqual(model.diskOperationResult?.items.map(\.outcome),[.rolledBack,.succeeded])
        try await Task.sleep(for:.milliseconds(50))
    }
    func testDiskAuthorizationCancellationDoesNotUnmountAnything() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let runner=DiskHostRunner(),service=DiskService(runner:runner)
        let model=AppModel(configurationStore:ConfigurationStore(configurationURL:root.appendingPathComponent("config.json")),launchAutomatically:false,diskService:service,mountDirectoryCreator:{_ in throw CancellationError()})
        let disks=try await service.listEligibleVolumes();model.applyDiskRefresh(disks)
        model.mountDisks([DiskMountRequest(volume:disks[0],path:root.appendingPathComponent("missing").path)])
        try await wait(model)
        XCTAssertEqual(model.status.phase,.cancelled)
        let calls=await runner.calls
        XCTAssertTrue(calls.filter{$0.first == "unmount" || $0.first == "mount"}.isEmpty)
    }
    func testDiskDuplicateUUIDsKeepExactFocusAndNeverShareNewDrafts() {
        let model=AppModel(launchAutomatically:false)
        let a=volume(uuid:"CLONED"),b=volume("disk5s1",uuid:"CLONED")
        model.applyDiskRefresh([a,b]);model.activeDiskID=b.id
        model.diskPaths[a.id]="/tmp/A";model.diskPaths[b.id]="/tmp/B"
        model.applyDiskRefresh([a,b])
        XCTAssertEqual(model.activeDiskID,b.id)
        XCTAssertEqual(model.diskPaths[a.id],"/tmp/A")
        XCTAssertEqual(model.diskPaths[b.id],"/tmp/B")
        model.configuration.diskPresets=[DiskPreset(diskIdentifier:a.id,volumeUUID:"CLONED",mountPath:"/tmp/saved")]
        let c=volume("disk8s1",uuid:"CLONED")
        model.applyDiskRefresh([a,b,c])
        XCTAssertNil(model.diskPaths[c.id])
    }
    func testDiskRefreshFailureIsVisibleAfterSuccessfulMount() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let service=DiskService(runner:DiskHostRunner(failRefresh:true))
        let model=AppModel(configurationStore:ConfigurationStore(configurationURL:root.appendingPathComponent("config.json")),launchAutomatically:false,diskService:service)
        let volumes=try await service.listEligibleVolumes();model.applyDiskRefresh(volumes)
        model.mountDisks([DiskMountRequest(volume:volumes[0],path:root.appendingPathComponent("target").path)])
        try await wait(model)
        XCTAssertTrue(model.diskOperationResult?.isSuccess == true)
        XCTAssertNotNil(model.diskRefreshError)
        XCTAssertEqual(model.status.phase,.failed)
    }
    func testDiskPageFitsMinimumDetailWidthInNineLanguagesAndBothAppearances() throws {
        let defaults=UserDefaults.standard,old=UserDefaults.standard.object(forKey:AppLanguage.preferenceKey)
        defer {if let old {defaults.set(old,forKey:AppLanguage.preferenceKey)} else {defaults.removeObject(forKey:AppLanguage.preferenceKey)}}
        let output=URL(fileURLWithPath:"/tmp/mac-toolbox-disk-layout-qa")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let model=AppModel(launchAutomatically:false),localization=LocalizationController()
        model.applyDiskRefresh([volume(name:String(repeating:"Long Volume Name ",count:4)),volume("disk5s1")])
        for language in AppLanguage.Preference.allCases where language != .system {
            localization.setPreference(language)
            for batch in [false,true] {
            model.selectedDiskIDs = batch ? Set(model.disks.map(\.id)) : []
            for scheme in [ColorScheme.light,.dark] {
                let content=ZStack { AppBackgroundView(); DiskManagerDetailView(initialBatchMode: batch) }.environmentObject(model).environmentObject(localization).environment(\.colorScheme,scheme).preferredColorScheme(scheme)
                let host=NSHostingView(rootView:content)
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:672,height:612),styleMask:[.borderless],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=host
                host.layoutSubtreeIfNeeded();window.displayIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.width,673,"\(language)")
                let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                let appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
                appearance?.performAsCurrentDrawingAppearance {host.cacheDisplay(in:host.bounds,to:bitmap)}
                let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                try data.write(to:output.appendingPathComponent("disk-\(language.rawValue)-\(batch ? "batch":"single")-\(scheme == .dark ? "dark":"light").png"))
                window.close()
            }
            }
        }
    }
}
#endif
