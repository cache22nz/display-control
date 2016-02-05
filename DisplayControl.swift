//
//  DisplayControl.swift
//  Display Control
//
//  Created by Michael Carey on 15/12/15.
//  Copyright © 2015 Michael Carey. All rights reserved.
//

import Foundation


let kCGNullDirectDisplay = CGDirectDisplayID(0)
let kIONull = io_object_t(0)
let kMaxDisplays : UInt32 = 255


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


enum DisplayListType {
    case basic
    case withSafeModes
    case withUnsafeModes
}


class CGDisplayModeTuple: Hashable {
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
    
    
    func aspectRatio() -> Float {
        return floor(Float(width) / Float(height) * 100) / 100
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


func <=(left: CGDisplayModeTuple, right: CGDisplayModeTuple) -> Bool {
    return (left == right) || (left < right)
}


class DisplayData {
    var ID : CGDirectDisplayID
    var label : String
    var isBuiltin : Bool { return CGDisplayIsBuiltin(ID) == 1 }
    var isMain : Bool { return CGDisplayIsMain(ID) == 1 }
    var isInMirrorSet : Bool { return CGDisplayIsInMirrorSet(ID) == 1 }
    var isOnline : Bool { return CGDisplayIsOnline(ID) == 1 }
    var currentMode : CGDisplayModeTuple
    var currentModeIndex : Int = 0
    var availableModes : [CGDisplayModeTuple] = []
    
    /*
    init(fromDisplayID displayID: CGDirectDisplayID) {
        ID = displayID
        label = displayModelName(displayID)
        
        if let CFAvailableModes = CGDisplayCopyAllDisplayModes(displayID, nil) {
            let rawModes = Array.fromCFArray(CFAvailableModes)!.filter({CGDisplayModeIsUsableForDesktopGUI($0)})
            
            var filteredModes : Set<CGDisplayModeTuple> = []
            for mode in rawModes {
                filteredModes.insert(CGDisplayModeTuple(mode: mode!))
            }
            
            availableModes = Array(filteredModes).sort({$0 < $1})
            
            currentMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(displayID)!)
            currentModeIndex = availableModes.indexOf({$0 == currentMode})!
        } else {
            currentMode = CGDisplayModeTuple(0, 0, 0.0)
        }
    }
    */

    init(fromDisplayID displayID: CGDirectDisplayID, listType: DisplayListType) {
        ID = displayID
        label = displayModelName(displayID)
        currentMode = CGDisplayModeTuple(0, 0, 0.0)
        
        if listType != DisplayListType.basic {
            availableModes = listAvailableModes(displayID, modeListType: listType)
            
            currentMode = CGDisplayModeTuple(mode: CGDisplayCopyDisplayMode(displayID)!)
            currentModeIndex = availableModes.indexOf({$0 == currentMode})!
        }
    }
    
    
    func nearestMatchingMode(targetMode: CGDisplayModeTuple) -> CGDisplayModeTuple? {
        //var bestMode = availableModes.filter({$0 == targetMode}).last
        var bestMode: CGDisplayModeTuple?
        
        if availableModes.count > 0 {
            if targetMode < availableModes.first! {
                bestMode = availableModes.first
            } else {
                bestMode = availableModes.filter({$0.width <= targetMode.width && $0.height <= targetMode.height && $0.refreshRate <= targetMode.refreshRate}).last
            }
        }
        
        return bestMode
    }
}


func listAvailableModes(displayID: CGDirectDisplayID, modeListType: DisplayListType) -> [CGDisplayModeTuple] {
    var modeList: [CGDisplayModeTuple] = []
    
    if modeListType != DisplayListType.basic {
        if let CFAvailableModes = CGDisplayCopyAllDisplayModes(displayID, nil) {
            var rawModes: [CGDisplayMode]
            if modeListType == DisplayListType.withSafeModes {
                rawModes = Array.fromCFArray(CFAvailableModes)!.filter({CGDisplayModeIsUsableForDesktopGUI($0)})
            } else {
                rawModes = Array.fromCFArray(CFAvailableModes)!
            }
            
            var filteredModes : Set<CGDisplayModeTuple> = []
            for mode in rawModes {
                filteredModes.insert(CGDisplayModeTuple(mode: mode))
            }
            
            modeList = Array(filteredModes).sort({$0 < $1})
        }
    }
    
    return modeList
}


func aspectRatio(width: Int, _ height: Int) -> Float {
    return floor(Float(width) / Float(height) * 100) / 100
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


func detectDisplays(listType: DisplayListType) -> [DisplayData] {
    var displays: [DisplayData] = []
    var displayCount : UInt32 = 0
    
    var detectionResult = CGGetOnlineDisplayList(kMaxDisplays, nil, &displayCount)
    
    if detectionResult == CGError.Success {
        var onlineDisplays = [CGDirectDisplayID](count: Int(displayCount), repeatedValue: 0)
        detectionResult = CGGetOnlineDisplayList(displayCount, &onlineDisplays, &displayCount)
        
        if detectionResult == CGError.Success {
            for displayID in onlineDisplays {
                displays.append(DisplayData(fromDisplayID: displayID, listType: listType))
            }
            
            displays.sortInPlace({$0.ID < $1.ID})
        }
    }
    return displays
}
