// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

fileprivate extension IndexSet {
    
    init<S: Sequence>(from sequence: S) where S.Element == Int {
        self.init()
        sequence.forEach { self.insert($0) }
    }
    
}

// MARK: -

/// A representation of a two level tree.
///
/// Table and collection view data sources can adapt their models to this type and use the `difference` function to calculate change sets suitable for doing table or collection view updates.
public protocol Diffable {
    associatedtype SectionType: DifferenceComparable
    associatedtype ItemType: DifferenceComparable
    var sections: [SectionType] { get }
    func items(in section: Int) -> [ItemType]
}

public extension Diffable {
    private var wrappedItems: [WrappedDifferenceComparable<IndexPath, ItemType>] {
        var result: [WrappedDifferenceComparable<IndexPath, ItemType>] = []
        for sectionIndex in 0 ..< sections.count {
            let sectionItems = items(in: sectionIndex)
            let wrappedItems = sectionItems.enumerated().map { indexAndItem in
                return WrappedDifferenceComparable(index: IndexPath(row: indexAndItem.0, section: sectionIndex), value: indexAndItem.1)
            }
            result.append(contentsOf: wrappedItems)
        }
        return result
    }
    
    /// Returns a difference value that can be used to update the table or collection view.
    public func difference(from old: Self, suppressedMovePositions: (sources: Set<IndexPath>, destinations: Set<IndexPath>)? = nil) -> Difference {
        let oldSectionIdentifiers = old.sections.map({ $0.differenceIdentifier })
        let sectionIdentifiers = sections.map({ $0.differenceIdentifier })
        precondition(Set(oldSectionIdentifiers).count == oldSectionIdentifiers.count, "Old sections must have unique section identifiers to compute a difference")
        precondition(Set(sectionIdentifiers).count == sectionIdentifiers.count, "Sections must have unique section identifiers to compute a difference")
        
        let newWrappedSections = sections.enumerated().map { WrappedDifferenceComparable(index: $0, value: $1) }
        let oldWrappedSections = old.sections.enumerated().map { WrappedDifferenceComparable(index: $0, value: $1) }
        
        let sectionDifference: CollectionDifference<Int>
        let sectionDifferenceFast = WrappedDifferenceComparable.difference(from: oldWrappedSections, to: newWrappedSections)
        switch sectionDifferenceFast {
        case .reload:
            sectionDifference = CollectionDifference(insertions: [], deletions: [], updates: [], moves: [])
        case .applyDifference(let collectionDifference):
            sectionDifference = collectionDifference
        }
        
        
        let newWrappedItems = wrappedItems
        let oldWrappedItems = old.wrappedItems
        let itemDifference: CollectionDifference<IndexPath>
        let itemDifferenceFast = WrappedDifferenceComparable.difference(from: oldWrappedItems, to: newWrappedItems, metaMutator: MetaMutator(sectionDifference: sectionDifference), suppressedMovePositions: suppressedMovePositions)
        switch itemDifferenceFast {
        case .reload:
            return Difference(sectionChanges: CollectionDifference(insertions: [], deletions: [], updates: [], moves: []), itemChanges: CollectionDifference(insertions: [], deletions: [], updates: [], moves: []), changeKind: .hasChangeButCannotApply)
        case .applyDifference(let collectionDifference):
            itemDifference = collectionDifference
        }
        
        
        // Clean up moves to/from inserted/deleted sections.
        var convertedInsertions = Set<IndexPath>()
        var convertedDeletions = Set<IndexPath>()
        var survivingMoves = itemDifference.moves.filter { indexPaths in
            let (source, destination) = indexPaths
            var omitMove = false

            // No need to move items if we're deleting their source section, but we do need to insert them at their destination. We'll filter out unnecessary insertions below, so don't check that here.
            if sectionDifference.deletions.contains(source.section) {
                convertedInsertions.insert(destination)
                omitMove = true
            }

            // No need to move items if we're inserting their destination section, but we do need to delete them from their source section. We'll filter out unnecessary deletions below, so don't check that here.
            if sectionDifference.insertions.contains(destination.section) {
                convertedDeletions.insert(source)
                omitMove = true
            }

            return !omitMove
        }

        var foundConflictingSectionAndItemChanges: Bool = false
        
        // Exclude items that are covered by existing section deltas:
        let survivingInsertions = itemDifference.insertions.union(convertedInsertions).filter { indexPath in
            // No need to insert items if we're inserting the whole section
            return !sectionDifference.insertions.contains(indexPath.section)
        }
        let survivingDeletions = itemDifference.deletions.union(convertedDeletions).compactMap { (indexPath) -> IndexPath? in
            // No need to delete items if we're deleting the whole section
            guard !sectionDifference.deletions.contains(indexPath.section) else { return nil }
            
            // UITableView has a problem with drops that cause a row deletion in a moving section, so look for those conflicts and mark them; later, we'll note the problem in our returned Difference's applicability
            if sectionDifference.moves.contains(where: { $0.0 == indexPath.section }) {
                foundConflictingSectionAndItemChanges = true
            }
            
            // All other deletions are to be performed unchanged
            return indexPath
        }
        let survivingUpdates = itemDifference.updates.filter { indexPaths in
            // No need to update items if we're deleting their sections.
            return !sectionDifference.deletions.contains(indexPaths.0.section)
        }

        // Above, when creating `survivingMoves`, we're doing a quick pass to omit moves that contain deleted items/sections or items in newly added sections. Here we're digging a little deeper by looking at where each potential move lands. If a potential move destination can be achieved via the deletions and insertions above, then we can ignore the move.
        survivingMoves = survivingMoves.filter { indexPaths in
            let (source, destination) = indexPaths
            
            // To figure if the source IndexPath would land in the same place via deletions and insertions — for each change that would effect its location — we decrement the source section for each deletion and increment it for each insertion.
            var section = source.section
            section -= sectionDifference.deletions.filter({ $0 < section }).count
            section += sectionDifference.insertions.filter({ $0 <= section }).count
            
            // Here we do the same thing as we did for the sections for the rows.
            var item = source.item
            item -= survivingDeletions.filter({ $0.section == source.section && $0.item < item }).count
            item += survivingInsertions.filter({ $0.section == destination.section && $0.item <= item }).count
            
            // If this new IndexPath is the same as the potential move destination, there's no need to consider it. We'll just let the deletions and insertions handle it.
            if IndexPath(item: item, section: section) == destination {
                return false
            }
            
            return true
        }

        let survivingItemDifference = CollectionDifference<IndexPath>(insertions: Set(survivingInsertions), deletions: Set(survivingDeletions), updates: survivingUpdates, moves: survivingMoves)

        let applicability: Difference.ChangeKind
        if foundConflictingSectionAndItemChanges {
            applicability = .hasChangeButCannotApply
        } else {
            switch (sectionDifferenceFast, itemDifferenceFast) {
            case (.reload, _): fallthrough
            case (_, .reload): applicability = .hasChangeButCannotApply
            case let (.applyDifference(sectionDiff), .applyDifference(itemDiff)):
                applicability = (sectionDiff.isEmpty && itemDiff.isEmpty) ? .noChange : .hasChangeAndCanApply
            }
        }
        
        return Difference(sectionChanges: sectionDifference, itemChanges: survivingItemDifference, changeKind: applicability)
    }
}

// MARK: -

/// The type of items in a `Diffable` collection.
///
/// Items provide a `differenceIdentifier` that allows them to be tracked across `Diffable`s, even if their values have changed or they lack object identity (i.e., are enum or struct instances rather than class instances).
public protocol DifferenceComparable {
    associatedtype Identifier: Hashable
    /// A value used to construct differences using sets.
    ///
    /// Items that represent the same "thing" in a difference should have the same `differenceIdentifier`. That is, for two items `a` and `b`, `a.diff(from: b) == .unchanged || a.diff(from: b) == .needsUpdate` implies `a.differenceIdentifier == b.differenceIdentifier`. Furthermore `a.differenceIdentifier != b.differenceIdentifier` implies `a.diff(from: b) == .incomparable`.
    var differenceIdentifier: Identifier { get }
    
    /// Calculates the difference between this element and `preState`.
    func diff(from preState: Self) -> ElementDifference
}

// MARK: -

/// Records how to elements differ.
///
/// - seeAlso: DifferenceComparable.differenceIdentifier
public enum ElementDifference {
    /// The items are identical for diffing purposes.
    ///
    /// An item that's unchanged between two `Diffable`s may only appear in the `moves` of a `CollectionDifference`.
    case unchanged
    
    /// The items persist but have changed.
    ///
    /// An item that needsUpdate between two `Diffable`s may appear in the `moves` and the `updates` of a `CollectionDifference`.
    case needsUpdate
    
    /// The items are unrelated.
    case incomparable
}

// MARK: -

/// Records the differences between items at a single level in two `Diffable`s.
///
/// For sections, `Index == Int`. For items, `Index == IndexPath`.
public struct CollectionDifference<Index: DifferenceIndex> {
    public let insertions: Set<Index>
    public let deletions: Set<Index>
    
    /// Old index and new index of each item that needs to be updated.
    public let updates: [(Index, Index)]
    
    /// Old index and new index of each item that moved.
    public let moves: [(Index, Index)]
    
    public var isEmpty: Bool {
        return insertions.isEmpty && deletions.isEmpty && updates.isEmpty && moves.isEmpty
    }
}

fileprivate enum FastCollectionDifferenceWrapper<Index: DifferenceIndex> {
    case reload
    case applyDifference(CollectionDifference<Index>)
}

// MARK: -

/// Takes a table view cell to be updated, that cell's indexPath in the pre-state, and that cell's indexPath in the post-state.
public typealias DifferenceRowUpdater = (UITableViewCell, IndexPath, IndexPath) -> Void

/// Takes a table view header view to be updated, that view's section number in the pre-state, and that view's section number in the post-state.
/// - Parameters:
///   - header: A header view for updated section
///   - footer: A footer view for updated section
///   - preStateSection: The section index prior to update
///   - postStateSection: The section index after to update
public typealias DifferenceSectionUpdater = (_ header: UITableViewHeaderFooterView?, _ footer: UITableViewHeaderFooterView?, _ preStateSection: Int, _ postStateSection: Int) -> Void

private let updateCrossDissolveAnimationDuration: TimeInterval = 0.05

/// Encapsulates the difference between two `Diffable`s and can apply those differences to a table or collection view.
public struct Difference {
    public struct TableUpdateAnimations {
        public var sectionDeletion: UITableView.RowAnimation
        public var sectionInsertion: UITableView.RowAnimation
        public var sectionUpdate: UIView.AnimationOptions
        
        public var rowDeletion: UITableView.RowAnimation
        public var rowInsertion: UITableView.RowAnimation
        
        public var rowUpdate: UIView.AnimationOptions
        
        public init(sectionDeletion: UITableView.RowAnimation = .top, sectionInsertion: UITableView.RowAnimation = .top, sectionUpdate: UIView.AnimationOptions = [.transitionCrossDissolve], rowDeletion: UITableView.RowAnimation = .top, rowInsertion: UITableView.RowAnimation = .top, rowUpdate: UIView.AnimationOptions = [.transitionCrossDissolve]) {
            self.sectionDeletion = sectionDeletion
            self.sectionInsertion = sectionInsertion
            self.sectionUpdate = sectionUpdate
            self.rowDeletion = rowDeletion
            self.rowInsertion = rowInsertion
            self.rowUpdate = rowUpdate
        }
        
        public init(fade: Bool) {
            let animation: UITableView.RowAnimation = fade ? .fade : .none
            self.sectionDeletion = animation
            self.sectionInsertion = animation
            self.sectionUpdate = fade ? [.transitionCrossDissolve] : []
            self.rowDeletion = animation
            self.rowInsertion = animation
            self.rowUpdate = fade ? [.transitionCrossDissolve] : []
        }
    }
    
    public let sectionChanges: CollectionDifference<Int>
    public let itemChanges: CollectionDifference<IndexPath>
    
    /// Describes how the difference can be applied.
    ///
    /// - hasChangeAndCanApply: This Difference contains changes that it can apply for you.
    /// - hasChangeButCannotApply: This Difference contains changes but cannot apply them for you because it was not able to compute the minimal set of changes due to performance reasons. In this case you probably want to `reloadData()` yourself.
    /// - noChange: This Difference does not contain any changes.
    public enum ChangeKind {
        case hasChangeAndCanApply
        case hasChangeButCannotApply
        case noChange
    }
    public var changeKind: ChangeKind
    
    /// Animates the table view to transition between the pre- and post-states from which this `Difference` was constructed.
    ///
    /// - Parameters:
    ///   - tableView: the table view to animate
    ///   - animations: the animations to use, defaults to fades for updates and `top` for inserts and deletes
    ///   - sectionUpdater: a block invoked for each section header requiring an update; receives the current header and/or footer view, pre-state section index, and post-state section index. If `animations.sectionUpdate` is non-empty, then `sectionUpdater` is invoked inside a `UIView.transition(with: section[Header|Footer],…)` animation
    ///
    ///     Defaults to `nil`.
    ///
    ///   - rowUpdater: a block invoked for each visible cell requiring an update; receives the cell, pre-state indexPath, and post-state indexPath. If `animations.rowUpdate` is non-empty, then `rowUpdater` is invoked inside a `UIView.transition(with: cell,…)` animation
    ///
    ///     N.B., this *won't* necessarily be called for every element in `itemChanges.updates`, only for those where the cell is already visible.
    ///
    ///     Defaults to `nil`.
    ///
    ///   - otherUpdates: invoked in the same batch update as the updates defined by this `Difference`
    ///   - completion: invoked after the batch update animations complete
    public func updateTableView(_ tableView: UITableView, animations: TableUpdateAnimations = TableUpdateAnimations(), sectionUpdater: DifferenceSectionUpdater? = nil, rowUpdater: DifferenceRowUpdater? = nil, otherUpdates: (() -> Void)? = nil, completion: ((Bool) -> Void)? = nil) {
        if let updater = sectionUpdater {
            for (source, destination) in sectionChanges.updates {
                let sectionHeader = tableView.headerView(forSection: source)
                let sectionFooter = tableView.footerView(forSection: source)
                guard !(sectionHeader == nil && sectionFooter == nil) else { continue }
                if animations.sectionUpdate.isEmpty {
                    updater(sectionHeader, sectionFooter, source, destination)
                } else {
                    if let sectionHeader = sectionHeader {
                        UIView.transition(with: sectionHeader, duration: updateCrossDissolveAnimationDuration, options: animations.sectionUpdate, animations: {
                            updater(sectionHeader, nil, source, destination)
                        }, completion: nil)
                    }
                    
                    if let sectionFooter = sectionFooter {
                        UIView.transition(with: sectionFooter, duration: updateCrossDissolveAnimationDuration, options: animations.sectionUpdate, animations: {
                            updater(nil, sectionFooter, source, destination)
                        }, completion: nil)
                    }
                }
            }
        }
        
        if let updater = rowUpdater, let pathsForVisiblePreStateCells = tableView.indexPathsForVisibleRows {
            // We only update visible rows. Otherwise UITableView will ask us to configure a *new* cell in cellForRow(at:). We already have the new view model in place and will vend a post-state cell instead of pre-state. And that's if we're lucky. If the pre-state path doesn't exist in the post-state, we'll crash.
            let pathSet = Set(pathsForVisiblePreStateCells)
            for (sourcePath, destinationPath) in itemChanges.updates {
                guard pathSet.contains(sourcePath) else { continue }
                guard let cell = tableView.cellForRow(at: sourcePath) else { continue }
                if animations.rowUpdate.isEmpty {
                    updater(cell, sourcePath, destinationPath)
                } else {
                    UIView.transition(with: cell, duration: updateCrossDissolveAnimationDuration, options: animations.rowUpdate, animations: {
                        updater(cell, sourcePath, destinationPath)
                    }, completion: nil)
                }
            }
        }
        
        tableView.performBatchUpdates({
            tableView.deleteSections(IndexSet(from: sectionChanges.deletions), with: animations.sectionDeletion)
            tableView.insertSections(IndexSet(from: sectionChanges.insertions), with: animations.sectionInsertion)
            for (source, destination) in sectionChanges.moves {
                tableView.moveSection(source, toSection: destination)
            }
            
            tableView.deleteRows(at: Array(itemChanges.deletions), with: animations.rowDeletion)
            tableView.insertRows(at: Array(itemChanges.insertions), with: animations.rowInsertion)
            for (source, destination) in itemChanges.moves {
                tableView.moveRow(at: source, to: destination)
            }
            
            otherUpdates?()
        }, completion: completion)
    }
    
    public func updateCollectionView(_ collectionView: UICollectionView, otherUpdates: (() -> Void)? = nil, completion: ((Bool) -> Void)? = nil) {
        collectionView.performBatchUpdates({
            collectionView.deleteSections(IndexSet(from: sectionChanges.deletions))
            collectionView.insertSections(IndexSet(from: sectionChanges.insertions))
            for (source, destination) in sectionChanges.moves {
                collectionView.moveSection(source, toSection: destination)
            }
            
            collectionView.deleteItems(at: Array(itemChanges.deletions))
            collectionView.insertItems(at: Array(itemChanges.insertions))
            for (source, destination) in itemChanges.moves {
                collectionView.moveItem(at: source, to: destination)
            }
            
            otherUpdates?()
        }, completion: completion)
    }
}

// MARK: -

public protocol DifferenceIndex: Comparable, Hashable {
    associatedtype IndexBumper: Bumper where IndexBumper.Index == Self
    associatedtype MoveComparisonContext
    
    static func indexesReindexing(_ originals: [Self], metaMutator: MetaMutator?) -> [Self]
    static func indexBumper() -> IndexBumper
    
    static func moveComparisonContext<Value>(for simulationState: SimulatedTableView<Self, Value>) -> MoveComparisonContext
    /// Order must be “strict weak” as defined in the documentation of `Array.sorted(by:)`.
    static func movesAreOrderedByIncreasingImpact(_ left: (Self, Self), _ right: (Self, Self), context: MoveComparisonContext) -> Bool
    
    /// The engine will try to filter out moves that don't shift the position of a value in a flattened array of values. This isn't always OK; an item might move from the start of one section to the end of the preceding section, for example. Return `false` to require that such moves be included in results, or `true` to allow such moves to be filtered out of computed differences.
    static func moveIsFilterable(_ move: (Self, Self)) -> Bool
}

public protocol Bumper {
    associatedtype Index: DifferenceIndex
    func bump(_ index: Index) -> (Index, Self)
    func bumperAfterInsertingIndex(_ index: Index) -> Self
}

extension Int: DifferenceIndex {
    public static func indexesReindexing(_ originals: [Int], metaMutator: MetaMutator?) -> [Int] {
        guard !originals.isEmpty else { return [] }
        return Array(0 ..< originals.count)
    }

    public static func indexBumper() -> IntBumper {
        return IntBumper()
    }

    public static func moveComparisonContext<Value>(for simulationState: SimulatedTableView<Int, Value>) -> Int {
        return Int.max
    }

    public static func movesAreOrderedByIncreasingImpact(_ left: (Int, Int), _ right: (Int, Int), context: Int) -> Bool {
        // impact is distance moved
        let leftDistance: Int = abs(left.0 - left.1)
        let rightDistance: Int = abs(right.0 - right.1)
        return leftDistance < rightDistance
    }
    
    public static func moveIsFilterable(_ move: (Int, Int)) -> Bool {
        return true
    }
}

public struct IntBumper: Bumper {
    var bumpAmount = 0
    
    public func bump(_ index: Int) -> (Int, IntBumper) {
        return (index + bumpAmount, self)
    }

    public func bumperAfterInsertingIndex(_ index: Int) -> IntBumper {
        var result = self
        result.bumpAmount += 1
        return result
    }
}

extension IndexPath: DifferenceIndex {
    public static func indexesReindexing(_ originals: [IndexPath], metaMutator: MetaMutator?) -> [IndexPath] {
        guard let first = originals.first else { return [] }
        var currentIncomingSection = first.section // Used to detect section discontinuities, the points at which we need to re-adjust numbering.
        var nextRow = 0
        var sectionDelta = 0
        var result: [IndexPath] = []
        for index in originals {
            // <bug:///155292> (iOS-OmniFocus Engineering: Engineering Review of DifferenceEngine Change)
            if index.section != currentIncomingSection {
                // Make sure we re-number sections when entire section has been deleted. This handles the distinction between all items in a section being deleted and an entire section being deleted. From an items-only view we can't distinguish, so we need to get the sectionDifference involved via the metaMutator.
                var localSectionDelta = 0
                if let metaMutator = metaMutator, index.section > currentIncomingSection + 1 {
                    // Scan forward to the next section that wasn't deleted.
                    while metaMutator.isSectionDeleted(1 + currentIncomingSection + localSectionDelta) {
                        localSectionDelta += 1
                    }
                    sectionDelta += localSectionDelta
                }
                
                // We may have scanned to the end of the section list and found only deleted sections. If that's the case, be sure not to reset the nextRow; otherwise, we'll restart counting from row 0 in the (unchanged) currentIncomingSection, leading to possible index path duplication in the results.
                if (index.section - localSectionDelta > currentIncomingSection) {
                    nextRow = 0
                }
                currentIncomingSection = index.section
            }
            result.append(IndexPath(row: nextRow, section: currentIncomingSection - sectionDelta))
            nextRow += 1
        }
        return result
    }
    
    public static func indexBumper() -> IndexPathBumper {
        return IndexPathBumper()
    }
    
    /// result is map from section to number of rows in section
    public typealias SectionSizer = (Int) -> Int
    public static func moveComparisonContext<Value>(for simulationState: SimulatedTableView<IndexPath, Value>) -> SectionSizer {
        var maxRowInSection: [Int: Int] = [:]
        for item in simulationState.orderedItems {
            let indexPath = item.index
            if let extant = maxRowInSection[indexPath.section] {
                maxRowInSection[indexPath.section] = Swift.max(indexPath.row, extant)
            } else {
               maxRowInSection[indexPath.section] = indexPath.row
            }
        }
        return { (section: Int) -> Int in
            guard let maxRow = maxRowInSection[section] else {
                return 0
            }
            return maxRow + 1
        }
    }
    
    public static func movesAreOrderedByIncreasingImpact(_ left: (IndexPath, IndexPath), _ right: (IndexPath, IndexPath), context: @escaping SectionSizer) -> Bool {
        /// impact is the number of rows affected
        func impact(_ pair: (IndexPath, IndexPath)) -> Int {
            let (start, end) = pair
            if start.section == end.section {
                // distance moved
                return abs(start.row - end.row)
            } else {
                // number of subsequent rows in section
                let firstImpact = context(start.section) - start.row - 1
                let secondImpact = context(end.section) - end.row - 1
                return firstImpact + secondImpact
            }
        }
        
        return impact(left) < impact(right)
    }
    
    public static func moveIsFilterable(_ move: (IndexPath, IndexPath)) -> Bool {
        return move.0.section == move.1.section
    }
}

public struct IndexPathBumper: Bumper {
    var sectionToBump = 0
    var rowBumpAmount = 0
    
    public func bump(_ index: IndexPath) -> (IndexPath, IndexPathBumper) {
        precondition(index.section >= sectionToBump)
        
        if index.section == sectionToBump {
            let resultPath = IndexPath(row: index.row + rowBumpAmount, section: sectionToBump)
            return (resultPath, self)
        }
        
        assert(index.section > sectionToBump)
        var newBumper = self
        newBumper.sectionToBump = index.section
        newBumper.rowBumpAmount = 0
        return (index, newBumper)
    }

    public func bumperAfterInsertingIndex(_ index: IndexPath) -> IndexPathBumper {
        var newBumper = self
        if index.section == sectionToBump {
            newBumper.rowBumpAmount += 1
        } else {
            newBumper.sectionToBump = index.section
            newBumper.rowBumpAmount = 0
        }
        return newBumper
    }
}

public struct MetaMutator {
    fileprivate let sectionDifference: CollectionDifference<Int>
    
    fileprivate func isSectionDeleted(_ section: Int) -> Bool {
        return sectionDifference.deletions.contains(section)
    }
}

// MARK: -

/// A pair of a comparable value and its index.
private struct WrappedDifferenceComparable<Index: DifferenceIndex, Value: DifferenceComparable> {
    var index: Index
    let value: Value
    
    func diff(from preState: WrappedDifferenceComparable<Index, Value>) -> ElementDifference {
        return value.diff(from: preState.value)
    }
    
    static func difference(from old: [WrappedDifferenceComparable<Index, Value>], to new: [WrappedDifferenceComparable<Index, Value>], metaMutator: MetaMutator? = nil, suppressedMovePositions: (sources: Set<Index>, destinations: Set<Index>)? = nil) -> FastCollectionDifferenceWrapper<Index> {
        let newSet = Set(new)
        let oldSet = Set(old)
        
        let insertedSet = newSet.subtracting(oldSet)
        let deletedSet = oldSet.subtracting(newSet)
        
        var inserted = Set<Index>(insertedSet.map({ $0.index }))
        var deleted = Set<Index>(deletedSet.map({ $0.index }))
        
        if old.isEmpty { // avoid remaining work, only inserting in this case
            return .applyDifference(CollectionDifference(insertions: inserted, deletions: deleted, updates: [], moves: []))
        }

        // We need to filter out superfluous moves, which can provoke UITableView to throw. To do that, we simulate what table view will do. rdar://35009240
        var simulatedState = SimulatedTableView(preState: old, metaMutator: metaMutator)
        simulatedState.delete(deleted)
        simulatedState.insert(insertedSet)
        
        var updated: [(Index, Index)] = []
        var possibleMoves: [(WrappedDifferenceComparable<Index, Value>, WrappedDifferenceComparable<Index, Value>)] = []
        
        for oldWrapped in old {
            if !deletedSet.contains(oldWrapped) {
                guard let setIndex = newSet.index(of: oldWrapped) else { continue }
                let newWrapped = newSet[setIndex]
                switch newWrapped.diff(from: oldWrapped) {
                case .needsUpdate:
                    updated.append((oldWrapped.index, newWrapped.index))
                    fallthrough // updated items might also have moved
                case .unchanged:
                    if newWrapped.index != oldWrapped.index {
                        if let suppressed = suppressedMovePositions, suppressed.sources.contains(oldWrapped.index) || suppressed.destinations.contains(newWrapped.index) {
                            deleted.insert(oldWrapped.index)
                            simulatedState.delete([oldWrapped.index])
                            inserted.insert(newWrapped.index)
                            simulatedState.insert([newWrapped])
                        } else {
                            possibleMoves.append((oldWrapped, newWrapped))
                        }
                    }
                case .incomparable:
                    assertionFailure("implementation of `DifferenceComparable` protocol for `\(String(describing: oldWrapped))` violates a protocol invariant")
                }
            }
        }
        
        let result: FastCollectionDifferenceWrapper<Index>
        let PossibleMovesThreshold = 300
        if possibleMoves.count <= PossibleMovesThreshold {
            let moved = simulatedState.filteredMoves(possibleMoves)
            result = .applyDifference(CollectionDifference(insertions: inserted, deletions: deleted, updates: updated, moves: moved))
        } else {
            result = .reload
        }
        
        return result
    }
}

extension WrappedDifferenceComparable: Hashable {
    static func ==<Element>(lhs: WrappedDifferenceComparable<Index, Element>, rhs: WrappedDifferenceComparable<Index, Element>) -> Bool {
        return lhs.value.differenceIdentifier == rhs.value.differenceIdentifier
    }
    
    var hashValue: Int {
        return value.differenceIdentifier.hashValue
    }
}

public struct SimulatedTableView<Index: DifferenceIndex, Value: DifferenceComparable>: CustomStringConvertible {
    fileprivate private(set) var orderedItems: [WrappedDifferenceComparable<Index, Value>] {
        didSet {
            // clear caches
            _indexMap = nil
            _indexSet = nil
        }
    }
    
    private let metaMutator: MetaMutator?
    
    fileprivate init(preState: [WrappedDifferenceComparable<Index, Value>], metaMutator: MetaMutator?) {
        precondition(!preState.isEmpty)
        precondition(SimulatedTableView.isSortedWithUniqueIndexes(preState))
        self.orderedItems = preState
        self.metaMutator = metaMutator
    }
    
    public var description: String {
        return orderedItems.map({ "\($0)" }).joined(separator: "\n")
    }
    
    var hasHandledMetaDelete = false
    mutating func delete(_ preStateIndexes: Set<Index>) {
        guard !preStateIndexes.isEmpty else { return }
        let indexMap = self.indexMap()
        
        let arrayIndexesOfItemsToDelete = preStateIndexes.compactMap({ indexMap[$0] }).sorted().reversed()
        for arrayIndex in arrayIndexesOfItemsToDelete {
            orderedItems.remove(at: arrayIndex)
        }
        
        
        reindex(metaMutator: hasHandledMetaDelete ? nil : metaMutator)
        hasHandledMetaDelete = true
    }
    
    fileprivate mutating func insert(_ postStateItems: Set<WrappedDifferenceComparable<Index, Value>>) {
        guard !postStateItems.isEmpty else { return }

        // The incoming items have post-state indexes. Since we've already performed deletions, `orderedItems` have intermediate state indexes. Need to updated indexes of existing items to shove them to higher index values when there are insertion at smaller index values.
        // The most straightforward approach is: for each item to be inserted (1) try using indexMap to find location, (2) barring that, scan for insertion location, (3) insert item, (4) reindex(). This is O(n^2). If insertions are done in order, we can optimize to avoid repeated traversals, since steps (2) and (4) only apply to the remainder of the array. With that insight we can sort the postStateItems in O(n·lg(n)), then do the rest of the work on a single in-order pass.
        
        let itemsToInsert = postStateItems.sorted(by: { left, right in
            return left.index < right.index
        })
        
        // This is essentially a merge with some patching of indexes as we go.
        var newOrderedItems: [WrappedDifferenceComparable<Index, Value>] = []
        var oldArrayIndex = 0
        var insertionItemsArrayIndex = 0
        var indexBumper = Index.indexBumper()
        while oldArrayIndex < orderedItems.count && insertionItemsArrayIndex < itemsToInsert.count {
            let (bumpedIndex, newIndexBumper) = indexBumper.bump(orderedItems[oldArrayIndex].index)
            indexBumper = newIndexBumper
            if itemsToInsert[insertionItemsArrayIndex].index <= bumpedIndex {
                newOrderedItems.append(itemsToInsert[insertionItemsArrayIndex])
                indexBumper = indexBumper.bumperAfterInsertingIndex(itemsToInsert[insertionItemsArrayIndex].index)
                insertionItemsArrayIndex += 1
            } else {
                var oldItem = orderedItems[oldArrayIndex]
                oldItem.index = bumpedIndex
                newOrderedItems.append(oldItem)
                oldArrayIndex += 1
            }
        }
        // Close out the non-empty source array. Only one of these loops will actually iterate.
        assert(oldArrayIndex == orderedItems.count || insertionItemsArrayIndex == itemsToInsert.count)
        while oldArrayIndex < orderedItems.count {
            let (bumpedIndex, newIndexBumper) = indexBumper.bump(orderedItems[oldArrayIndex].index)
            indexBumper = newIndexBumper
            var oldItem = orderedItems[oldArrayIndex]
            oldItem.index = bumpedIndex
            newOrderedItems.append(oldItem)
            oldArrayIndex += 1
        }
        while insertionItemsArrayIndex < itemsToInsert.count {
            newOrderedItems.append(itemsToInsert[insertionItemsArrayIndex])
            insertionItemsArrayIndex += 1
        }

        orderedItems = newOrderedItems
    }
   
    /// Applies the move from the pre-state to the post-state, or does nothing if the item is already at the destination.
    ///
    /// - Parameters:
    ///   - source: the pre-state item location and value
    ///   - destination: the post-state item location and value
    /// - Returns: true if the move is necessary or false if it's superfluous
    fileprivate mutating func filteredMoves(_ possibleMoves: [(WrappedDifferenceComparable<Index, Value>, WrappedDifferenceComparable<Index, Value>)]) -> [(Index, Index)] {
        let context = Index.moveComparisonContext(for: self)
        let sortedPossibleMoves = possibleMoves.sorted { (leftPair, rightPair) -> Bool in
            let leftIndexes = (leftPair.0.index, leftPair.1.index)
            let rightIndexes = (rightPair.0.index, rightPair.1.index)
            let result = Index.movesAreOrderedByIncreasingImpact(leftIndexes, rightIndexes, context: context)
            return result
        }
        
        var result: [(Index, Index)] = []
        
        for possibleMove in sortedPossibleMoves.reversed() {
            let source = possibleMove.0
            let destination = possibleMove.1
            let indexMap = self.indexMap()
            if let destinationArrayIndex = indexMap[destination.index], orderedItems[destinationArrayIndex] == destination && Index.moveIsFilterable((source.index, destination.index)) {
                // superfluous, already at the destination
                continue
            }
            
            // Simulate the single item move so subsequent checks are accurate.
            // Sadly, this is O(n·m), where m is the number of moves that survive our filter above. In the worst case, random permutation of a list, m = n and we have an O(n^2) algorithm. Let's see if it flies in practice.
            guard let intermediateIndex = index(for: source) else {
                continue
            }
            delete([intermediateIndex])
            insert([destination])

            let move = (possibleMove.0.index, possibleMove.1.index)
            result.append(move)
        }

        return result
    }
    
    private static func isSortedWithUniqueIndexes(_ items: [WrappedDifferenceComparable<Index, Value>]) -> Bool {
        guard var currentIndex = items.first?.index else { return true }
        for item in items.dropFirst() {
            if item.index <= currentIndex {
                return false
            }
            currentIndex = item.index
        }
        return true
    }
    
    private static func buildIndexMap(from orderedItems: [WrappedDifferenceComparable<Index, Value>]) -> [Index: Int] {
        let result: [Index: Int] = Dictionary(orderedItems.enumerated().map({ ($0.1.index, $0.0) })) { (oldValue, newValue) -> Int in
            assertionFailure("Unexpected duplicate index key for array indices \(oldValue) and \(newValue)")
            return newValue
        }
        return result
    }
    
    private mutating func reindex(metaMutator: MetaMutator?) {
        let newIndexes = Index.indexesReindexing(orderedItems.map({ $0.index }), metaMutator: metaMutator)
        orderedItems = zip(orderedItems, newIndexes).map() { item, index in
            var changedItem = item
            changedItem.index = index
            return changedItem
        }
    }
    
    /// cached value, can clear but should *not* read directly, use `indexMap()`
    private var _indexMap: [Index: Int]? = nil
    private mutating func indexMap() -> [Index: Int] {
        if let extant = _indexMap {
            return extant
        }
        let result = SimulatedTableView.buildIndexMap(from: orderedItems)
        _indexMap = result
        return result
    }

    
    /// cached value, can clear but should *not* read directly, use `index(for:)`
    private var _indexSet: Set<WrappedDifferenceComparable<Index, Value>>? = nil
    private mutating func index(for wrappedValue: WrappedDifferenceComparable<Index, Value>) -> Index? {
        let set: Set<WrappedDifferenceComparable<Index, Value>>
        if let extant = _indexSet {
            set = extant
        } else {
            set = Set(orderedItems)
            _indexSet = set
        }
        
        guard let setIndex = set.index(of: wrappedValue) else { return nil }
        return set[setIndex].index
    }

}
