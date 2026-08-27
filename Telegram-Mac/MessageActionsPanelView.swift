//
//  MessageActionsPanelView.swift
//  Telegram-Mac
//
//  Created by keepcoder on 31/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

import Postbox



class MessageActionsPanelView: Control, Notifable {
    
    private let deleteButton:TextButton = TextButton()
    private let exportButton:TextButton = TextButton()
    private let forwardButton:TextButton = TextButton()
    private let countTitle:TextView = TextView()
        
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        self.countTitle.userInteractionEnabled = false
        self.countTitle.isSelectable = false
        
        deleteButton.disableActions()
        exportButton.disableActions()
        forwardButton.disableActions()
    
        
        forwardButton.direction = .right
        addSubview(deleteButton)
        addSubview(exportButton)
        addSubview(forwardButton)
        addSubview(countTitle)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    private var buttonActiveStyle:ControlStyle {
        return ControlStyle(font:.normal(.header), foregroundColor: theme.colors.grayText, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentIcon)
    }
    private var deleteButtonActiveStyle:ControlStyle {
        return ControlStyle(font:.normal(.header), foregroundColor: theme.colors.grayText, backgroundColor: theme.colors.background, highlightColor: theme.colors.redUI)
    }
    private var countStyle:ControlStyle {
        return ControlStyle(font:.normal(.header), foregroundColor: theme.colors.grayText, backgroundColor: theme.colors.background, highlightColor: theme.colors.text)
    }

    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.needsLayout = true
    }
    
    override func layout() {
        super.layout()
        deleteButton.centerY(x:20)
        forwardButton.centerY(x:frame.width - forwardButton.frame.width - 20)
        exportButton.centerY(x:forwardButton.frame.minX - exportButton.frame.width - 24)

        let countMinX = deleteButton.frame.maxX + 20
        let countMaxX = exportButton.frame.minX - 20
        countTitle.resize(max(40, countMaxX - countMinX))
        countTitle.centerY(x: countMinX)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var chatInteraction:ChatInteraction?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    private func updateUI(_ canDelete:Bool , _ canForward:Bool, _ count:Int) -> Void {
        deleteButton.userInteractionEnabled = canDelete
        exportButton.userInteractionEnabled = canForward && count > 0
        forwardButton.userInteractionEnabled = canForward
        
        deleteButton.set(color: !canDelete ? theme.colors.grayText : theme.colors.redUI, for: .Normal)
        exportButton.set(color: exportButton.userInteractionEnabled ? theme.colors.accent : theme.colors.grayText, for: .Normal)
        forwardButton.set(color: !canForward ? theme.colors.grayText : theme.colors.accent, for: .Normal)

        deleteButton.set(text: leftText, for: .Normal)
        exportButton.set(text: "Для ИИ", for: .Normal)
        forwardButton.set(text: rightText, for: .Normal)

        if let leftIcon = leftIcon {
            deleteButton.set(image: leftIcon, for: .Normal)
        } else {
            deleteButton.removeImage(for: .Normal)
        }
        if let rightIcon = rightIcon {
            forwardButton.set(image: rightIcon, for: .Normal)
        } else {
            forwardButton.removeImage(for: .Normal)
        }
        
        deleteButton.scaleOnClick = true
        exportButton.scaleOnClick = true
        forwardButton.scaleOnClick = true

        deleteButton.set(color: !deleteButton.userInteractionEnabled ? theme.colors.grayIcon : leftColor, for: .Normal)
        exportButton.set(color: !exportButton.userInteractionEnabled ? theme.colors.grayIcon : theme.colors.accent, for: .Normal)
        forwardButton.set(color: !forwardButton.userInteractionEnabled ? theme.colors.grayIcon : rightColor, for: .Normal)

        let text = count == 0 ? strings().messageActionsPanelEmptySelected : strings().messageActionsPanelSelectedCountCountable(count)
        let color = (!canForward && !canDelete) || count == 0 ? theme.colors.grayText : theme.colors.text
        let layout = TextViewLayout(.initialize(string: text, color: color, font: .medium(.title)), maximumNumberOfLines: 1, truncationType: .middle)
        
        countTitle.update(layout)
        needsLayout = true
    }
    
    func notify(with value: Any, oldValue: Any, animated:Bool) {
        if let value = value as? ChatPresentationInterfaceState, let selectionState = value.selectionState {
            if value.reportMode != nil {
                updateUI(true, selectionState.selectedIds.count > 0, selectionState.selectedIds.count)
            } else {
                updateUI(value.canInvokeBasicActions.delete, value.canInvokeBasicActions.forward, selectionState.selectedIds.count)
            }
        }
    }
    
    deinit {
    }
    
    func isEqual(to other: Notifable) -> Bool {
        if let other = other as? MessageActionsPanelView {
            return self == other
        }
        return false
    }
    

    func prepare(with chatInteraction:ChatInteraction) -> Void {
        if let chatInteraction = self.chatInteraction {
            chatInteraction.remove(observer: self)
        }
        self.chatInteraction = chatInteraction
        self.chatInteraction?.add(observer: self)
        
        forwardButton.set(handler: { [weak chatInteraction] _ in
            chatInteraction?.forwardSelectedMessages()
        }, for: .Click)
        exportButton.set(handler: { [weak chatInteraction] _ in
            chatInteraction?.exportSelectedMessagesForAI()
        }, for: .Click)
        deleteButton.set(handler: { [weak chatInteraction] _ in
            chatInteraction?.deleteSelectedMessages()
        }, for: .Click)
        
        self.notify(with: chatInteraction.presentation, oldValue: chatInteraction.presentation, animated: false)
    }

    private var leftColor: NSColor {
        if chatInteraction?.presentation.reportMode != nil {
            return theme.colors.accent
        }
        return theme.colors.redUI
    }
    private var rightColor: NSColor {
        if chatInteraction?.presentation.reportMode != nil {
            return theme.colors.redUI
        }
        return theme.colors.accent
    }

    private var leftText: String {
        if chatInteraction?.presentation.reportMode != nil {
            return strings().modalCancel
        }
        return strings().messageActionsPanelDelete
    }
    private var rightText: String {
        if chatInteraction?.presentation.reportMode != nil {
            return strings().modalReport
        }
        return strings().messageActionsPanelForward
    }
    private var leftIcon: CGImage? {
        if chatInteraction?.presentation.reportMode != nil {
            return nil
        }
        return !deleteButton.userInteractionEnabled ? theme.icons.chatDeleteMessagesInactive : theme.icons.chatDeleteMessagesActive
    }
    private var rightIcon: CGImage? {
        if chatInteraction?.presentation.reportMode != nil {
            return nil
        }
        return !forwardButton.userInteractionEnabled ? theme.icons.chatForwardMessagesInactive : theme.icons.chatForwardMessagesActive
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        deleteButton.set(text: leftText, for: .Normal)
        exportButton.set(text: "Для ИИ", for: .Normal)
        forwardButton.set(text: rightText, for: .Normal)

        if let leftIcon = leftIcon {
            deleteButton.set(image: leftIcon, for: .Normal)
        } else {
            deleteButton.removeImage(for: .Normal)
        }
        if let rightIcon = rightIcon {
            forwardButton.set(image: rightIcon, for: .Normal)
        } else {
            forwardButton.removeImage(for: .Normal)
        }

        deleteButton.set(color: !deleteButton.userInteractionEnabled ? theme.colors.grayIcon : leftColor, for: .Normal)
        exportButton.set(color: !exportButton.userInteractionEnabled ? theme.colors.grayIcon : theme.colors.accent, for: .Normal)
        forwardButton.set(color: !forwardButton.userInteractionEnabled ? theme.colors.grayIcon : rightColor, for: .Normal)
        
        _ = deleteButton.sizeToFit(NSZeroSize, NSMakeSize(0, frame.height))
        _ = exportButton.sizeToFit(NSZeroSize, NSMakeSize(0, frame.height))
        _ = forwardButton.sizeToFit(NSZeroSize, NSMakeSize(0, frame.height))
        
        deleteButton.style = deleteButtonActiveStyle
        exportButton.style = buttonActiveStyle
        forwardButton.style = buttonActiveStyle
        countTitle.style = countStyle

        countTitle.set(background: theme.colors.background, for: .Normal)
        
        backgroundColor = theme.colors.background
        if let chatInteraction = chatInteraction {
            self.notify(with: chatInteraction.presentation, oldValue: chatInteraction.presentation, animated: false)
        }


    }

    override func viewDidMoveToWindow() {
        if window == nil {
            self.chatInteraction?.remove(observer: self)
            self.resignFirstResponder()
        }
    }
    
}
