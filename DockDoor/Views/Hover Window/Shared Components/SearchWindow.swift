import AppKit
import Defaults
import SwiftUI

struct SearchFieldView: View {
    let searchField: NSTextField
    @State private var backgroundAppearance: BackgroundAppearance = .resolve()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            SearchTextFieldRepresentable(textField: searchField)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .materialPill(backgroundAppearance: backgroundAppearance)
        .frame(height: 40)
        .task {
            for await _ in Defaults.updates(BackgroundAppearance.observedKeys, initial: true) {
                let updated = BackgroundAppearance.resolve()
                if updated != backgroundAppearance { backgroundAppearance = updated }
            }
        }
    }
}

struct SearchTextFieldRepresentable: NSViewRepresentable {
    let textField: NSTextField

    func makeNSView(context: Context) -> NSTextField {
        textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

class SearchWindow: NSPanel, NSTextFieldDelegate {
    private var searchField: NSTextField!
    private weak var previewCoordinator: PreviewStateCoordinator?

    init(previewCoordinator: PreviewStateCoordinator) {
        self.previewCoordinator = previewCoordinator
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setupWindow()
        setupSearchField()
    }

    var isFocused: Bool {
        (NSApp.keyWindow === self) && (searchField.currentEditor() != nil)
    }

    private func setupWindow() {
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    private func setupSearchField() {
        searchField = NSTextField()
        searchField.placeholderString = "Press \(KeyboardLabel.localizedKey(for: Defaults[.searchTriggerKey])) to search windows…"
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.usesSingleLineMode = true
        searchField.maximumNumberOfLines = 1
        searchField.lineBreakMode = .byClipping
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.isScrollable = true
            cell.lineBreakMode = .byClipping
        }
        searchField.delegate = self

        let searchView = SearchFieldView(searchField: searchField)
        let hostingView = NSHostingView(rootView: searchView)
        hostingView.frame = contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        previewCoordinator?.searchQuery = textField.stringValue
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        configureFieldEditorForSingleLine()
    }

    func showSearch(relativeTo window: NSWindow) {
        guard window.isVisible else { return }

        if parent !== window {
            parent?.removeChildWindow(self)
            window.addChildWindow(self, ordered: .above)
        }

        let frame = window.frame
        if frame.width <= 0 || frame.height <= 0 {
            DispatchQueue.main.async { [weak self] in
                self?.showSearch(relativeTo: window)
            }
            return
        }

        let searchWidth: CGFloat = 300
        let searchHeight: CGFloat = 40
        let gap: CGFloat = -20

        guard let screen = window.screen ?? NSScreen.main else {
            // Fallback: position above
            let searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.maxY + gap,
                width: searchWidth,
                height: searchHeight
            )
            setFrame(searchFrame, display: false)
            orderFront(nil)
            return
        }

        let screenFrame = screen.visibleFrame
        let spaceAbove = screenFrame.maxY - frame.maxY
        let spaceBelow = frame.minY - screenFrame.minY
        let requiredVerticalSpace = searchHeight + gap

        var searchFrame: NSRect

        if spaceAbove >= requiredVerticalSpace {
            // Fits above
            searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.maxY + gap,
                width: searchWidth,
                height: searchHeight
            )
        } else if spaceBelow >= requiredVerticalSpace {
            // Fits below
            searchFrame = NSRect(
                x: frame.midX - searchWidth / 2,
                y: frame.minY - searchHeight - gap,
                width: searchWidth,
                height: searchHeight
            )
        } else {
            // Neither fits - position to the side
            let spaceRight = screenFrame.maxX - frame.maxX
            let spaceLeft = frame.minX - screenFrame.minX

            if spaceRight >= searchWidth + gap {
                // Position to the right
                searchFrame = NSRect(
                    x: frame.maxX + gap,
                    y: frame.maxY - searchHeight,
                    width: searchWidth,
                    height: searchHeight
                )
            } else if spaceLeft >= searchWidth + gap {
                // Position to the left
                searchFrame = NSRect(
                    x: frame.minX - searchWidth - gap,
                    y: frame.maxY - searchHeight,
                    width: searchWidth,
                    height: searchHeight
                )
            } else {
                // No room anywhere - overlay at top of window
                searchFrame = NSRect(
                    x: frame.midX - searchWidth / 2,
                    y: frame.maxY - searchHeight - gap,
                    width: searchWidth,
                    height: searchHeight
                )
            }
        }

        if searchFrame.minX < screenFrame.minX {
            searchFrame.origin.x = screenFrame.minX + 10
        } else if searchFrame.maxX > screenFrame.maxX {
            searchFrame.origin.x = screenFrame.maxX - searchWidth - 10
        }
        if searchFrame.minY < screenFrame.minY {
            searchFrame.origin.y = screenFrame.minY + 10
        } else if searchFrame.maxY > screenFrame.maxY {
            searchFrame.origin.y = screenFrame.maxY - searchHeight - 10
        }

        setFrame(searchFrame, display: false)
        orderFront(nil)
    }

    func hideSearch() {
        parent?.removeChildWindow(self)
        orderOut(nil)
        searchField.stringValue = ""
        previewCoordinator?.searchQuery = ""
    }

    func updateSearchText(_ text: String) {
        guard searchField.stringValue != text else { return }
        searchField.stringValue = text
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    func focusSearchField() {
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            _ = self.makeFirstResponder(self.searchField)
            self.configureFieldEditorForSingleLine()
        }
    }

    private func configureFieldEditorForSingleLine() {
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.maxSize = NSSize(width: .greatestFiniteMagnitude, height: searchField.bounds.height)
        editor.textContainerInset = .zero
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = true
        editor.textContainer?.lineBreakMode = .byClipping
        editor.textContainer?.containerSize = NSSize(width: .greatestFiniteMagnitude, height: searchField.bounds.height)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
