#!/usr/bin/env ruby
# Runs production native-tab lookup and Close against simulated AX controls.
require 'tmpdir'
require_relative 'support/action_ownership'
root = File.expand_path('../..', __dir__)
def block(source, signature)
  start = source.index(signature) or abort "Missing #{signature}"
  first = source.index('{', start)
  depth = 0
  (first...source.length).each do |i|
    depth += 1 if source[i] == '{'
    depth -= 1 if source[i] == '}'
    return source[start..i] if depth.zero?
  end
  abort "Unclosed #{signature}"
end
ax = File.read("#{root}/DockDoor/Extensions/AXUIElement.swift")
window = File.read("#{root}/DockDoor/Utilities/Window Management/WindowInfo.swift")
util = File.read("#{root}/DockDoor/Utilities/Window Management/WindowUtil.swift")
hover = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewHoverContainer.swift")
coordinator = File.read("#{root}/DockDoor/Views/Hover Window/Shared Components/SharedPreviewWindowCoordinator.swift")
menus = File.read("#{root}/DockDoor/Views/Hover Window/WindowPreviewInteractionModifier.swift")
routes = {
  'single action' => util.match?(/case \.close:.*?window\.close\(\)/m),
  'batch action' => util.include?('succeeded = await !closeWindows([window], feedback: feedback).succeeded.isEmpty'),
  'Close All' => block(util, '    static func closeAllWindows(').include?('requestWindowClosures(windowsToClose, feedback: feedback)'),
  'background Close worker' => block(util, '    private actor CloseExecutor').include?('requestWindowClosures(windows, feedback: feedback, settleFailures: settleFailures)') && block(util, '    private static func requestWindowClosures(').include?('window.close(progress:'),
  'preview controls' => block(hover, '    private func handleWindowAction(').include?('action.perform('),
  'preview selection' => hover.include?('performCheckedWindowAction(action, on: windowInfo)'),
  'keyboard coordinator' => block(coordinator, '    func performActionOnCurrentWindow(').include?('action.perform('),
  'selected-window batch' => coordinator.include?('WindowUtil.performPreviewBatchAction(action, on: targets, allowFullscreenEntry: allowFullscreenEntry, feedback: feedback,'),
  'Cmd+Tab highlighted apps' => block(coordinator, '    func performActionOnCmdTabHighlightedApps(').include?('return closeCmdTabHighlightedApps(') && block(coordinator, '    private func closeCmdTabHighlightedApps(').include?('await WindowUtil.closeWindows('),
  'native menu clicks and shortcuts' => menus.scan('request.handler(request.action)').length == 2,
  'menu-bar actions' => File.read("#{root}/DockDoor/Utilities/WindowActionsMenuController.swift").include?('action.perform(on: window, feedback: feedback)'),
  'keyboard routing' => File.read("#{root}/DockDoor/Utilities/KeybindHelper.swift").include?('performActionOnCurrentWindow(action: action)'),
  'script routing' => File.read("#{root}/DockDoor/Utilities/ScriptCommands.swift").include?('WindowUtil.performPreviewBatchAction(action, on: windows'),
  'native window gestures' => File.read("#{root}/DockDoor/Utilities/Window Gestures/WindowGestureExecutor.swift").include?('action.perform(on: window)')
}
routes.each { |name, passes| abort "Close route bypassed shared operation: #{name}" unless passes }
puts "Passed #{routes.size} shared Close route checks"
source = <<~'SWIFT'
import Foundation
let kAXTabGroupRole = "AXTabGroup", kAXRadioButtonRole = "AXRadioButton"
let kAXValueAttribute = "AXValue", kAXWindowAttribute = "AXWindow", kAXPressAction = "AXPress"
struct Key { static let collapseNativeTabsIntoSingleWindow = Key() }
enum Defaults { static var collapse = true; static subscript(_ key: Key) -> Bool { collapse } }
enum DebugLogger { static func log(_ operation: String, details: String) {} }
enum Failure: Error { case refused }
final class AXUIElement {
 static var closed: [Int] = []
 let id: Int, kind: String, sub: String?
 var nodes: [AXUIElement]?, value: NSNumber?, owner: AXUIElement?, control: AXUIElement?
 var failsRead = false, failsPress = false, reads = 0
 var delay: TimeInterval = 0
 static var closeWasOnMainThread = false
 var failsCloseRead = false, failsValueRead = false
 var onPress: (() -> Void)?
 init(_ id: Int, _ kind: String = "AXButton", _ nodes: [AXUIElement]? = [], sub: String? = nil, value: Int? = nil) {
  self.id = id; self.kind = kind; self.nodes = nodes; self.sub = sub; self.value = value.map(NSNumber.init(value:))
 }
 func children() throws -> [AXUIElement]? { reads += 1; if failsRead { throw Failure.refused }; return nodes }
 func role() throws -> String? { kind }
 func subrole() throws -> String? { sub }
 func attribute<T>(_ key: String, _ type: T.Type) throws -> T? {
  if key == kAXValueAttribute && failsValueRead { throw Failure.refused }
  return (key == kAXWindowAttribute ? owner as Any? : value as Any?) as? T
 }
 func closeButton() throws -> AXUIElement? { if failsCloseRead { throw Failure.refused }; return control }
 func cgWindowId() throws -> Int? { id }
 func performAction(_ action: String) throws {
  if failsPress { throw Failure.refused }
  Self.closeWasOnMainThread = Self.closeWasOnMainThread || Thread.isMainThread
  if delay > 0 { Thread.sleep(forTimeInterval: delay) }
  if kind != kAXRadioButtonRole { Self.closed.append(id) }
  onPress?()
 }
SWIFT
source += block(ax, '    func nativeTabGroup()') + "\n"
source += block(ax, '    func nativeBackgroundTabs()') + "\n}\n"
source += "struct WindowInfo { let id = 900; let axElement: AXUIElement; let closeButton: AXUIElement?; var isWindowlessApp = false\n"
source += block(window, '    func close(progress:') + "\n}\n"
source += <<~'SWIFT'
struct PreviewWindowIdentity:Hashable {let pid:Int32=1;let windowID:Int;init(_ window:WindowInfo){windowID=window.id}}
enum ActionFeedbackOutcome { case requested, failed }
final class CloseMetrics: @unchecked Sendable {
 let lock = NSLock()
 private var values: [(Int, Int)] = []
 private var terminal = false
 var progress: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return values }
 var finished: Bool { lock.lock(); defer { lock.unlock() }; return terminal }
 func append(_ completed: Int, _ total: Int) { lock.lock(); values.append((completed, total)); lock.unlock() }
 func finish() { lock.lock(); terminal = true; lock.unlock() }
}
struct ActionFeedbackHandle: Sendable {
 let metrics: CloseMetrics
 func closeProgress(for identity: PreviewWindowIdentity) -> @Sendable (Int, Int) -> Void { { metrics.append($0, $1) } }
 func finish(_ identity: PreviewWindowIdentity, _ outcome: ActionFeedbackOutcome) { metrics.finish() }
}
enum WindowUtil {
 struct PreviewBatchResult { var succeeded: [WindowInfo] = []; var failed: [PreviewWindowIdentity] = [] }
SWIFT
source += block(util, '    private actor CloseExecutor') + "\n"
source += util.lines.find { |line| line.include?('private static let closeExecutor =') }
source += block(util, '    static func closeWindows(') + "\n"
source += block(util, '    private static func requestWindowClosures(') + "\n}\n"
source += <<~'SWIFT'
final class Group {
 let root = AXUIElement(900, "AXWindow"), group = AXUIElement(901, kAXTabGroupRole)
 var members: [Int], selected = 900, rebuild: Bool, hideLast: Bool
 var selectionRefused = false, closeRefused = false, missingWindow = false, missingButton = false
 var pressFails = false, wrongWindow = false, changeCount = false
 var pressDelay: TimeInterval = 0
 var autoSelectSuccessor = false, rebuildOnSelection = false
 var closeReadFails = false
 var groupReadFailsAfterClose = false
 var savedButtons: [AXUIElement] = []
 init(_ background: [Int] = [1, 2, 3], rebuild: Bool = true, hideLast: Bool = false) {
  members = background + [900]; self.rebuild = rebuild; self.hideLast = hideLast
  root.nodes = [group]; root.control = AXUIElement(900); group.owner = root
  refresh()
 }
 func refresh() {
  if hideLast && members.count == 1 {group.nodes = nil; root.nodes = []; return}
  let tabs = members.map { member -> AXUIElement in
   let tab = AXUIElement(member + 1000, kAXRadioButtonRole, sub: "AXTabButton", value: member == selected ? 1 : 0)
   tab.onPress = { [unowned self, weak tab] in
    guard !selectionRefused, let tab else {return}
    for item in group.nodes ?? [] {item.value = 0}; tab.value = 1; selected = member
    let window = AXUIElement(wrongWindow ? 900 : member, "AXWindow")
    let button = AXUIElement(member); button.failsPress = pressFails; button.delay = pressDelay
    button.onPress = { [unowned self, weak tab] in
     window.failsCloseRead = closeReadFails
     guard !closeRefused else { return }
     window.control = nil
     if rebuild { for item in group.nodes ?? [] {item.value = nil} } else {tab?.value = nil}
     members.removeAll{$0 == member}
     selected = 900
     group.owner = root
     if changeCount {members.append(777)}
     if rebuild {refresh()} else {group.nodes?.removeAll{$0 === tab}; group.nodes?.last?.value = 1}
     if autoSelectSuccessor && members.count > 1 {group.nodes?.first?.onPress?()}
     group.failsRead = groupReadFailsAfterClose
    }
    window.control = missingButton ? nil : button; group.owner = missingWindow ? nil : window
    if rebuildOnSelection {refresh()}
   }
   return tab
  }
  group.nodes = tabs; savedButtons += tabs
 }
 func close(_ enabled: Bool = true, windowless: Bool = false) -> Bool {
  Defaults.collapse = enabled; AXUIElement.closed = []
  return WindowInfo(axElement: root, closeButton: root.control, isWindowlessApp: windowless).close()
 }
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool) {precondition(condition()); checks += 1}
let differentFolders = Group()
check(differentFolders.close()); check(AXUIElement.closed == [1, 2, 3, 900])
// Every remaining radio button is replaced after Close, as Finder does for different folders.
check(differentFolders.savedButtons.count > 4)
let finderSuccessors = Group(); finderSuccessors.autoSelectSuccessor = true; finderSuccessors.rebuildOnSelection = true
check(finderSuccessors.close()); check(AXUIElement.closed == [1, 2, 3, 900])
let stableButtons = Group(rebuild: false)
check(stableButtons.close()); check(AXUIElement.closed == [1, 2, 3, 900])
let hiddenTabBar = Group(hideLast: true)
check(hiddenTabBar.close()); check(AXUIElement.closed == [1, 2, 3, 900])
let disabled = Group()
check(disabled.close(false)); check(AXUIElement.closed == [900] && disabled.root.reads == 0)
let windowless = Group()
check(!windowless.close(windowless: true)); check(AXUIElement.closed.isEmpty && windowless.root.reads == 0)
let single = Group([])
check(single.close()); check(AXUIElement.closed == [900])
let noTabs = Group(); noTabs.root.nodes = []
check(noTabs.close()); check(AXUIElement.closed == [900])
let nested = Group(); nested.root.nodes = [AXUIElement(902, "AXGroup", [nested.group])]
check(nested.close()); check(AXUIElement.closed == [900])
let browserTabs = Group(); browserTabs.group.nodes = [AXUIElement(1, kAXRadioButtonRole, value: 0), AXUIElement(2, kAXRadioButtonRole, value: 1)]
check(browserTabs.close()); check(AXUIElement.closed == [900])
let unknownValue = Group(); unknownValue.group.nodes?.first?.value = nil
check(unknownValue.close()); check(AXUIElement.closed == [1, 2, 3, 900])
let invalidValue = Group(); invalidValue.group.nodes?.first?.value = 2
check(invalidValue.close()); check(AXUIElement.closed == [900])
let duplicateSelected = Group(); duplicateSelected.group.nodes?.first?.value = 1
check(duplicateSelected.close()); check(AXUIElement.closed == [900])
let noSelected = Group(); noSelected.group.nodes?.last?.value = 0
check(noSelected.close()); check(AXUIElement.closed == [900])
for mode in 0..<6 {
 let g = Group()
 switch mode {
 case 0: g.selectionRefused = true
 case 1: g.missingWindow = true
 case 2: g.missingButton = true
 case 3: g.pressFails = true
 case 4: g.wrongWindow = true
 default: g.closeRefused = true
 }
 check(!g.close()); check(AXUIElement.closed == (mode == 5 ? [1] : []))
}
let concurrentAddition = Group(); concurrentAddition.changeCount = true
check(!concurrentAddition.close()); check(AXUIElement.closed == [1])
for refused in [false, true] {
 let failedConfirmation = Group([1]); failedConfirmation.closeRefused = refused; failedConfirmation.closeReadFails = true
 check(!failedConfirmation.close()); check(AXUIElement.closed == [1])
}
let failedWindowRead = Group(); failedWindowRead.root.failsRead = true
check(!failedWindowRead.close()); check(AXUIElement.closed.isEmpty)
let failedGroupRead = Group(); failedGroupRead.group.failsRead = true
check(!failedGroupRead.close()); check(AXUIElement.closed.isEmpty)
let failedTabRead = Group(); failedTabRead.group.nodes?.first?.failsValueRead = true
check(!failedTabRead.close()); check(AXUIElement.closed.isEmpty)
let failedRefresh = Group(); failedRefresh.groupReadFailsAfterClose = true
check(!failedRefresh.close()); check(AXUIElement.closed == [1])
print("Passed \(checks) native-tab Close assertions, including rebuilt different-folder controls")
let slow = Group(Array(1...8)); slow.pressDelay = 0.03
let metrics = CloseMetrics()
AXUIElement.closed = []; AXUIElement.closeWasOnMainThread = false
let closing = Task { @MainActor in
 await WindowUtil.closeWindows([WindowInfo(axElement: slow.root, closeButton: slow.root.control)], feedback: ActionFeedbackHandle(metrics: metrics))
}
let queuedGroup = Group([100, 101])
let queuedClose = Task { @MainActor in
 await WindowUtil.closeWindows([WindowInfo(axElement: queuedGroup.root, closeButton: queuedGroup.root.control)])
}
queuedClose.cancel()
let closed = await closing.value
let skipped = await queuedClose.value
check(skipped.succeeded.isEmpty && skipped.failed.isEmpty && queuedGroup.root.reads == 0)
check(closed.succeeded.count == 1 && closed.failed.isEmpty)
check(!AXUIElement.closeWasOnMainThread)
check(metrics.progress.map { $0.0 } == Array(0...9))
check(metrics.progress.allSatisfy { $0.1 == 9 })
let stopped = Group()
AXUIElement.closed = []
let stoppedWindow = WindowInfo(axElement: stopped.root, closeButton: stopped.root.control)
let stoppedResult = await Task.detached { [stoppedWindow] in
 stoppedWindow.close { completed, _ in
  if completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
 }
}.value
check(!stoppedResult && AXUIElement.closed == [1])
print("Passed background native Close responsiveness, ordered tab progress and cooperative cancellation checks")
SWIFT
Dir.mktmpdir('dockfork-native-close-') do |dir|
  path = "#{dir}/Checks.swift"
  File.write(path, with_action_ownership(source))
  abort 'Compilation failed' unless system('swiftc', path, '-o', "#{dir}/checks")
  abort 'Checks failed' unless system("#{dir}/checks")
end
