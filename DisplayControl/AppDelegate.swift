//
//  AppDelegate.swift
//  Display Control
//
//  Created by Michael Carey on 25/10/15.
//  Copyright © 2015 Michael Carey. All rights reserved.
//

import Cocoa

extension Array {
    static func fromCFArray(records : CFArray?) -> Array<Element>? {
        var result: [Element]?
        if let records = records {
            for i in 0..<CFArrayGetCount(records) {
                let unmanagedObject: UnsafePointer<Void> = CFArrayGetValueAtIndex(records, i)
                let rec: Element = unsafeBitCast(unmanagedObject, Element.self)
                if (result == nil) {
                    result = [Element]()
                }
                result!.append(rec)
            }
        }
        return result
    }
}

let kCGErrorSuccess : Int32 = 0
let kCGNullDirectDisplay = CGDirectDisplayID(0)
let kIONull = io_object_t(0)
let kMirrorTag = 88

struct CGDisplayModeTuple: Hashable {
    var width: Int
    var height: Int
    var refreshRate: Double
    var hashValue: Int { return width.hashValue + height.hashValue + refreshRate.hashValue }
    
    init(_ w: Int, _ h: Int, _ r: Double) {
        width = w
        height = h
        refreshRate = r
    }
    
    init(mode: CGDisplayMode) {
        width = CGDisplayModeGetWidth(mode)
        height = CGDisplayModeGetHeight(mode)
        refreshRate = CGDisplayModeGetRefreshRate(mode)
    }
}


func ==(left: CGDisplayModeTuple, right: CGDisplayModeTuple) -> Bool {
    return (left.width == right.width) && (left.height == right.height) && (left.refreshRate == right.refreshRate)
}


func ==(left: CGDisplayMode, right: CGDisplayModeTuple) -> Bool {
    return (CGDisplayModeGetWidth(left) == right.width) && (CGDisplayModeGetHeight(left) == right.height) && (CGDisplayModeGetRefreshRate(left) == right.refreshRate)
}


func ==(left: CGDisplayModeTuple, right: CGDisplayMode) -> Bool {
    return (CGDisplayModeGetWidth(right) == left.width) && (CGDisplayModeGetHeight(right) == left.height) && (CGDisplayModeGetRefreshRate(right) == left.refreshRate)
}


func ==(left: CGDisplayMode, right: CGDisplayMode) -> Bool {
    return ((CGDisplayModeGetWidth(left) == CGDisplayModeGetWidth(right)) &&
        (CGDisplayModeGetHeight(left) == CGDisplayModeGetHeight(right)) &&
        (CGDisplayModeGetRefreshRate(left) == CGDisplayModeGetRefreshRate(right)))
}


func <(left: CGDisplayModeTuple, right: CGDisplayModeTuple) -> Bool {
    return left.width == right.width ?
        (left.height == right.height ?
            left.refreshRate < right.refreshRate :
            left.height < right.height) :
        left.width < right.width
}


func aspectRatio(width: Int, _ height: Int) -> Float {
    return floor(Float(width) / Float(height) * 100) / 100
}


func stringPixelWidth(str: String, withFont font: NSFont) -> CGFloat {
    return str.sizeWithAttributes([NSFontAttributeName: font]).width
}

func menuFontPixelWidth(str: String) -> CGFloat {
    return stringPixelWidth(str, withFont: NSFont.menuFontOfSize(0))
}


func DisplayIOServicePort(displayID: CGDirectDisplayID) -> io_service_t {
    let displayService = IOServiceMatching("IODisplayConnect")
    var serviceIterator = io_iterator_t()
    var servicePort = kIONull

    if IOServiceGetMatchingServices(kIOMasterPortDefault, displayService, &serviceIterator) == 0 {
        var info: CFDictionary
        var vendorID = CFIndex()
        var productID = CFIndex()
        var vendorIDRef: CFNumberRef
        var productIDRef: CFNumberRef
        var success: Bool
        
        var infoNS: NSDictionary
        
        var serviceObject = IOIteratorNext(serviceIterator)
        while serviceObject != kIONull {
            info = IODisplayCreateInfoDictionary(serviceObject, IOOptionBits(kIODisplayOnlyPreferredName)).takeUnretainedValue()
            infoNS = NSDictionary.init(dictionary: info)
            vendorIDRef = infoNS.valueForKey(kDisplayVendorID) as! CFNumberRef
            productIDRef = infoNS.valueForKey(kDisplayProductID) as! CFNumberRef
            
            success = CFNumberGetValue(vendorIDRef, CFNumberType.CFIndexType, &vendorID)
            success = success && CFNumberGetValue(productIDRef, CFNumberType.CFIndexType, &productID)
            
            if success {
                if Int(CGDisplayVendorNumber(displayID)) == vendorID &&
                        Int(CGDisplayModelNumber(displayID)) == productID {
                    servicePort = serviceObject
                    break
                }
            }
            
            serviceObject = IOIteratorNext(serviceIterator)
        }
    }
    
    return servicePort
}


func displayModelName(displayID: CGDirectDisplayID) -> String {
    var name = String(displayID)
    let servicePort = DisplayIOServicePort(displayID)
    if servicePort != kIONull {
        let IODeviceInfo = IODisplayCreateInfoDictionary(servicePort, IOOptionBits(kIODisplayOnlyPreferredName))
        if IODeviceInfo != nil {
            let deviceInfo = NSDictionary(dictionary: IODeviceInfo.takeUnretainedValue())
            if deviceInfo.count > 0 {
                let localisedNames = deviceInfo.objectForKey(kDisplayProductName) as! NSDictionary
                if localisedNames.count > 0 {
                    name = localisedNames.objectForKey(localisedNames.allKeys[0]) as! String
                }
            }
        }
    }
    
    return name
}


struct DisplayData {
    var ID : CGDirectDisplayID
    var label : String
    var isBuiltin : Bool { return CGDisplayIsBuiltin(ID) == 1 }
    var isMain : Bool { return CGDisplayIsMain(ID) == 1 }
    var isInMirrorSet : Bool { return CGDisplayIsInMirrorSet(ID) == 1 }
    var currentMode : CGDisplayModeTuple
    var currentModeIndex : Int = 0
    var availableModes : [CGDisplayModeTuple] = []
    
    init(fromDisplayID displayID: CGDirectDisplayID) {
        ID = displayID
        label = displayModelName(displayID)
        
        let CFAvailableModes = CGDisplayCopyAllDisplayModes(displayID, nil)
        let rawModes = Array.fromCFArray(CFAvailableModes)!.filter({CGDisplayModeIsUsableForDesktopGUI($0)})
        
        var filteredModes : Set<CGDisplayModeTuple> = []
        for mode in rawModes {
            filteredModes.insert(CGDisplayModeTuple(mode: mode!))
        }
        
        availableModes = Array(filteredModes).sort({$0 < $1})
        
        currentMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(displayID)!)
        currentModeIndex = availableModes.indexOf({$0 == currentMode})!
    }
}


func displayReconfigurationCallback (displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutablePointer<Void>) -> Void {
    
    let appDelegate = NSApplication.sharedApplication().delegate as! AppDelegate
    
    var displayLabel: String
    if appDelegate.displayList.filter({$0.ID == displayID}).count > 0 {
        displayLabel = appDelegate.displayList[appDelegate.displayList.indexOf({$0.ID == displayID})!].label
    } else {
        displayLabel = displayModelName(displayID)
    }

    NSLog("Display reconfiguration callback called for display \(displayLabel) (\(displayID)): flags = \(flags.rawValue)")

    if flags.rawValue & CGDisplayChangeSummaryFlags.AddFlag.rawValue > 0 {
        // Add new display to displayList & update menu
        
        appDelegate.displayList.append(DisplayData(fromDisplayID: displayID))
        if menuFontPixelWidth(appDelegate.displayList.last!.label) > appDelegate.largestDisplayLabelPixelWidth {
            appDelegate.largestDisplayLabelPixelWidth = menuFontPixelWidth(appDelegate.displayList.last!.label)
            appDelegate.configureDisplayMenuParagraphStyle()
        }
        appDelegate.displayList.sortInPlace({$0.ID < $1.ID})
        let newDisplayIndex = appDelegate.displayList.indexOf({$0.ID == displayID})!
        appDelegate.menu.insertItem(appDelegate.buildDisplayMenu(displayID, tag: newDisplayIndex), atIndex: newDisplayIndex)
        
        var i = 0
        for _ in appDelegate.displayList {
            appDelegate.menu.itemAtIndex(i)!.tag = i
            i++
        }
        
        NSLog("Display connected: \(displayLabel) (\(displayID))")

    } else if flags.rawValue & CGDisplayChangeSummaryFlags.RemoveFlag.rawValue > 0 {
        // Remove display from displayList and update menu
        let removedDisplayIndex = appDelegate.displayList.indexOf({$0.ID == displayID})!
        appDelegate.displayList.removeAtIndex(removedDisplayIndex)
        
        appDelegate.largestDisplayLabelPixelWidth = 0
        for display in appDelegate.displayList {
            if menuFontPixelWidth(display.label) > appDelegate.largestDisplayLabelPixelWidth {
                appDelegate.largestDisplayLabelPixelWidth = menuFontPixelWidth(display.label)
            }
        }

        appDelegate.configureDisplayMenuParagraphStyle()
        
        appDelegate.menu.removeItemAtIndex(appDelegate.menu.indexOfItem(appDelegate.menu.itemWithTag(removedDisplayIndex)!))
        
        var i = 0
        for _ in appDelegate.displayList {
            appDelegate.menu.itemAtIndex(i)!.tag = i
            i++
        }

        NSLog("Display removed: \(displayLabel) (\(displayID))")
    }
    
    if flags.rawValue & CGDisplayChangeSummaryFlags.SetModeFlag.rawValue > 0 {
        
        let displayIndex = appDelegate.displayList.indexOf({$0.ID == displayID})!
        let display = appDelegate.displayList[displayIndex]
        let newMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(displayID)!)
        let newModeIndex = display.availableModes.indexOf(newMode)
        
        let displayMenu = appDelegate.menu.itemWithTag(displayIndex)!
        displayMenu.submenu?.itemWithTag(display.currentModeIndex)?.state = 0
        displayMenu.submenu?.itemAtIndex(newModeIndex!)?.state = 1
        displayMenu.attributedTitle = NSAttributedString(string: display.label + "\t\(newMode.width)\t× \(newMode.height)", attributes: [NSParagraphStyleAttributeName: appDelegate.displayMenuParagraphStyle, NSFontAttributeName: NSFont.menuFontOfSize(0)])
        appDelegate.displayList[displayIndex].currentMode = newMode
        appDelegate.displayList[displayIndex].currentModeIndex = newModeIndex!
        
    }
    
    if flags.rawValue & CGDisplayChangeSummaryFlags.MirrorFlag.rawValue > 0 {
        
        appDelegate.menu.itemWithTag(kMirrorTag)?.title = "Disable Mirroring"
        NSLog("Mirroring activated")

    } else if flags.rawValue & CGDisplayChangeSummaryFlags.UnMirrorFlag.rawValue > 0 {
        
        appDelegate.menu.itemWithTag(kMirrorTag)?.title = "Enable Mirroring"
        NSLog("Mirroring deactivated")
    }
}


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSSquareStatusItemLength)
    let maxDisplays : UInt32 = 255
    let menu = NSMenu()
    var CGResult : CGError?
    var displayCount : UInt32 = 0
    var displayList : [DisplayData] = []
    var callbackIsSet : Bool = false
    var largestDisplayLabelPixelWidth: CGFloat = 0.0
    let displayMenuParagraphStyle = NSMutableParagraphStyle()
    let resolutionMenuParagraphStyle = NSMutableParagraphStyle()
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            
            CGResult = CGGetOnlineDisplayList(maxDisplays, nil, &displayCount)
            
            var onlineDisplays = [CGDirectDisplayID](count: Int(displayCount), repeatedValue: 0)
            CGResult = CGGetOnlineDisplayList(displayCount, &onlineDisplays, &displayCount)
            
            for displayID in onlineDisplays {
                displayList.append(DisplayData(fromDisplayID: displayID))
                if menuFontPixelWidth(displayList.last!.label) > largestDisplayLabelPixelWidth {
                    largestDisplayLabelPixelWidth = menuFontPixelWidth(displayList.last!.label)
                }
            }
            
            /* Build menus */
            configureDisplayMenuParagraphStyle()
            configureResolutionMenuParagraphStyle()

            displayList.sortInPlace({$0.ID < $1.ID})
            
            var i = 0
            for display in displayList {
                menu.addItem(buildDisplayMenu(display.ID, tag: i))
                i++
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
        }
        
         callbackIsSet = (CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil).rawValue == 1)
    }
    
    
    func buildDisplayMenu(displayID: CGDirectDisplayID, tag: Int) -> NSMenuItem {
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
            
            switch aspectRatio(displayMode.width, displayMode.height) {
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
            subMenuItem.enabled = true
            subMenu.addItem(subMenuItem)
            j++
        }
        
        menuItem.tag = tag
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
        if callbackIsSet {
            CGResult = CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        }
    }
    
    
    func setDisplayMode(sender: AnyObject) {
        let selectedMenuItem = sender as! NSMenuItem
        let display = displayList[(selectedMenuItem.parentItem?.tag)!]
        let selectedMode = display.availableModes[selectedMenuItem.tag]
        var displayConfig = CGDisplayConfigRef.init()

        if selectedMode != display.currentMode {
            let displayMode: CGDisplayMode = (Array.fromCFArray(CGDisplayCopyAllDisplayModes(display.ID, nil))?.filter({$0 == selectedMode}).first)!
            
            CGResult = CGBeginDisplayConfiguration(&displayConfig)
            if CGResult!.rawValue == kCGErrorSuccess {
                CGResult = CGConfigureDisplayWithDisplayMode(displayConfig, display.ID, displayMode, nil)
                if CGResult!.rawValue == kCGErrorSuccess {
                    CGResult = CGCompleteDisplayConfiguration(displayConfig, CGConfigureOption.ForSession)
                }
            }
            
            if CGResult!.rawValue == kCGErrorSuccess {
                let newMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(display.ID)!)
                NSLog("Mode changed for display \(display.label) (\(display.ID)); new mode = \(newMode.width) × \(newMode.height) @ \(newMode.refreshRate)Hz")
            } else {
                NSLog("ERROR: mode not changed for display \(display.label) (\(display.ID)): result (\(CGResult!.rawValue))")
            }
        }
    }
    
    
    func toggleMirroring(sender: AnyObject) {
        var displayConfig = CGDisplayConfigRef.init()
        var mirrorTarget = kCGNullDirectDisplay
        
        CGResult = CGBeginDisplayConfiguration(&displayConfig)
        if CGResult!.rawValue == kCGErrorSuccess {
            if CGDisplayIsInMirrorSet(CGMainDisplayID()) == 0 {
                mirrorTarget = CGMainDisplayID()
            }
            for display in displayList {
                if !display.isMain {
                    CGResult = CGConfigureDisplayMirrorOfDisplay(displayConfig, display.ID, mirrorTarget)
                    if CGResult!.rawValue != kCGErrorSuccess {
                        break
                    }
                }
            }
            if CGResult!.rawValue == kCGErrorSuccess {
                CGResult = CGCompleteDisplayConfiguration(displayConfig, CGConfigureOption.ForSession)
            }
        }
        if CGResult!.rawValue == kCGErrorSuccess {
            NSLog("Mirror toggle result: success (\(CGResult!.rawValue))")
        } else {
            NSLog("Mirror toggle result: error (\(CGResult!.rawValue))")
        }
    }
    
    
    func configureDisplayMenuParagraphStyle() {
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
    
    
    func logToConsole(sender: AnyObject) {
        NSLog("Display Control button activated")
    }
    
    
    func nullSelector(sender: AnyObject) {
        NSLog("nullSelector called; should never see this")
    }

}

