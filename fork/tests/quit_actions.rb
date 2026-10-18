#!/usr/bin/env ruby
# Exercise production Quit dispatch with inert apps; never terminate a real process.
require 'tmpdir'
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
util = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowUtil.swift")
info = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowInfo.swift")
catalog = File.read("#{ROOT}/DockDoor/Utilities/Window Management/WindowActionCatalog.swift")
perform = block(util, "    func perform(\n")
abort 'Preview Quit/Close still inspects held modifiers' if perform.include?('modifierFlags')
abort 'Quit label still inspects held modifiers' if block(catalog, '    func menuTitle(').include?('modifierFlags')
dock = File.read("#{ROOT}/DockDoor/Utilities/DockObserver.swift")
gesture = block(dock, '    private func handleCmdRightClickQuit(')
abort 'Documented Dock Quick Quit changed' unless gesture.include?('event.flags.contains(.maskAlternate)') && gesture.include?('app.forceTerminate()') && gesture.include?('app.terminate()')
builder = File.read("#{ROOT}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift")
abort 'Both Quit actions need shared destructive styling' unless builder.include?('if action.isQuitAction {')
abort 'Collapsed Quit needs an explicit Force Quit alternative' unless builder.include?('.flatMap { $0 == .quit ? [.quit, .forceQuit] : [$0] }')
abort 'Force Quit missing from shared menus' unless catalog.include?('[.close, .quit, .forceQuit]')
abort 'Force Quit missing from assignments' unless util[util.index('    static let assignablePreviewActions:')...util.index('    func postActionCategory(')].include?('.forceQuit')
coordinator = File.read("#{ROOT}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
highlighted = block(coordinator, '    func performActionOnCmdTabHighlightedApps(')
abort 'Cmd+Tab app requests must report refusal' unless highlighted.include?('if case .noChange = result {')
defaults = File.read("#{ROOT}/DockDoor/consts.swift")
abort 'Force Quit must not gain a default assignment' if defaults.include?('.forceQuit')
%w[quit forceQuit].each do |action|
  abort "Stored action #{action} missing" unless util.match?(/^    case #{action}$/)
end

source = <<~'SWIFT'
import Foundation
typealias pid_t = Int32
struct Key<T> { let value: T }
enum Defaults { static subscript<T>(_ key: Key<T>) -> T { key.value } }
extension Key where T == Bool {
 static var fillActionsAutoTileSelection: Self { Self(value: false) }
 static var moveResizeBringToForeground: Self { Self(value: false) }
}
final class App {
 let processIdentifier: pid_t
 var isHidden = false, isTerminated = false, accepts = true
 var normal = 0, forced = 0
 init(_ pid: pid_t) { processIdentifier = pid }
 func terminate() -> Bool { normal += 1; return accepts }
 func forceTerminate() -> Bool { forced += 1; return accepts }
}
struct AX { func isFullscreen() throws -> Bool { false } }
struct PreviewWindowIdentity: Hashable {
 let pid: pid_t, windowID: Int
 init(_ window: WindowInfo) { pid = window.app.processIdentifier; windowID = window.id }
}
struct WindowInfo {
 let id: Int, app: App
 var isWindowlessApp = false, isFullscreen: Bool? = false
 var isMinimized = false
 var isHidden: Bool { app.isHidden }
 var axElement: AX { AX() }
 func close() -> Bool { true }
 func bringToFrontConfirmed() async -> Bool { true }
SWIFT
source += block(info, '    func quit(force:') + "\n}\n"
case_start = util.index('    // Existing actions')
cases = util[case_start...util.index('    var localizedName:', case_start)].scan(/^    case (\w+)$/).flatten
source += "enum WindowAction { case #{cases.join(', ')}\n"
%w[localizedName iconName].each { |name| source += block(util[case_start..], "    var #{name}:") + "\n" }
source += catalog[catalog.index('    var isQuitAction:')...catalog.index('    var isAppWidePreviewAction:')]
%w[isAppWidePreviewAction].each { |name| source += block(catalog, "    var #{name}:") + "\n" }
%w[appliesToSelectedWindow batchTargets].each { |name| source += block(catalog, "    func #{name}(") + "\n" }
source += <<~'SWIFT'
 var tilingDirection: Int? { nil }
 func autoTilingDirection(windowCount: Int, fillActionsAutoTile: Bool) -> Int? { nil }
 func batchTargetState(for windows: [WindowInfo]) -> Bool? { nil }
 func isAvailable(for window: WindowInfo) -> Bool { true }
SWIFT
source += block(catalog, '    func menuTitle(') + "\n" + block(catalog, '    func feedbackTitle(') + "\n"
source += <<~'SWIFT'
 enum ActionResult { case noChange, dismissed }
 func perform(on window: WindowInfo, keepPreviewOnQuit: Bool = false, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> ActionResult {
  defer { feedback?.finishRemaining(.requested) }
  func accepted(_ success: Bool) -> Bool { if !success { feedback?.finishRemaining(.failed) }; return success }
  switch self {
SWIFT
source += perform[perform.index('        case .quit, .forceQuit:')...perform.index('        case .minimize:')]
source += "default: return .noChange\n}\n}\n}\n"
source += <<~'SWIFT'
enum Outcome { case requested, completed, failed, cancelled }
final class ActionFeedbackHandle {
 var states: [PreviewWindowIdentity: Outcome] = [:]
 var confirmedProgress: ((WindowInfo, Bool) -> Void)? { nil }
 func finishRemaining(_ outcome: Outcome) {}
 func finish(_ id: PreviewWindowIdentity, _ outcome: Outcome) { if states[id] == nil { states[id] = outcome } }
 func finish(_ result: WindowUtil.PreviewBatchResult, requested: Bool = false) {}
}
enum WindowUtil {
 static var quitOnClose = false
 static func readCachedWindows(for pid: pid_t) -> [WindowInfo] { [] }
 static func shouldQuitAppOnWindowClose(processIdentifier pid: pid_t) -> Bool { quitOnClose }
 static func closeAllWindows(for app: App, preferredWindows: [WindowInfo]? = nil, feedback: ActionFeedbackHandle? = nil) -> Int { 0 }
 static func hasOnlyFullscreenWindows(for app: App) -> Bool { false }
 static func openNewWindow(app: App) {}
 static func canBringWindowToFrontWithoutSpaceSwitch(_ window: WindowInfo) -> Bool { true }
 static func setHiddenStateConfirmed(for app: App, isHidden: Bool, fullscreenCandidates: [AX] = [], beforeChange: (@MainActor (Bool) -> Bool)? = nil) async -> Bool { true }
 static func revealWindowConfirmed(_ window: WindowInfo) async -> Bool { true }
 static func changeFullscreenConfirmed(_ window: WindowInfo, toggle: Bool, beforeChange: (@MainActor (Bool) -> Bool)? = nil) async -> Bool { true }
 static func setMinimizedWindowsConfirmed(_ windows: [WindowInfo], isMinimized: Bool, progress: ((WindowInfo, Bool) -> Void)?) async -> [WindowInfo] { windows }
 static func tilePreviewWindows(_ windows: [WindowInfo], direction: Int, feedback: ActionFeedbackHandle?) async -> PreviewBatchResult { PreviewBatchResult() }
 static func closeWindows(_ windows: [WindowInfo], feedback: ActionFeedbackHandle?) async -> PreviewBatchResult { PreviewBatchResult(succeeded: windows) }
SWIFT
source += block(util, '    struct PreviewBatchResult') + "\n"
source += block(util, '    static func performPreviewBatchAction(') + "\n}\n"
source += <<~'SWIFT'
@main struct Checks {
 @MainActor static func main() async {
  for force in [false, true] {
   let app = App(1), other = App(2)
   let action = force ? WindowAction.forceQuit : .quit
   let one = WindowInfo(id: 1, app: app), two = WindowInfo(id: 2, app: app)
   let empty = WindowInfo(id: 0, app: other, isWindowlessApp: true)
   precondition(action.menuTitle(for: one) == (force ? "Force Quit App" : "Quit App"))
   precondition(action.feedbackTitle(for: one) == action.menuTitle(for: one))
   precondition(action.iconName == (force ? "exclamationmark.octagon.fill" : "xmark.circle.fill"))
   precondition(action.isAppWidePreviewAction && action.appliesToSelectedWindow(empty))
   let feedback = ActionFeedbackHandle()
   let result = await WindowUtil.performPreviewBatchAction(action, on: [one, two, empty, one], feedback: feedback)
   precondition(result.succeeded.count == 2 && result.failed.isEmpty)
   precondition(app.normal == (force ? 0 : 1) && app.forced == (force ? 1 : 0))
   precondition(other.normal == app.normal && other.forced == app.forced)
   precondition(feedback.states.count == 3 && feedback.states.values.allSatisfy { $0 == .requested })
   app.accepts = false
   let failed = await WindowUtil.performPreviewBatchAction(action, on: [one, two])
   precondition(failed.failed == [PreviewWindowIdentity(one)] && failed.succeeded.isEmpty)
   let stopped = App(3); stopped.isTerminated = true
   let unavailable = await WindowUtil.performPreviewBatchAction(action, on: [WindowInfo(id: 3, app: stopped)])
   precondition(unavailable.succeeded.isEmpty && stopped.normal == 0 && stopped.forced == 0)
   let scalar = App(4)
   if case .dismissed = action.perform(on: WindowInfo(id: 4, app: scalar)) {} else { preconditionFailure() }
   precondition(scalar.normal == (force ? 0 : 1) && scalar.forced == (force ? 1 : 0))
   scalar.accepts = false
   if case .noChange = action.perform(on: WindowInfo(id: 4, app: scalar)) {} else { preconditionFailure() }
  }
  WindowUtil.quitOnClose = true
  for windowless in [false, true] {
   let app = App(5), window = WindowInfo(id: 5, app: app, isWindowlessApp: windowless)
   _ = WindowAction.close.perform(on: window)
   precondition(app.normal == 1 && app.forced == 0)
  }
  let app = App(6)
  let windows = [WindowInfo(id: 6, app: app), WindowInfo(id: 7, app: app)]
  _ = await WindowUtil.performPreviewBatchAction(.close, on: windows)
  precondition(app.normal == 1 && app.forced == 0)
  let cancelled = App(7)
  let task = Task { @MainActor in
   withUnsafeCurrentTask { $0?.cancel() }
   return await WindowUtil.performPreviewBatchAction(.forceQuit, on: [WindowInfo(id: 8, app: cancelled)])
  }
  _ = await task.value
  precondition(cancelled.normal == 0 && cancelled.forced == 0)
  print("PASS normal/force dispatch, PID deduplication, windowless targets, acknowledgements, refusal, terminated targets, Close-to-Quit and cancellation")
 }
}
SWIFT
Dir.mktmpdir('dockfork-quit-actions-') do |dir|
  path = "#{dir}/checks.swift"; File.write(path, source)
  abort 'Swift compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', '-suppress-warnings', path, '-o', "#{dir}/checks")
  abort 'Quit checks failed' unless system("#{dir}/checks")
end
puts 'PASS catalog/menu/default wiring and unchanged Dock Quick Quit; all termination calls used inert apps'
