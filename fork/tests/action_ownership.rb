#!/usr/bin/env ruby
# Exercise production request ownership with held operations, never real applications.
require 'tmpdir'
require_relative 'support/action_ownership'
source = <<~'SWIFT'
import Foundation
struct PreviewWindowIdentity: Hashable, Sendable { let pid: Int32; let windowID: Int }
extension WindowActionOwnership {
 var testRequests: Int { lock.withLock { records.count } }
}
@MainActor final class Gate {
 var started = false
 private var continuation: CheckedContinuation<Void, Never>?
 func hold() async { started = true; await withCheckedContinuation { continuation = $0 } }
 func release() { continuation?.resume(); continuation = nil }
}
@main struct Checks {
 @MainActor static func until(_ condition: () -> Bool) async {
  for _ in 0..<10000 { if condition() { return }; await Task.yield() }
  preconditionFailure("Operation did not reach its checkpoint")
 }
 @MainActor static func main() async {
  let owner = WindowActionOwnership.shared
  let a = PreviewWindowIdentity(pid: 1, windowID: 1), sibling = PreviewWindowIdentity(pid: 1, windowID: 2)
  let b = PreviewWindowIdentity(pid: 2, windowID: 1)
  let batchGate = Gate()
  let batch = Task { await WindowActionRequest.run([a, sibling]) { request in
   precondition(WindowActionRequest.current?.token == request.token)
   await batchGate.hold()
   let nested = await WindowActionRequest.run([a]) { child in child.token == request.token }
   let outside: Bool? = await WindowActionRequest.run([b], atomic: true) { _ in preconditionFailure("Parent scope expanded") }
   precondition(nested == true && outside == nil)
   return true
  } }
  await until { batchGate.started }
  let rejected: Bool? = await WindowActionRequest.run([a]) { _ in preconditionFailure("Busy operation executed") }
  precondition(rejected == nil)
  let separate = await WindowActionRequest.run([b]) { _ in true }
  precondition(separate == true && !batch.isCancelled)
  batchGate.release(); let completed = await batch.value
  precondition(completed == true && owner.testRequests == 0)

  let oldGate = Gate(); var events: [String] = []
  let old = Task { await WindowActionRequest.run([a]) { _ in
   await oldGate.hold()
   defer { events.append("cleanup") }
   return !Task.isCancelled
  } }
  await until { oldGate.started }
  let middle = Task { await WindowActionRequest.run([a]) { _ in events.append("middle"); return true } }
  await until { owner.testRequests == 2 }
  let latest = Task { await WindowActionRequest.run([a]) { _ in events.append("latest"); return true } }
  await until { owner.testRequests == 3 }
  precondition(events.isEmpty, "Replacement overtook in-flight cleanup")
  let unrelated = await WindowActionRequest.run([b]) { _ in true }
  precondition(unrelated == true, "Cleanup blocked an unrelated app")
  oldGate.release()
  let oldResult = await old.value, middleResult = await middle.value, latestResult = await latest.value
  precondition(oldResult == false && middleResult == nil && latestResult == true)
  precondition(events == ["cleanup", "latest"] && owner.testRequests == 0, "Cancelled intents executed or ownership leaked")

  let protected = owner.begin([a], protect: true)
  let free = owner.begin([b])
  let atomic: Bool? = await WindowActionRequest.run([a, b], atomic: true) { _ in preconditionFailure("Partial linked transaction executed") }
  precondition(atomic == nil && free.contains(b), "Atomic refusal cancelled an unrelated participant")
  protected.finish(); free.finish()

  let parent = owner.begin([a]), busySibling = owner.begin([sibling], protect: true)
  precondition(!parent.reserveApp(1) && busySibling.contains(sibling))
  busySibling.finish(); precondition(parent.reserveApp(1))
  precondition(parent.contains(PreviewWindowIdentity(pid: 1, windowID: 900)))
  let blockedApp = owner.begin([sibling]); precondition(blockedApp.admitted.isEmpty)
  parent.finish()

  let active = owner.begin([a], protect: true)
  let refused = owner.begin([a]); precondition(refused.admitted.isEmpty && active.mayForeground)
  let newer = owner.begin([b]); precondition(!active.mayForeground && newer.mayForeground)
  newer.finish(); precondition(!active.mayForeground, "Old request reclaimed focus after newer completion")
  active.finish()
  precondition(owner.testRequests == 0)
  print("PASS production ownership: independent/busy targets, inherited scope, cleanup-before-replacement, rapid supersession without replay, atomic linked refusal, app upgrades, focus ownership and zero retained records")
 }
}
SWIFT
Dir.mktmpdir('dockfork-action-ownership-') do |dir|
  file = "#{dir}/checks.swift"
  File.write(file, with_action_ownership(source))
  abort 'Ownership fixture compilation failed' unless system('swiftc', '-swift-version', '5', '-parse-as-library', file, '-o', "#{dir}/checks")
  abort 'Ownership fixture failed' unless system("#{dir}/checks")
end
