// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Darwin.malloc

public protocol MemoryUseHistoryObserver : AnyObject {
    func memoryUseHistory(_ history: MemoryUseHistory, changedBaseline: MemoryUseHistory.Sample)
    func memoryUseHistory(_ history: MemoryUseHistory, addedSamples: [MemoryUseHistory.Sample])
}

public class MemoryUseHistory {

    public static let shared = MemoryUseHistory()
    
    public struct Sample {
        public let time: TimeInterval
        public let count: UInt
        public let size: UInt

        func hasSameValues(as other: Sample) -> Bool {
            return count == other.count && size == other.size
        }
    }

    public private(set) var baseline: Sample? {
        didSet {
            if let sample = baseline {
                observers.forEach { entry in
                    entry.observer?.memoryUseHistory(self, changedBaseline: sample)
                }
            }
        }
    }

    public private(set) var samples = [Sample]()
    
    private let sampleQueue: DispatchQueue
    private var timer: DispatchSourceTimer

    private struct Entry {
        weak var observer: MemoryUseHistoryObserver?
    }
    private var observers = [Entry]()


    private init() {
        // Don't bother logging in Debug builds, but provide some info that this is happening in non-debug in case we accidentally poke the shared instance.
        #if !DEBUG
            NSLog("Memory Use History tracking enabled")
        #endif

        sampleQueue = DispatchQueue(label: "com.omnigroup.framework.OmniBase.MemoryUseHistory")
        timer = DispatchSource.makeTimerSource(flags: [], queue: sampleQueue)
        
        timer.setEventHandler() {
            self._sample()
        }
        timer.schedule(deadline: DispatchTime.now(), repeating: 1.0)
        timer.resume()
    }

    public func setBaseline() {
        guard let sample = samples.last else {
            return
        }
        baseline = sample
    }

    public func add(observer: MemoryUseHistoryObserver) {
        let entry = Entry(observer: observer)
        observers.append(entry)
    }

    /// Records the current state in a new sample. Called automatically on a timer, but may also be called explicitly.
    public func sample() {
        sampleQueue.async {
            self._sample()
        }
    }

    // MARK:- Private
    
    private func _add(sample: Sample) {
        // This doesn't happen often, if at all, right now since we don't get created unless the UI to display this is up, and in that case we have malloc blocks appearing/disappearing on our timer.
        let count = samples.count
        if count >= 2 && samples[count - 1].hasSameValues(as: sample) && samples[count - 2].hasSameValues(as: sample) {
            // If we are sitting idle, just extend lines that have the same values
            samples[count - 1] = sample
            return
        }

        if samples.isEmpty {
            baseline = sample
        }
        
        samples.append(sample)

        observers.forEach { entry in
            entry.observer?.memoryUseHistory(self, addedSamples: [sample])
        }
    }

    private func _sample() {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        
        let sample = Sample(time: Date.timeIntervalSinceReferenceDate, count: UInt(stats.blocks_in_use), size: UInt(stats.size_allocated))

        DispatchQueue.main.async {
            self._add(sample: sample)
        }
    }
}
