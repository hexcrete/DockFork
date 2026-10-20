#!/usr/bin/env ruby
# Runs the production script adapters and fullscreen worker against simulated APIs.
require 'tmpdir'
require_relative 'support/action_ownership'
require 'rexml/document'
ROOT = File.expand_path('../..', __dir__)
def block(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  first = source.index(/\{\n/, start)
  depth = 0
  (first...source.length).each do |i|
    depth += 1 if source[i] == '{'
    depth -= 1 if source[i] == '}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end
scripts = File.read("#{ROOT}/DockDoor/Utilities/ScriptCommands.swift")
util = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
dictionary = REXML::Document.new(File.read("#{ROOT}/DockDoor/DockDoor.sdef"))
commands = REXML::XPath.match(dictionary, '//command')
codes = commands.map { |command| command.attributes['code'] }
abort 'Duplicate Apple event code' unless codes.uniq.size == codes.size
abort 'DockFork quit command changed' unless commands.any? { |c| c.attributes['name'] == 'quit' && c.attributes['code'] == 'aaboroot' && c.elements['cocoa'].attributes['class'] == 'NSQuitCommand' }
['quit app', 'force quit app'].each do |name|
  command = commands.find { |c| c.attributes['name'] == name } or abort "Missing #{name}"
  abort 'App action must use shared asynchronous handler' unless command.elements['cocoa'].attributes['class'] == 'WindowActionCommand'
  abort 'App action must accept lists' unless command.elements['direct-parameter/type[@list="yes"]']
end

abort 'Legacy direct-execution helpers remain' if scripts.include?('static func performWindowAction(') || scripts.include?('static func positionWindow(')
abort 'Fullscreen entry must be limited to one target' unless util.include?('action == .toggleFullScreen && allowFullscreenEntry && windows.count == 1')
source = <<~'SWIFT'
import Foundation
struct Description { var commandName = "" }
class NSScriptCommand: NSObject {
 var directParameter: Any?; var evaluatedArguments: [String: Any]?
 var commandDescription = Description()
 func performDefaultImplementation() -> Any? { nil }
}
class AsyncWindowCommand: NSScriptCommand {
 var operation: (@MainActor () async throws -> String)?
 func execute(_ operation: @escaping @MainActor () async throws -> String) -> Any? { self.operation = operation; return "suspended" }
}
enum WindowAction { case maximize, center, fill, toggleFullScreen, minimize, close, hide, quit, forceQuit
 func isSupported(for window: WindowInfo) -> Bool { true }
 static let fullscreenConfirmationDelay: UInt64 = 180_000_000
}
struct PreviewWindowIdentity:Hashable {let pid:Int32;let windowID:Int;init(_ w:WindowInfo){pid=w.app.processIdentifier;windowID=w.id}}
struct WindowInfo { let axElement = FakeAX(); let app = App(); let id = 1
 var appAxElement: FakeAX { axElement }; var isWindowlessApp: Bool { false }
}
final class App { let processIdentifier: Int32 = 1; let isTerminated = false }
enum NSWorkspace { static let shared = Workspace() }
struct Workspace { var frontmostApplication: App? { nil } }
final class FakeAX {
 var full = false, refuses = false, writes = 0
 func isFullscreen() throws -> Bool { full }
 func focusedWindow() throws -> FakeAX { self }
 func cgWindowId() throws -> Int { 1 }
 func setAttribute(_ name: String, _ value: Bool) throws { writes += 1; if !refuses { full = value } }
}
let kAXFullscreenAttribute = "fullscreen"
enum Failure: Error { case invalid }
enum DockDoorCommands {
 enum CommandError: Error { case invalidParameter(String), invalidPosition(String) }
 static var focused: String?
 static func resolveWindows(_ ids: [String]) throws -> [WindowInfo] {
  guard !ids.contains("invalid") else { throw Failure.invalid }; return ids.map { _ in WindowInfo() }
 }
 static func focusWindow(_ id: String) throws { focused = id }
 static func batchResult(_ result: String) -> String { result }
 static func parsePositionAction(_ name: String) -> WindowAction? { name == "left" ? .fill : nil }
SWIFT
source += block(scripts, '    static func windowIdentifiers(') + "\n"
source += block(scripts, '    static func actionFromCommandName(') + "\n}\n"
source += <<~'SWIFT'
enum WindowUtil {
 static var calls = 0, count = 0, permitsEntry = false, failure = false
 static var cached: Bool?, reconciled = 0
 @MainActor static func performPreviewBatchAction(_ action: WindowAction, on windows: [WindowInfo], allowFullscreenEntry: Bool = false) async -> String {
  calls += 1; count = windows.count; permitsEntry = allowFullscreenEntry
  return failure ? "error: rejected" : "ok"
 }
 static func updateCachedWindowState(_ window: WindowInfo, isFullscreen: Bool) { cached = isFullscreen }
 static func scheduleCachedWindowMetadataReconciliation(pid: Int32, windowID: Int, delayNanos: UInt64) { reconciled += 1 }
SWIFT
source += block(util, '    private static func changeFullscreenConfirmed(').sub('private static', 'static') + "\n}\n"
source += block(scripts, 'class WindowActionCommand:') + "\n" + block(scripts, 'class PositionWindowCommand:') + "\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async throws {
  for name in ["minimize window", "close window", "maximize window", "hide window", "toggle fullscreen", "center window", "quit app", "force quit app"] {
   for parameter: Any in ["1", ["1"], ["1", "2"]] {
    let command = WindowActionCommand(); command.commandDescription.commandName = name; command.directParameter = parameter
    precondition(command.performDefaultImplementation() as? String == "suspended")
    let result = try await command.operation!(); precondition(result == "ok")
    precondition(WindowUtil.count == ((parameter as? [String])?.count ?? 1))
    precondition(WindowUtil.permitsEntry == (parameter is String))
   }
  }
  for parameter: Any in ["1", ["1"], ["1", "2"]] {
   let command = PositionWindowCommand(); command.directParameter = parameter; command.evaluatedArguments = ["position": "left"]
   precondition(command.performDefaultImplementation() as? String == "suspended")
   let result = try await command.operation!(); precondition(result == "ok" && !WindowUtil.permitsEntry)
  }
  let invalid = PositionWindowCommand(); invalid.directParameter = "1"; invalid.evaluatedArguments = ["position": "nope"]
  precondition((invalid.performDefaultImplementation() as? String)?.hasPrefix("error:") == true && invalid.operation == nil)
  let empty = WindowActionCommand(); empty.directParameter = [String]()
  precondition((empty.performDefaultImplementation() as? String)?.hasPrefix("error:") == true)
  let failed = WindowActionCommand(); failed.commandDescription.commandName = "maximize window"; failed.directParameter = "1"
  WindowUtil.failure = true; _ = failed.performDefaultImplementation()
  let failure = try await failed.operation!(); precondition(failure == "error: rejected")
  let missing = PositionWindowCommand(); missing.directParameter = "invalid"; missing.evaluatedArguments = ["position": "left"]
  _ = missing.performDefaultImplementation(); let before = WindowUtil.calls
  do { _ = try await missing.operation!(); preconditionFailure("Unknown target accepted") } catch {}
  precondition(WindowUtil.calls == before)
  let focus = WindowActionCommand(); focus.commandDescription.commandName = "focus window"; focus.directParameter = "1"
  precondition(focus.performDefaultImplementation() as? String == "ok" && DockDoorCommands.focused == "1" && focus.operation == nil)
  let window = WindowInfo()
  let entered = await WindowUtil.changeFullscreenConfirmed(window, toggle: true)
  precondition(entered && window.axElement.full && WindowUtil.cached == true)
  let exited = await WindowUtil.changeFullscreenConfirmed(window, toggle: true)
  precondition(exited && !window.axElement.full && WindowUtil.cached == false)
  let writes = window.axElement.writes
  let noOp = await WindowUtil.changeFullscreenConfirmed(window)
  precondition(noOp && window.axElement.writes == writes)
  window.axElement.refuses = true
  let refused = await WindowUtil.changeFullscreenConfirmed(window, toggle: true)
  precondition(!refused && WindowUtil.cached == false)
  let task = Task { await WindowUtil.changeFullscreenConfirmed(window, toggle: true) }
  try await Task.sleep(nanoseconds: 20_000_000); task.cancel()
  let cancelled = await task.value; precondition(!cancelled && WindowUtil.cached == false)
  print("PASS 27 single/list routes, validation, error propagation, explicit focus, fullscreen toggle/exit/no-op/refusal/cancellation")
 }
}
SWIFT
Dir.mktmpdir('dockfork-script-actions-') do |dir|
  path = "#{dir}/checks.swift"; File.write(path, with_action_ownership(source))
  abort 'Swift compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', path, '-o', "#{dir}/checks")
  abort 'Script checks failed' unless system("#{dir}/checks")
end

# Run the actual list-Space adapter with held callbacks, including group ownership.
source = <<~'SWIFT'
import Foundation
struct PreviewWindowIdentity: Hashable { let pid: Int32; let windowID: Int
 init(_ window: WindowInfo) { pid=1;windowID=window.id }
}
struct App { var processIdentifier: Int32 { 1 } }
struct WindowInfo { let id: Int; let app=App()
 @MainActor func bringToFrontConfirmed() async -> Bool {
  precondition(WindowActionRequest.current?.contains(PreviewWindowIdentity(self)) == true)
  WindowUtil.focused += 1;return true
 }
}
struct Space { let id=2 }
struct ManagedSpaceDestination { let space=Space() }
enum WindowSpaces { static func sourceSpaceIDs(for window: WindowInfo) -> Set<Int> { [2] } }
class AppDelegate { func dismissPreviews() {} }
struct Application { let delegate: Any?=nil }
let NSApp=Application()
enum DockDoorCommands {
 static func batchResult(_ result: WindowUtil.PreviewBatchResult) -> String {
  result.failed.isEmpty ? "ok" : "error: " + result.failed.map { String($0.windowID) }.joined(separator: ",")
 }
}
@MainActor enum WindowUtil {
 struct PreviewBatchResult { var succeeded:[WindowInfo]=[];var failed:[PreviewWindowIdentity]=[] }
 static var callbacks:[Int:(Bool)->Void]=[:], tokens:[UUID]=[], focused=0
 static func performConfirmedSpaceMove(_ window:WindowInfo,to destination:ManagedSpaceDestination,dismissPreviews:(()->Void)?,switchToDestination:Bool,completion:@escaping @MainActor(Bool)->Void)->(()->Void)? {
  let request=WindowActionRequest.current!
  precondition(request.contains(PreviewWindowIdentity(window)))
  tokens.append(request.token);callbacks[window.id]=completion
  return {callbacks.removeValue(forKey:window.id)}
 }
 static func revealWindowConfirmed(_ window:WindowInfo,checkingLiveState:Bool) async -> Bool {true}
}
extension WindowActionOwnership { var testCount:Int {lock.withLock {records.count}} }
@MainActor enum MoveAdapter {
SWIFT
source += block(scripts, '    private static func moveWindows(').sub('private static', 'static') + "\n}\n"
source += <<~'SWIFT'
@main struct SpaceChecks {
 @MainActor static func until(_ ready:()->Bool) async {
  for _ in 0..<10000 {if ready(){return};await Task.yield()};preconditionFailure("Move did not start")
 }
 @MainActor static func main() async {
  let a=WindowInfo(id:1),b=WindowInfo(id:2),c=WindowInfo(id:3),destination=ManagedSpaceDestination()
  let first=Task {await MoveAdapter.moveWindows([a,b],to:destination,switching:false)}
  await until {WindowUtil.callbacks.count==2}
  precondition(Set(WindowUtil.tokens).count==1,"Each member claimed an independent single request")
  let second=await MoveAdapter.moveWindows([a,b],to:destination,switching:false)
  precondition(second=="error: 1,2" && WindowUtil.tokens.count==2,"Busy group interrupted accepted move")
  let partial=Task {await MoveAdapter.moveWindows([a,c],to:destination,switching:false)}
  await until {WindowUtil.callbacks[3] != nil}
  WindowUtil.callbacks[3]?(true)
  let partialResult=await partial.value
  precondition(partialResult=="error: 1","Partial admission lost busy failure")
  WindowUtil.callbacks[1]?(true);WindowUtil.callbacks[2]?(true)
  let result=await first.value;precondition(result=="ok")
  WindowUtil.callbacks.removeAll()
  precondition(WindowActionOwnership.shared.testCount==0)
  let follow=Task {await MoveAdapter.moveWindows([a,b],to:destination,switching:true)}
  await until {WindowUtil.callbacks.count==2}
  WindowUtil.callbacks[1]?(true);WindowUtil.callbacks[2]?(true)
  let followed=await follow.value
  precondition(followed=="ok" && WindowUtil.focused==1 && WindowActionOwnership.shared.testCount==0)
  WindowUtil.callbacks.removeAll()
  let cancelled=Task {await MoveAdapter.moveWindows([a,b],to:destination,switching:false)}
  await until {WindowUtil.callbacks.count==2};cancelled.cancel()
  let cancellation=await cancelled.value
  precondition(cancellation=="error: Space move cancelled" && WindowUtil.callbacks.isEmpty && WindowActionOwnership.shared.testCount==0)
  print("PASS scripted Space lists: one protected group, overlapping refusal, unrelated partial progress, owned destination following, cancellation and cleanup")
 }
}
SWIFT
Dir.mktmpdir('dockfork-script-space-ownership-') do |dir|
  file="#{dir}/checks.swift"; File.write(file, with_action_ownership(source))
  abort 'Space-list fixture compilation failed' unless system('swiftc','-swift-version','5','-parse-as-library',file,'-o',"#{dir}/checks")
  abort 'Space-list ownership checks failed' unless system("#{dir}/checks")
end
