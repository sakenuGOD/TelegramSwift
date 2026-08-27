//
//  ChatSelectText.swift
//  TelegramMac
//
//  Created by keepcoder on 17/11/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
struct SelectContainer {
    let text:NSAttributedString
    let range:NSRange
    let index: Int
    let header:String?
}

class SelectManager : NSResponder {
    fileprivate weak var chatInteraction: ChatInteraction?
    override init() {
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var ranges:Atomic<[(AnyHashable,WeakReference<TextView>, SelectContainer)]> = Atomic(value: [])
    
    func add(range:NSRange, textView: TextView, text: NSAttributedString, header: String?, stableId: AnyHashable, index: Int) {
                
        _ = ranges.modify { ranges in
            var ranges = ranges
            let value = (stableId, WeakReference(value: textView), SelectContainer(text: text, range: range, index: index, header: header))
            if let index = ranges.firstIndex(where: { $0.0 == stableId }) {
                ranges.insert(value, at: index)
            } else {
                ranges.append(value)
            }
            return ranges
        }
    }
    
    func removeAll() {
        _ = ranges.modify { ranges in
            for selection in ranges {
                if let value = selection.1.value {
                    if value.textLayout?.selectedRange.range.location != NSNotFound {
                        value.selectionWasCleared = true
                    }
                    value.textLayout?.clearSelect()
                    value.canBeResponder = true
                    value.setNeedsDisplay()
                }
            }
            return []
        }
    }
    
    func remove(for id:Int64) {
        
    }
    var isEmpty:Bool {
        return ranges.with { $0.isEmpty }
    }
    
    
    var selectedText: NSAttributedString {
        let string:NSMutableAttributedString = NSMutableAttributedString()
        
        let addHeaders: Bool = ranges.with { $0.map { $0.0 } }.uniqueElements.count > 1
        
        ranges.with { ranges in
            
            var stableId: AnyHashable? = ranges.last?.0
            for i in stride(from: ranges.count - 1, to: -1, by: -1) {
                let container = ranges[i].2
                
                if stableId != ranges[i].0 {
                    _ = string.append(string: "\n\n", color: nil, font: .normal(.text))
                }
                
                if let header = container.header, ranges.count > 1, addHeaders {
                    _ = string.append(string: header + "\n", color: nil, font: .normal(.text))
                }
                
                if container.range.location != NSNotFound {
                    if container.range.location != 0, ranges.count > 1, addHeaders {
                        _ = string.append(string: "...", color: nil, font: .normal(.text))
                    }
                    string.append(container.text.attributedSubstring(from: container.range).trimmed)
                    if container.range.location + container.range.length != container.text.length, ranges.count > 1, addHeaders {
                        _ = string.append(string: "...", color: nil, font: .normal(.text))
                    }
                }
                if i != 0, string.string.last != "\n" {
                    string.append(string: "\n")
                }
               
                stableId = ranges[i].0
            }
        }
        return string
    }
    
    @objc func copy(_ sender:Any) {
        
        if let window = self.chatInteraction?.context.window, let peer = self.chatInteraction?.peer, peer.isCopyProtected {
            showProtectedCopyAlert(peer, for: window)
            return
        }
        
        let selectedText = self.selectedText
        if !selectedText.string.isEmpty {
            if !globalLinkExecutor.copyAttributedString(selectedText) {
                NSPasteboard.general.declareTypes([.string], owner: self)
                NSPasteboard.general.setString(selectedText.string, forType: .string)
            }
        } else if let chatInteraction = self.chatInteraction {
            if let selectionState = chatInteraction.presentation.selectionState {
                _ = chatInteraction.context.account.postbox.messagesAtIds(Array(selectionState.selectedIds.sorted(by: <))).start(next: { messages in
                    var text: String = ""
                    for message in messages {
                        if !text.isEmpty {
                            text += "\n\n"
                        }
                        if let forwardInfo = message.forwardInfo {
                            text += "> " + forwardInfo.authorTitle + ":"
                        } else {
                            text += "> " + (message.effectiveAuthor?.displayTitle ?? "") + ":"
                        }
                        text += "\n"
                        text += pullText(from: message).string as String
                    }
                    copyToClipboard(text)
                })
            }
        }
        
    }
    
    func selectNextChar() -> Bool {
        var result: Bool = false
        _ = ranges.modify { ranges in
            var ranges = ranges
            if let last = ranges.last, let textView = last.1.value {
                if last.2.range.max < last.2.text.length, let layout = textView.textLayout {
                    
                    var range = last.2.range
                    
                    switch layout.selectedRange.cursorAlignment {
                    case let .min(cursorAlignment), let .max(cursorAlignment):
                        if range.min >= cursorAlignment {
                            range.length += 1
                        } else {
                            range.location += 1
                            if range.length > 1 {
                                range.length -= 1
                            }
                        }
                    }
                    let location = min(max(0, range.location), last.2.text.length)
                    let length = max(min(range.length, last.2.text.length - location), 0)
                    range = NSMakeRange(location, length)
                    
                    layout.selectedRange.range = range
                    ranges[ranges.count - 1] = (last.0, last.1, SelectContainer(text: last.2.text, range: range, index: last.2.index, header: last.2.header))
                    textView.needsDisplay = true
                    result = true
                    return ranges
                }
            }
            result = false
            return ranges
        }
        return result
    }
    
    func selectPrevChar() -> Bool {
        var result: Bool = false
        _ = ranges.modify { ranges in
            var ranges = ranges
            if let first = ranges.first, let textView = first.1.value, textView.window?.isKeyWindow == true {
                if let layout = textView.textLayout {
                    
                    var range = first.2.range
                    
                    switch layout.selectedRange.cursorAlignment {
                    case let .min(cursorAlignment), let .max(cursorAlignment):
                        if range.location >= cursorAlignment {
                            if range.length > 1 {
                                range.length -= 1
                            } else {
                                range.location -= 1
                            }
                        } else {
                            if range.location > 0 {
                                range.location -= 1
                                range.length += 1
                            }
                        }
                    }
                    
                    let location = min(max(0, range.location), first.2.text.length)
                    let length = max(min(range.length, first.2.text.length - location), 0)
                    range = NSMakeRange(location, length)
                    layout.selectedRange.range = range
                    ranges[0] = (first.0, first.1, SelectContainer(text: first.2.text, range: range, index: first.2.index, header: first.2.header))
                    textView.needsDisplay = true
                    result = true
                    return ranges
                }
            }
            result = false
            return ranges
        }
        return result
    }
    
    func find(_ stableId:AnyHashable) -> NSRange? {
        return ranges.with { ranges -> NSRange? in
            for range in ranges {
                if range.0 == stableId {
                    return range.2.range
                }
            }
            return nil
        }
    }
    
    func findAll(_ stableId:AnyHashable) -> [(NSRange, Int)] {
        return ranges.with { ranges -> [(NSRange, Int)] in
            var list: [(NSRange, Int)] = []
            for range in ranges {
                if range.0 == stableId {
                    list.append((range.2.range, range.2.index))
                }
            }
            return list
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        removeAll()
        return true
    }
}

let selectManager:SelectManager = SelectManager()

func initializeSelectManager() {
    _ = selectManager.isEmpty
}

protocol MultipleSelectable {
    var selectableTextViews:[TextView] { get }
    var header: String? { get }
}

class ChatSelectText : NSObject {
    
    private var beginInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private var endInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private let table:TableView
    private var deselect:Bool = false
    private var started:Bool = false
    private var startMessageId:MessageId? = nil
    private var lastPressureEventStage = 0
    private var inPressedState = false
    private var locationInWindow: NSPoint? = nil
    private var reversible: Bool = false
    
    private var lastSelectdMessageId: MessageId?
    
    init(_ table:TableView) {
        self.table = table
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    func initializeHandlers(for window:Window, chatInteraction:ChatInteraction) {
        
        self.reversible = chatInteraction.mode.isSavedMode
        
        selectManager.chatInteraction = chatInteraction
        
        table.addScroll(listener: TableScrollListener (dispatchWhenVisibleRangeUpdated: false, { [weak table] _ in
            table?.enumerateVisibleViews(with: { view in
                view.updateMouse(animated: true)
            })
        }))
        
        window.set(mouseHandler: { [weak table] event -> KeyHandlerResult in
            
            table?.enumerateVisibleViews(with: { view in
                view.updateMouse(animated: true)
            })
            
            return .rejected
        }, with: self, for: .mouseMoved, priority:.medium)
        
        window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            
            self?.started = false
            self?.inPressedState = false
            self?.locationInWindow = event.locationInWindow
            
            if let table = self?.table, let superview = table.superview, let documentView = table.documentView {
                let point = superview.convert(event.locationInWindow, from: nil)
                let documentPoint = documentView.convert(event.locationInWindow, from: nil)
                let row = table.row(at: documentPoint)
                
                var isCurrentTableView: (NSView?)->Bool = { _ in return false}
                
                isCurrentTableView = { [weak table] view in
                    if view === table {
                        return true
                    } else if let superview = view?.superview {
                        if superview is TableView, view is TableRowView || view is NSClipView {
                            return isCurrentTableView(superview)
                        } else if superview is TableView {
                            return false
                        } else {
                            return isCurrentTableView(superview)
                        }
                    } else {
                        return false
                    }
                }
                
                if row < 0 || (!NSPointInRect(point, table.frame) || hasModals(window) || (!table.item(at: row).canMultiselectTextIn(event.locationInWindow) && chatInteraction.presentation.state != .selecting)) || !isCurrentTableView(window.contentView?.hitTest(event.locationInWindow)) {
                    self?.beginInnerLocation = NSZeroPoint
                } else {
                    self?.beginInnerLocation = documentPoint
                }
                
                
                if row != -1, let item = table.item(at: row) as? ChatRowItem, let view = item.view as? ChatRowView {
                    if chatInteraction.presentation.state == .selecting || (theme.bubbled && !NSPointInRect(view.convert(event.locationInWindow, from: nil), view.bubbleFrame(item))) {
                        if self?.startMessageId == nil {
                            self?.startMessageId = item.message?.id
                        }
                        self?.deselect = !view.isSelectInGroup(event.locationInWindow)
                    }
                }
                
                self?.started = self?.beginInnerLocation != NSZeroPoint
                if self?.started == true, row != -1 {
                    if chatInteraction.presentation.state == .selecting, let deselect = self?.deselect {
                        let item = table.item(at: row) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
            }
            
            return .invokeNext
        }, with: self, for: .leftMouseDown, priority:.medium)
        
        window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            
            self?.beginInnerLocation = NSZeroPoint
            self?.locationInWindow = nil
            
            Queue.mainQueue().justDispatch {
                guard let table = self?.table else {return}
                guard let documentView = table.documentView else {return}
                
                var cleanStartId: Bool = false
                let documentPoint = documentView.convert(event.locationInWindow, from: nil)
                let row = table.row(at: documentPoint)
                 if chatInteraction.presentation.state != .selecting {
                    if let view = table.viewNecessary(at: row) as? ChatRowView, !view.canStartTextSelecting(event) {
                        self?.beginInnerLocation = NSZeroPoint
                    }
                    cleanStartId = true
                }
               
                
                let point = self?.table.documentView?.convert(event.locationInWindow, from: nil) ?? NSZeroPoint
                if let index = self?.table.row(at: point), index > 0, let item = self?.table.item(at: index), let view = item.view as? ChatRowView {
                    
                    if event.clickCount > 1, selectManager.isEmpty {
                        if !view.isAllowedToDoubleAction(view.convert(event.locationInWindow, from: nil)) {
                            var set: Bool = false
                            inner: for view in view.selectableTextViews {
                                if view == window.firstResponder {
                                    _ = window.makeFirstResponder(view)
                                    set = true
                                    break inner
                                }
                            }
                            if !set {
                                _ = window.makeFirstResponder(view.selectableTextViews.first)
                            }
                        }
                    }

                    if chatInteraction.presentation.reportMode == nil {
                        if view.canDropSelection(in: event.locationInWindow) {
                            if let result = chatInteraction.presentation.selectionState?.selectedIds.isEmpty, result {
                                self?.startMessageId = nil
                                chatInteraction.update({$0.withoutSelectionState()})
                            }
                        }
                    }
                } else {
                    if chatInteraction.presentation.reportMode == nil {
                        if let result = chatInteraction.presentation.selectionState?.selectedIds.isEmpty, result {
                            self?.startMessageId = nil
                            chatInteraction.update({$0.withoutSelectionState()})
                        }
                    }
                }
                if cleanStartId {
                    self?.startMessageId = nil
                }
            }
            return .invokeNext
        }, with: self, for: .leftMouseUp, priority:.medium)
        
        window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            
            guard let `self` = self else {return .rejected}
            
            self.endInnerLocation = self.table.documentView?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? NSZeroPoint
            
            if self.started {
                self.started = !hasPopover(window) && self.beginInnerLocation != NSZeroPoint
            }
            if event.clickCount > 1 {
                self.started = false
            }
            
           // NSLog("\(!NSPointInRect(event.locationInWindow, window.bounds))")
            
            if self.started {
                self.table.clipView.autoscroll(with: event)
                if chatInteraction.presentation.state != .selecting {
                    if !self.inPressedState {
                        self.runSelector(window: window, chatInteraction: chatInteraction)
                        if window.firstResponder != selectManager {
                            _ = window.makeFirstResponder(selectManager)
                        }
                    }
                    return .invoked
                    
                } else if chatInteraction.presentation.state == .selecting {
                    self.runSelector(false, window: window, chatInteraction: chatInteraction)
                    return .invokeNext
                }
            }
            return .invokeNext
        }, with: self, for: .leftMouseDragged, priority:.medium)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            guard let `self` = self else { return .rejected }
            if event.stage == 2 && self.lastPressureEventStage < 2 {
                self.inPressedState = true
            }
            self.lastPressureEventStage = event.stage
            return .rejected
        }, with: self, for: .pressure, priority: .medium)
        
        window.set(handler: { _ -> KeyHandlerResult in
            
            return .rejected
        }, with: self, for: .A, priority: .medium, modifierFlags: [.command])
    }
    
    private func runSelector(_ selectingText:Bool = true, window: Window, chatInteraction:ChatInteraction) {
        
        
        var startIndex = table.row(at: beginInnerLocation)
        var endIndex = table.row(at: endInnerLocation)
        
                
        let reversed = endIndex < startIndex;
        
        if(endIndex < startIndex) {
            startIndex = startIndex + endIndex;
            endIndex = startIndex - endIndex;
            startIndex = startIndex - endIndex;
        }
        
        if startIndex < 0 || endIndex < 0 {
            return
        }
        
        let beginRow = table.row(at: beginInnerLocation)
        if  let view = table.item(at: beginRow).view as? ChatRowView, let item = view.item as? ChatRowItem, selectingText, table._mouseInside() {
            let rowPoint = view.convert(beginInnerLocation, from: table.documentView)
            if (!NSPointInRect(rowPoint, view.bubbleFrame(item)) && theme.bubbled) {
                if startIndex != endIndex || abs(beginInnerLocation.y - endInnerLocation.y) > 10 {
                    for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                        let item = table.item(at: i) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
                return
            }
        }

        if selectingText {
            
            selectManager.removeAll()
            
            let isMultiple = abs(endIndex - startIndex) > 0;
            
            for i in startIndex ... endIndex  {
                let view = table.viewNecessary(at: i) as? MultipleSelectable
                if let views = view?.selectableTextViews {
                    
                    var start_j:Int? = nil
                    var end_j:Int? = nil
                    
                    inner: for j in 0 ..< views.count {
                        let selectableView = views[j]
                        var viewRect: NSRect
                        if let view = selectableView.superview, view.frame.height < selectableView.frame.height {
                            viewRect = view.convert(CGRect(origin: .zero, size: view.frame.size), to: table.documentView)
                        } else {
                            viewRect = selectableView.convert(CGRect(origin: .zero, size: selectableView.frame.size), to: table.documentView)
                        }
                        let rect = NSRect(x: viewRect.midX, y: min(beginInnerLocation.y, endInnerLocation.y), width: abs(endInnerLocation.x - beginInnerLocation.x), height: abs(endInnerLocation.y - beginInnerLocation.y))
                        
                        if rect.intersects(viewRect) {
                            if start_j == nil {
                                start_j = j
                            } else {
                                start_j = min(start_j!, j)
                            }
                            if end_j == nil {
                                end_j = j
                            } else {
                                end_j = max(end_j!, j)
                            }
                        }
                    }
                    
                    for j in 0 ..< views.count {
                        let selectableView = views[j]
                        
                        if let layout = selectableView.textLayout {
                            let beginViewLocation = selectableView.convert(beginInnerLocation, from: table.documentView)
                            let endViewLocation = selectableView.convert(endInnerLocation, from: table.documentView)
                            
                            var startPoint:NSPoint = NSZeroPoint
                            var endPoint:NSPoint = NSZeroPoint
                            
                            if i == startIndex && i == endIndex {
                                
                            }
                            
                           
                            let fillEnd = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude)
                            
                            if (i > startIndex && i < endIndex) {
                                startPoint = NSMakePoint(0, 0);
                                endPoint = fillEnd;
                            } else if(i == startIndex) {
                                if(!isMultiple) {
                                    startPoint = beginViewLocation;
                                    endPoint = endViewLocation;
                                } else {
                                    if(!reversed) {
                                        if reversible {
                                            startPoint = beginViewLocation
                                            endPoint = fillEnd;
                                        } else {
                                            startPoint = beginViewLocation
                                            endPoint = NSMakePoint(0, 0);
                                        }
                                    } else {
                                        if reversible {
                                            startPoint = fillEnd;
                                            endPoint = endViewLocation;
                                        } else {
                                            startPoint = NSMakePoint(0, 0);
                                            endPoint = endViewLocation;
                                        }
                                    }
                                }
                                
                            } else if(i == endIndex) {
                                if(!reversed) {
                                    if reversible {
                                        startPoint = .zero;
                                        endPoint = endViewLocation;
                                    } else {
                                        startPoint = fillEnd;
                                        endPoint = endViewLocation;
                                    }
                                } else {
                                    startPoint = beginViewLocation;
                                    if reversible {
                                        endPoint = .zero
                                    } else {
                                        endPoint = fillEnd;
                                    }
                                }
                            }
                            
                            
                            if let start_j, let end_j, i == endIndex || i == startIndex {

                                if j < start_j || j > end_j {
                                    continue
                                } else {
                                    if end_j - start_j > 0 {
                                        if beginInnerLocation.y > endInnerLocation.y {
                                            if j <= start_j {
                                                endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            } else {
                                                startPoint = .zero
                                                if j < end_j {
                                                    endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            }
                                        } else if beginInnerLocation.y < endInnerLocation.y {
                                            if j > start_j {
                                                endPoint = .zero
                                                if j < end_j {
                                                    startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            } else {
                                                startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            }
                                        }
                                    }
                                    
                                }
                            }
                            
                            
                            selectableView.canBeResponder = false
                            layout.selectedRange.range = layout.selectedRange(startPoint:startPoint, currentPoint:endPoint)
                            layout.selectedRange.cursorAlignment = startPoint.x > endPoint.x ? .min(layout.selectedRange.range.max) : .max(layout.selectedRange.range.min)
                            selectManager.add(range: layout.selectedRange.range, textView: selectableView, text:layout.attributedString, header: j == 0 ? view?.header : nil, stableId: table.item(at: i).stableId, index: j)
                            selectableView.setNeedsDisplayLayer()
                            
                            
                        }
                    }
                }
                
            }
        } else {
            if chatInteraction.presentation.state == .selecting {
                for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                    let item = table.item(at: i) as? ChatRowItem
                    if let view = item?.view as? ChatRowView {
                        view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                    }
                }
            }
            
        }
        
    }
    
    func removeHandlers(for window:Window) {
        window.removeAllHandlers(for: self)
    }
    
}

private func aiContextResourceData(
    context: AccountContext,
    resource: TelegramMediaResource,
    reference: MediaResourceReference,
    userLocation: MediaResourceUserLocation,
    userContentType: MediaResourceUserContentType
) -> Signal<Data?, NoError> {
    let mediaBox = context.account.postbox.mediaBox
    let signal = Signal<Data?, NoError> { subscriber in
        let fetchDisposable = fetchedMediaResource(
            mediaBox: mediaBox,
            userLocation: userLocation,
            userContentType: userContentType,
            reference: reference,
            statsCategory: .image
        ).start()

        let dataDisposable = mediaBox.resourceData(resource).start(next: { data in
            guard data.complete else {
                return
            }
            let value = data.size == 0 ? nil : try? Data(contentsOf: URL(fileURLWithPath: data.path), options: .mappedIfSafe)
            subscriber.putNext(value)
            subscriber.putCompletion()
        })

        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
        }
    }

    return signal
    |> take(1)
    |> timeout(90.0, queue: .mainQueue(), alternate: .single(nil))
}

private func aiContextPreviewData(for message: Message, context: AccountContext) -> Signal<Data?, NoError> {
    for media in message.media {
        if let image = media as? TelegramMediaImage, let representation = image.representations.last {
            let imageReference = ImageMediaReference.message(message: MessageReference(message), media: image)
            return aiContextResourceData(
                context: context,
                resource: representation.resource,
                reference: imageReference.resourceReference(representation.resource),
                userLocation: imageReference.userLocation,
                userContentType: imageReference.userContentType
            )
        }

        if let file = media as? TelegramMediaFile, file.isVideo || file.probablySticker {
            let fileReference = FileMediaReference.message(message: MessageReference(message), media: file)
            if let representation = file.previewRepresentations.last {
                return aiContextResourceData(
                    context: context,
                    resource: representation.resource,
                    reference: fileReference.resourceReference(representation.resource),
                    userLocation: fileReference.userLocation,
                    userContentType: fileReference.userContentType
                )
            }
            if file.probablySticker {
                // Static stickers do not always carry a separate thumbnail.
                // Their WebP resource is directly renderable by AppKit.
                return aiContextResourceData(
                    context: context,
                    resource: file.resource,
                    reference: fileReference.resourceReference(file.resource),
                    userLocation: fileReference.userLocation,
                    userContentType: fileReference.userContentType
                )
            }
        }
    }
    return .single(nil)
}

private func aiContextHasVisualMedia(_ message: Message) -> Bool {
    return message.media.contains { media in
        if media is TelegramMediaImage {
            return true
        }
        if let file = media as? TelegramMediaFile {
            return file.isVideo || file.probablySticker
        }
        return false
    }
}

private func aiContextReplySummary(_ message: Message) -> String? {
    guard let reply = message.replyAttribute else {
        return nil
    }
    let repliedMessage = message.associatedMessages[reply.messageId]
    let author = repliedMessage?.effectiveAuthor?.displayTitle ?? "сообщение"
    let sourceText = reply.quote?.text ?? repliedMessage?.text ?? ""
    let compactText = sourceText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if compactText.isEmpty {
        return "Ответ на \(author)"
    }
    return "Ответ на \(author): \(String(compactText.prefix(280)))"
}

private func aiContextMarkdown(messages: [Message], chatTitle: String) -> String? {
    guard let first = messages.first, let last = messages.last else {
        return nil
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"

    var output = "# Контекст из Telegram\n\n"
    output += "Чат: \(chatTitle)  \n"
    output += "Период: \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(first.timestamp)))) — \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(last.timestamp))))\n\n"

    for message in messages {
        let author = message.forwardInfo?.authorTitle ?? message.effectiveAuthor?.displayTitle ?? "Неизвестный автор"
        let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
        output += "## [\(formatter.string(from: date))] \(author)\n\n"

        if let reply = aiContextReplySummary(message) {
            output += "> \(reply)\n\n"
        }

        if !message.text.isEmpty {
            output += message.text + "\n\n"
        }

        if let transcription = message.audioTranscription, !transcription.text.isEmpty, !transcription.isPending {
            let isCircle = (message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile)?.isInstantVideo == true
            output += isCircle ? "**Расшифровка кружка:**\n\n" : "**Расшифровка голосового:**\n\n"
            output += transcription.text + "\n\n"
        } else if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            if file.isVoice {
                output += "_[Голосовое сообщение без готовой расшифровки]_\n\n"
            } else if file.isInstantVideo {
                output += "_[Кружок без готовой расшифровки]_\n\n"
            }
        }
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("TelegramAIExports", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeTitle = chatTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    let nameFormatter = DateFormatter()
    nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
    let url = directory.appendingPathComponent("\(safeTitle)_\(nameFormatter.string(from: Date())).md")
    do {
        try output.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    } catch {
        return nil
    }
}

private func aiContextAppend(_ text: String, to result: NSMutableAttributedString, font: NSFont, color: NSColor = .textColor, paragraphSpacing: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.paragraphSpacing = paragraphSpacing
    style.lineSpacing = 2
    result.append(NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]))
}

private func aiContextImage(from data: Data, maxPixelDimension: CGFloat = 1600, maxDisplaySize: NSSize = NSMakeSize(440, 480)) -> NSImage? {
    guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else {
        return nil
    }
    let pixelScale = min(1.0, maxPixelDimension / max(source.size.width, source.size.height))
    let pixelSize = NSMakeSize(max(1, floor(source.size.width * pixelScale)), max(1, floor(source.size.height * pixelScale)))
    let displayScale = min(1.0, min(maxDisplaySize.width / source.size.width, maxDisplaySize.height / source.size.height))
    let displaySize = NSMakeSize(floor(source.size.width * displayScale), floor(source.size.height * displayScale))
    let result = NSImage(size: pixelSize)
    result.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: pixelSize)).fill()
    source.draw(in: NSRect(origin: .zero, size: pixelSize), from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1.0)
    result.unlockFocus()

    // Keep the PDF compact for model input. Text and transcriptions remain
    // lossless; only photographic pixels are resized and JPEG-compressed.
    if let tiffData = result.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]),
       let compressed = NSImage(data: jpegData) {
        compressed.size = displaySize
        return compressed
    }
    result.size = displaySize
    return result
}

private func aiContextPDF(messages: [Message], previews: [Data?], chatTitle: String) -> String? {
    guard !messages.isEmpty else {
        return nil
    }

    let result = NSMutableAttributedString()
    aiContextAppend("Контекст из Telegram\n", to: result, font: .boldSystemFont(ofSize: 22))
    aiContextAppend("Чат: \(chatTitle)\n", to: result, font: .systemFont(ofSize: 12), color: .darkGray)

    let firstDate = Date(timeIntervalSince1970: TimeInterval(messages.first!.timestamp))
    let lastDate = Date(timeIntervalSince1970: TimeInterval(messages.last!.timestamp))
    let periodFormatter = DateFormatter()
    periodFormatter.locale = Locale(identifier: "ru_RU")
    periodFormatter.dateStyle = .medium
    periodFormatter.timeStyle = .short
    aiContextAppend("Период: \(periodFormatter.string(from: firstDate)) — \(periodFormatter.string(from: lastDate))\n\n", to: result, font: .systemFont(ofSize: 11), color: .darkGray, paragraphSpacing: 8)

    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "ru_RU")
    timeFormatter.dateFormat = "dd.MM.yyyy HH:mm"

    for (index, message) in messages.enumerated() {
        let author = message.forwardInfo?.authorTitle ?? message.effectiveAuthor?.displayTitle ?? "Неизвестный автор"
        let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
        aiContextAppend("[\(timeFormatter.string(from: date))] \(author)\n", to: result, font: .boldSystemFont(ofSize: 12), color: NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.62, alpha: 1.0))

        if let reply = aiContextReplySummary(message) {
            aiContextAppend("↳ \(reply)\n", to: result, font: .italic(10), color: .gray)
        }

        var renderedPreview = false
        if let preview = previews[index], let image = aiContextImage(from: preview) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            result.append(NSAttributedString(attachment: attachment))
            aiContextAppend("\n", to: result, font: .systemFont(ofSize: 11))
            renderedPreview = true
        }

        if !renderedPreview {
            if message.media.contains(where: { $0 is TelegramMediaImage }) {
                aiContextAppend("[Фотография: предпросмотр недоступен]\n", to: result, font: .italic(11), color: .gray)
            } else if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isVideo, !file.probablySticker {
                let kind = file.isInstantVideo ? "Кружок" : "Видео"
                aiContextAppend("[\(kind): предпросмотр недоступен]\n", to: result, font: .italic(11), color: .gray)
            }
        }

        if !message.text.isEmpty {
            aiContextAppend(message.text + "\n", to: result, font: .systemFont(ofSize: 12))
        }

        if let sticker = message.media.first(where: { ($0 as? TelegramMediaFile)?.probablySticker == true }) as? TelegramMediaFile {
            let emoji = sticker.stickerText?.normalizedEmoji ?? ""
            aiContextAppend(emoji.isEmpty ? "[Стикер]\n" : "[Стикер: \(emoji)]\n", to: result, font: .italic(11), color: .gray)
        }

        if let transcription = message.audioTranscription, !transcription.text.isEmpty, !transcription.isPending {
            let kind: String
            if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isInstantVideo {
                kind = "Расшифровка кружка"
            } else {
                kind = "Расшифровка голосового"
            }
            aiContextAppend("\(kind):\n", to: result, font: .boldSystemFont(ofSize: 11), color: .darkGray)
            aiContextAppend(transcription.text + "\n", to: result, font: .systemFont(ofSize: 12))
        } else if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile {
            if file.isVoice {
                aiContextAppend("[Голосовое сообщение без готовой расшифровки]\n", to: result, font: .italic(11), color: .gray)
            } else if file.isInstantVideo {
                aiContextAppend("[Кружок без готовой расшифровки]\n", to: result, font: .italic(11), color: .gray)
            }
        }

        aiContextAppend("\n", to: result, font: .systemFont(ofSize: 8), paragraphSpacing: 10)
    }

    let contentWidth: CGFloat = 500
    let textView = NSTextView(frame: NSMakeRect(0, 0, contentWidth, 100))
    textView.isEditable = false
    textView.isRichText = true
    textView.drawsBackground = true
    textView.backgroundColor = .white
    textView.textContainerInset = NSMakeSize(24, 24)
    textView.textContainer?.containerSize = NSMakeSize(contentWidth - 48, .greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textStorage?.setAttributedString(result)
    if let textContainer = textView.textContainer, let layoutManager = textView.layoutManager {
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height + 48)
        textView.setFrameSize(NSMakeSize(contentWidth, max(usedHeight, 100)))
    }

    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
    printInfo.paperSize = NSMakeSize(595, 842)
    printInfo.leftMargin = 36
    printInfo.rightMargin = 36
    printInfo.topMargin = 36
    printInfo.bottomMargin = 36
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .automatic

    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("TelegramAIExports", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeTitle = chatTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
    let path = directory.appendingPathComponent("\(safeTitle)_\(dateFormatter.string(from: Date())).pdf").path

    let operation = NSPrintOperation.pdfOperation(with: textView, inside: textView.bounds, toPath: path, printInfo: printInfo)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    return operation.run() ? path : nil
}

extension ChatInteraction {
    func exportSelectedMessagesForAI() {
        guard let selectedIds = presentation.selectionState?.selectedIds, !selectedIds.isEmpty else {
            return
        }
        let context = self.context
        let chatTitle = presentation.peer?.displayTitle ?? "Telegram"
        let messages = context.account.postbox.messagesAtIds(Array(selectedIds))
        |> mapToSignal { messages -> Signal<String?, NoError> in
            let sortedMessages = messages.sorted(by: { MessageIndex($0) < MessageIndex($1) })
            guard !sortedMessages.isEmpty else {
                return .single(nil)
            }
            if !sortedMessages.contains(where: aiContextHasVisualMedia) {
                return .single(aiContextMarkdown(messages: sortedMessages, chatTitle: chatTitle))
            }
            let previewSignals = sortedMessages.map { aiContextPreviewData(for: $0, context: context) }
            return combineLatest(previewSignals)
            |> deliverOnMainQueue
            |> map { previews in
                return aiContextPDF(messages: sortedMessages, previews: previews, chatTitle: chatTitle)
            }
        }
        |> deliverOnMainQueue

        _ = showModalProgress(signal: messages, for: context.window, timeout: 0.2).start(next: { path in
            guard let path = path else {
                alert(for: context.window, info: "Не удалось собрать документ.")
                return
            }
            showModal(with: ShareModalController(ShareAIContextFileObject(context, path: path)), for: context.window)
        })
    }
}
