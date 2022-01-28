// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

@available(OSX 10.15, *)
public final class ComputedObservableValue<Output> : AnyObservableValue<Output> where Output: Equatable {
        
    private var cancellableSet: Set<AnyCancellable> = []
    private let set: ((Output)->Void)?
    private let get: ()->Output
    
    public init(get: @escaping ()->Output, set: ((Output)->Void)? = nil, dependentPublishers: [AnyPublisher<Void, Never>]) where Output: Equatable {
        self.set = set
        self.get = get
        
        super.init(initialValue: get())
        
        observe(dependentPublishers)
    }
    
    public func setNewDependentPublishers(_ publishers: [AnyPublisher<Void, Never>]) {
        cancellableSet.forEach({ $0.cancel() })
        observe(publishers)
        forceUpdate(to: get())
    }
    
    @discardableResult
    override public func update(_ newValue: Output) -> Bool {
        guard let set = set else { assertionFailure("Attempted to set value on read-only computed value"); return false }
        set(newValue)
        return super.update(get())
    }
    
    private func observe(_ publishers: [AnyPublisher<Void, Never>]) {
        publishers.forEach({
            $0.sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                self.forceUpdate(to: self.get())
            }).store(in: &cancellableSet)
        })
    }
    
    private func forceUpdate(to newValue: Output) {
        super.update(newValue)
    }
}
