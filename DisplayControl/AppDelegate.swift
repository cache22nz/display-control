//
//  AppDelegate.swift
//  Display Control
//
//  Created by Michael Carey on 25/10/15.
//  Copyright © 2015 Michael Carey. All rights reserved.
//

//import Cocoa
import AppKit

let kMirrorTag = 88

func displayReconfigurationCallback (displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutablePointer<Void>) -> Void {
    
    let appDelegate = NSApplication.sharedApplication().delegate as! AppDelegate
    var display: DisplayData
    
    if appDelegate.displayList.filter({$0.ID == displayID}).count > 0 {
        display = appDelegate.displayList.filter({$0.ID == displayID}).first!
    } else {
        display = DisplayData(fromDisplayID: displayID, listType: DisplayListType.withSafeModes)
        NSLog("New display detected: \(display.label) (\(displayID))")
    }
    
    
    NSLog("Display reconfiguration callback called for display \(display.label) (\(displayID)): flags = \(flags.rawValue)")

    if flags.rawValue & CGDisplayChangeSummaryFlags.AddFlag.rawValue > 0 {
        // Add new display to displayList & update menu
        
        guard !appDelegate.displayList.contains({$0.ID == displayID}) else {
            NSLog("'AddDisplay' called for already scanned display; this shouldn't happen")
            return
        }
        
        appDelegate.displayList.append(display)
        appDelegate.displayList.sortInPlace({$0.ID < $1.ID})
        appDelegate.configureDisplayMenuParagraphStyle()
        if let newDisplayIndex = appDelegate.displayList.indexOf({$0.ID == displayID}) {
            appDelegate.menu.insertItem(appDelegate.buildDisplayMenu(displayID), atIndex: newDisplayIndex)
        }

        NSLog("Display connected: \(display.label) (\(displayID))")
        

    } else if flags.rawValue & CGDisplayChangeSummaryFlags.RemoveFlag.rawValue > 0 {
        // Remove display from displayList and update menu
        
        guard appDelegate.displayList.contains({$0.ID == displayID}) else {
            NSLog("'RemoveDisplay' called for unscanned display; this shouldn't happen")
            return
        }
        
        let removedDisplayIndex = appDelegate.displayList.indexOf({$0.ID == displayID})!
        appDelegate.displayList.removeAtIndex(removedDisplayIndex)
        
        if appDelegate.menu.itemWithTag(Int(displayID)) != nil {
            // change menu paragraph style before removing menu, so it takes effect when the removal triggers a refresh
            appDelegate.configureDisplayMenuParagraphStyle()
            
            appDelegate.menu.removeItem(appDelegate.menu.itemWithTag(Int(displayID))!)
        }
        
        NSLog("Display removed: \(display.label) (\(displayID))")
    }

    
    if flags.rawValue & CGDisplayChangeSummaryFlags.SetModeFlag.rawValue > 0 {
        
        guard appDelegate.displayList.contains({$0.ID == displayID}) else {
            NSLog("'SetMode' called for unscanned display; this shouldn't happen")
            return
        }
        
        let displayIndex = appDelegate.displayList.indexOf({$0.ID == displayID})!
        
        guard display.isOnline else {
            NSLog("'SetMode' called for offline display; this shouldn't happen")
            return
        }
        
        if let displayMenu = appDelegate.menu.itemWithTag(Int(displayID)) {
            if let newCGMode = CGDisplayCopyDisplayMode(displayID) {
                let newMode = CGDisplayModeTuple(mode: newCGMode)

                // shouldn't assume the new resolution is in the list. Check, rescan and rebuild menu if necessary.
                if !display.availableModes.contains(newMode) {
                    
                    NSLog("New mode for display \(display.label) (\(displayID)) not detected in original scan: \(newMode.width) x \(newMode.height) @ \(newMode.refreshRate)Hz")
                    appDelegate.displayList[displayIndex] = DisplayData(fromDisplayID: displayID, listType: DisplayListType.withSafeModes)
                    displayMenu.submenu = appDelegate.buildDisplayMenu(displayID).submenu

                } else {
                    
                    let newModeIndex = display.availableModes.indexOf(newMode)
                    
                    displayMenu.submenu?.itemWithTag(display.currentModeIndex)?.state = 0
                    displayMenu.submenu?.itemAtIndex(newModeIndex!)?.state = 1
                    
                    appDelegate.displayList[displayIndex].currentMode = newMode
                    appDelegate.displayList[displayIndex].currentModeIndex = newModeIndex!
                }

                displayMenu.attributedTitle = NSAttributedString(string: display.label + "\t\(newMode.width)\t× \(newMode.height)", attributes: [NSParagraphStyleAttributeName: appDelegate.displayMenuParagraphStyle, NSFontAttributeName: NSFont.menuFontOfSize(0)])
            }
        } else {
            NSLog("'SetMode' called for display that has no menu; this shouldn't happen")
        }
    }
    
    
    if flags.rawValue & CGDisplayChangeSummaryFlags.MirrorFlag.rawValue > 0 {
        
        guard appDelegate.displayList.count > 1 else {
            NSLog("'MirrorDisplays' called with less than 2 displays connected; this shouldn't happen")
            return
        }
        
        appDelegate.menu.itemWithTag(kMirrorTag)?.title = "Disable Mirroring"
        if #available(OSX 10.10, *) {
            if let button = appDelegate.statusItem.button {
                button.image = NSImage(named: "StatusBarBlueButtonImage")
            }
        } else {
            // Fallback on earlier versions
            appDelegate.statusItem.image = NSImage(named: "StatusBarBlueButtonImage")
        }

        NSLog("Mirroring activated")

    } else if flags.rawValue & CGDisplayChangeSummaryFlags.UnMirrorFlag.rawValue > 0 {
        
        appDelegate.menu.itemWithTag(kMirrorTag)?.title = "Enable Mirroring"
        if #available(OSX 10.10, *) {
            if let button = appDelegate.statusItem.button {
                button.image = NSImage(named: "StatusBarButtonImage")
            }
        } else {
            // Fallback on earlier versions
            appDelegate.statusItem.image = NSImage(named: "StatusBarButtonImage")
        }

        NSLog("Mirroring deactivated")
    }
    
    // Check stored display list for consistency
    for display in appDelegate.displayList {
        if !display.isOnline {
            if appDelegate.menu.itemWithTag(Int(display.ID)) != nil {
                appDelegate.menu.removeItem(appDelegate.menu.itemWithTag(Int(display.ID))!)
            }
            
            appDelegate.displayList.removeAtIndex(appDelegate.displayList.indexOf({$0.ID == display.ID})!)
        }
    }
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSSquareStatusItemLength)
    let menu = NSMenu()
    var displayList : [DisplayData] = []
    var callbackRegistered : Bool = false
    var largestDisplayLabelPixelWidth: CGFloat = 0.0
    let displayMenuParagraphStyle = NSMutableParagraphStyle()
    let resolutionMenuParagraphStyle = NSMutableParagraphStyle()
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        
        if #available(OSX 10.10, *) {
            if let button = statusItem.button {
                button.image = NSImage(named: "StatusBarButtonImage")
            }
        } else {
            // Fallback on earlier versions
            statusItem.image = NSImage(named: "StatusBarButtonImage")
        }
        
        displayList = detectDisplays(DisplayListType.withSafeModes)
        
        /* Build menus */
        configureDisplayMenuParagraphStyle()
        configureResolutionMenuParagraphStyle()

        for display in displayList {
            menu.addItem(buildDisplayMenu(display.ID))
        }
        
        menu.addItem(NSMenuItem.separatorItem())
        
        if displayList.filter({$0.isInMirrorSet}).count == 0 {
            menu.addItem(NSMenuItem(title: "Enable Mirroring", action: Selector("toggleMirroring:"), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Disable Mirroring", action: Selector("toggleMirroring:"), keyEquivalent: ""))
        }
        menu.itemArray.last?.tag = kMirrorTag
        
        menu.addItem(NSMenuItem.separatorItem())
        menu.addItem(NSMenuItem(title: "Quit Display Control", action: Selector("terminate:"), keyEquivalent: ""))
        
        statusItem.menu = menu
        
        let registrationResult = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        callbackRegistered = (registrationResult == CGError.Success)
        
        if !callbackRegistered {
            NSLog("Warning: unexpected result when registering callback function (code: \(registrationResult.rawValue))")
        }
    }
    
    
    func stringPixelWidth(str: String, withFont font: NSFont) -> CGFloat {
        return str.sizeWithAttributes([NSFontAttributeName: font]).width
    }
    
    func menuFontPixelWidth(str: String) -> CGFloat {
        return stringPixelWidth(str, withFont: NSFont.menuFontOfSize(0))
    }
    
    
    func getLargestDisplayLabelPixelWidth() -> CGFloat {
        var labelPixelWidth: CGFloat = 0.0
        for display in displayList {
            if menuFontPixelWidth(display.label) > labelPixelWidth {
                labelPixelWidth = menuFontPixelWidth(display.label)
            }
        }
        return labelPixelWidth
    }
    
    
    func buildDisplayMenu(displayID: CGDirectDisplayID) -> NSMenuItem {
       let display = displayList[displayList.indexOf({$0.ID == displayID})!]
        
        let menuItem = NSMenuItem(title: "", action: Selector("nullSelector:"), keyEquivalent: "")
        menuItem.attributedTitle = NSAttributedString(string: display.label + "\t\(display.currentMode.width)\t× \(display.currentMode.height)", attributes: [NSParagraphStyleAttributeName: displayMenuParagraphStyle, NSFontAttributeName: NSFont.menuFontOfSize(0)])

        let subMenu = NSMenu()
        var j = 0
        var menuTitle: String
        
        for displayMode in display.availableModes {
            menuTitle = "\t\(displayMode.width)\t× \(displayMode.height)"
            if (displayMode.refreshRate > 0) {
                menuTitle += "\t@ \(displayMode.refreshRate)Hz"
            }

            let subMenuItem = NSMenuItem(title: "", action: Selector("setDisplayMode:"), keyEquivalent: "")
            subMenuItem.attributedTitle = NSAttributedString(string: menuTitle, attributes: [NSParagraphStyleAttributeName: resolutionMenuParagraphStyle, NSFontAttributeName: NSFont.menuFontOfSize(0)])
            if displayMode == display.currentMode {
                subMenuItem.state = 1
            }
            
            switch displayMode.aspectRatio() {
            case aspectRatio(4, 3):
                subMenuItem.image = NSImage(named: "aspect-ratio-4-3")
                
            case aspectRatio(16, 9):
                subMenuItem.image = NSImage(named: "aspect-ratio-16-9")
                
            case aspectRatio(16, 10):
                subMenuItem.image = NSImage(named: "aspect-ratio-16-10")
                
            default:
                subMenuItem.image = NSImage(named: "aspect-ratio-none")
            }
            
            subMenuItem.tag = j
            subMenu.addItem(subMenuItem)
            j++
        }
        
        menuItem.tag = Int(displayID)
        menuItem.submenu = subMenu
        
        return menuItem
    }
    
    
    override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
        var itemEnabled = true
        if menuItem.action == Selector("toggleMirroring:") {
            itemEnabled = displayList.count > 1
        }
        return itemEnabled
    }


    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
        if callbackRegistered {
            let teardownResult = CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
            if teardownResult != CGError.Success {
                NSLog("Warning: unexpected result when deregistering callback function (code: \(teardownResult.rawValue))")
            }
        }
    }
    
    
    func setDisplayMode(sender: AnyObject) {
        let selectedMenuItem = sender as! NSMenuItem
        if let display = displayList.filter({Int($0.ID) == (selectedMenuItem.parentItem?.tag)}).first {
            let selectedMode = display.availableModes[selectedMenuItem.tag]
            var displayConfig = CGDisplayConfigRef.init()
            var CGResult: CGError
            
            if display.isOnline {
                if selectedMode != display.currentMode {
                    let displayMode: CGDisplayMode = (Array.fromCFArray(CGDisplayCopyAllDisplayModes(display.ID, nil))?.filter({$0 == selectedMode}).first)!
                    
                    CGResult = CGBeginDisplayConfiguration(&displayConfig)
                    if CGResult == CGError.Success {
                        CGResult = CGConfigureDisplayWithDisplayMode(displayConfig, display.ID, displayMode, nil)
                        if CGResult == CGError.Success {
                            CGResult = CGCompleteDisplayConfiguration(displayConfig, CGConfigureOption.ForSession)
                        }
                    }
                    
                    if CGResult == CGError.Success {
                        let newMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(display.ID)!)
                        NSLog("Mode changed for display \(display.label) (\(display.ID)); new mode = \(newMode.width) × \(newMode.height) @ \(newMode.refreshRate)Hz")
                    } else {
                        NSLog("ERROR: mode not changed for display \(display.label) (\(display.ID)): result (\(CGResult.rawValue))")
                    }
                }
            } else {
                // display is offline somehow, remove all references?
                /*

                */
                
                NSLog("ERROR: mode change requested for offline display \(display.label) (ID: \(display.ID))")
            }
        } else {
            NSLog("ERROR: mode change requested for unscanned display (ID: \(selectedMenuItem.parentItem?.tag))")
        }
    }
    
    
    func toggleMirroring(sender: AnyObject) {
        var displayConfig = CGDisplayConfigRef.init()
        var mirrorTarget = kCGNullDirectDisplay
        
        var mirrorResult = CGBeginDisplayConfiguration(&displayConfig)
        if mirrorResult == CGError.Success {
            if CGDisplayIsInMirrorSet(CGMainDisplayID()) == 0 {
                mirrorTarget = CGMainDisplayID()
            }
            for display in displayList {
                if !display.isMain && display.isOnline {
                    mirrorResult = CGConfigureDisplayMirrorOfDisplay(displayConfig, display.ID, mirrorTarget)
                    if mirrorResult != CGError.Success {
                        break
                    }
                }
            }
            if mirrorResult == CGError.Success {
                mirrorResult = CGCompleteDisplayConfiguration(displayConfig, CGConfigureOption.ForSession)
            }
        }
        if mirrorResult == CGError.Success {
            NSLog("Mirror toggle result: success (\(mirrorResult.rawValue))")
        } else {
            NSLog("Mirror toggle result: error (\(mirrorResult.rawValue))")
        }
    }
    
    
    func configureDisplayMenuParagraphStyle() {
        let newLargestDisplayLabelPixelWidth = getLargestDisplayLabelPixelWidth()
        
        if newLargestDisplayLabelPixelWidth != largestDisplayLabelPixelWidth {
            largestDisplayLabelPixelWidth = newLargestDisplayLabelPixelWidth
        }
        
        for tabStop in displayMenuParagraphStyle.tabStops {
            displayMenuParagraphStyle.removeTabStop(tabStop)
        }
        
        displayMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.RightTabStopType, location: largestDisplayLabelPixelWidth + 30 + menuFontPixelWidth("00000 ")))
        displayMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.LeftTabStopType, location: displayMenuParagraphStyle.tabStops[0].location + menuFontPixelWidth(" ")))
        displayMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.LeftTabStopType, location: displayMenuParagraphStyle.tabStops[1].location + menuFontPixelWidth("× 00000") + 30))
    }


    
    func configureResolutionMenuParagraphStyle() {
        for tabStop in resolutionMenuParagraphStyle.tabStops {
            resolutionMenuParagraphStyle.removeTabStop(tabStop)
        }
        
        resolutionMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.RightTabStopType, location: menuFontPixelWidth("00000") + 5))
        resolutionMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.LeftTabStopType, location: resolutionMenuParagraphStyle.tabStops[0].location + menuFontPixelWidth(" ")))
        resolutionMenuParagraphStyle.addTabStop(NSTextTab(type: NSTextTabType.LeftTabStopType, location: resolutionMenuParagraphStyle.tabStops[1].location + menuFontPixelWidth("× 00000") + 30))
    }
    
    
    func nullSelector(sender: AnyObject) {
        NSLog("nullSelector called; should never see this")
    }

}

