//
//  PlatformImage.swift
//  CarrierWaveCore
//
//  Cross-platform image typealias for the sharing module. The card renderer
//  produces a `PlatformImage` which callers convert via NSItemProvider /
//  UIActivityItemSource (iOS) or NSSharingServicePicker (macOS).
//

#if canImport(UIKit)
    import UIKit

    public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    import AppKit

    public typealias PlatformImage = NSImage
#endif
