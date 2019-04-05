// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

@objc(OFResourceBookmarks) open class ResourceBookmarks : NSObject, ResourceLocationDelegate {

    private let preferenceKey: String

    @objc public private(set) var bookmarkedResourceLocations = [ResourceLocation]()
    public let resourceTypes: [String:ResourceTypePredicate]

    public init(preferenceKey: String, resourceTypes: [String:ResourceTypePredicate]) {
        self.preferenceKey = preferenceKey
        self.resourceTypes = resourceTypes

        super.init()
        
        readPreference()
    }

    deinit {
        bookmarkedResourceLocations.forEach { $0.invalidate() }
    }

    @objc open func isResourceInKnownResourceLocation(_ resourceURL: URL) -> Bool {
        for location in bookmarkedResourceLocations {
            if location.containsURL(resourceURL) {
                return true
            }
        }
        return false
    }

    @objc open func addResourceFolderURL(_ url: URL) throws {
        let location = try ResourceLocation(folderURL: url, resourceTypes: resourceTypes, delegate: self)

        var bookmarks = UserDefaults.standard.array(forKey: preferenceKey) ?? []
        guard let bookmark = location.bookmark else {
            assertionFailure("The initializer will have thrown an error otherwise")
            return
        }
        bookmarks.append(bookmark)

        UserDefaults.standard.set(bookmarks, forKey: preferenceKey)

        var locations = bookmarkedResourceLocations
        locations.append(location)

        bookmarkedResourceLocations = locations

        didAddResourceLocation(location)
    }

    @objc open func removeResourceFolderURL(_ fileURL: URL) {
        // TODO: This should probably take a OFResourceLocation to remove.

        guard let locationIndex = bookmarkedResourceLocations.firstIndex(where: { $0.folderURL == fileURL }) else {
            assertionFailure("Removing resource folder URL that wasn't registered")
            return
        }

        let location = bookmarkedResourceLocations[locationIndex]
        willRemoveResourceLocation(location)

        location.invalidate()

        var updatedLocations = bookmarkedResourceLocations
        updatedLocations.remove(at: locationIndex)

        bookmarkedResourceLocations = updatedLocations

        let bookmarks = bookmarkedResourceLocations.map { $0.bookmark }
        UserDefaults.standard.set(bookmarks, forKey: preferenceKey)
    }

    // MARK:- ResourceLocationDelegate

    open func resourceLocationDidUpdateResourceURLs(_ location: ResourceLocation) {
        // For subclasses
    }
    open func resourceLocationDidMove(_ location: ResourceLocation) {
        // For subclasses
    }

    // MARK:- Subclasses

    open func willRemoveResourceLocation(_ location: ResourceLocation) {
    }
    open func didAddResourceLocation(_ location: ResourceLocation) {
    }
    // MARK:- Private

    private func readPreference() {
        bookmarkedResourceLocations.forEach {
            willRemoveResourceLocation($0)
            $0.invalidate()
        }
        bookmarkedResourceLocations = []

        var rewriteDefault = false

        var locations = [ResourceLocation]()

        for object in (UserDefaults.standard.array(forKey: preferenceKey) ?? []) {
            guard let data_ = object as? NSData else {
                rewriteDefault = true
                continue
            }
            let data = data_ as Data

            let location: ResourceLocation
            do {
                location = try ResourceLocation(bookmark: data, resourceTypes: resourceTypes, delegate: self)
            } catch let err as NSError {
                err.log(withReason: "Error creating resource location from bookmark data \(data)")
                continue
            }

            // Ugly... OFResourceLocation might look up a new bookmark if the one we give it is stale.
            rewriteDefault = rewriteDefault || (location.bookmark != data)

            locations.append(location)
        }

        bookmarkedResourceLocations = locations

        bookmarkedResourceLocations.forEach { didAddResourceLocation($0) }

        if (rewriteDefault) {
            let bookmarks = bookmarkedResourceLocations.map { $0.bookmark }
            UserDefaults.standard.set(bookmarks, forKey: preferenceKey)
        }
    }

}

