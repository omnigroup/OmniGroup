// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation
import OmniBase
import OmniFoundation

@objc(ODAVUtilityBaseOperation)
public
class UtilityBaseOperation : OFAsynchronousOperation, OFErrorable
{
    internal let connection: ODAVConnection;
    internal let callbackQueue: OperationQueue;

    private  var error_: Error?;
    internal var cancellableOperation: ODAVOperation?;
    internal var cancellableTimer: DispatchSourceTimer?;

    public   var error: Error? { get { return error_; } };

    internal
    init(connection: ODAVConnection, cbq: OperationQueue) {
        assert(cbq.maxConcurrentOperationCount == 1); // Must be a serial queue; we use it to serialize access to ourself
        self.connection = connection;
        self.callbackQueue = cbq;
    }

    override
    public func handleCancellation() {
        callbackQueue.addOperation {
            if let timer = self.cancellableTimer {
                timer.cancel();  // self.cancellableTimer will be set to nil by the timer cancellation block.
            }
            if let op = self.cancellableOperation {
                op.cancel();  // self.cancellableOperation will be set to nil by the operation's didFinish block.
            }
        }
    }
    
    override
    public func finish()
    {
        // These should already be nil, but just in case.
        assert(self.cancellableOperation == nil);
        self.cancellableOperation = nil;
        assert(self.cancellableTimer == nil);
        self.cancellableTimer = nil;
        
        super.finish();
    }
    
    internal
    func fail(_ error: Error)
    {
        self.error_ = error;
        self.finish();
    }
    
    internal
    func succeed()
    {
        self.finish();
    }
    
    /// Begins a DAV operation which will be canceled if `self` is canceled.
    ///
    /// The operation's didFinish block *must* set self.cancellableOperation to nil as the first thing it does!
    internal
    func startCancellableOperation(_ op: ODAVOperation)
    {
        assert(self.cancellableOperation == nil);
        assert(OperationQueue.current == self.callbackQueue);
        
        self.cancellableOperation = op
        op.start(withCallbackQueue: self.callbackQueue);
    }

    public
    enum createParentsResult {
        case succeeded(finalLocation: URL)
        case exceededLevels
        case cancelled
        case mkcolFailed(error: Error, goingDown: Bool)
    };
    
    public final
    func tryCreateParents(levelsToCreate: UInt, location: URL, componentsStripped: [String] = [], goingBackUp: Bool = false, completion: @escaping (createParentsResult)->Void)
    {
        if levelsToCreate <= UInt(componentsStripped.count) {
            // The caller doesn't want us to do any (more) MKCOLs.
            completion(createParentsResult.exceededLevels);
            return;
        }
        
        let toCreate = location.lastPathComponent;
        if NSString.isEmpty(toCreate) {
            // Whoops. We hit the root. No can continue.
            completion(createParentsResult.exceededLevels);
            return
        }
        
        let mkcol = connection.asynchronousMakeCollection(at: location, completionHandler: { (result, mkcolError) in
            
            self.cancellableOperation = nil;
            
            func mkcolSucceeded(location: URL, componentsStripped: [String]) {
                var components = componentsStripped;
                if let childCollection = components.popLast() {
                    let reAdding = location.appendingPathComponent(childCollection, isDirectory: true)
                    self.tryCreateParents(levelsToCreate: levelsToCreate, location: reAdding, componentsStripped: components, goingBackUp: true, completion: completion)
                } else {
                    // Hey, we're done! Try that PROPFIND again.
                    completion(createParentsResult.succeeded(finalLocation: location));
                }
            }
            
            if let result = result {
                mkcolSucceeded(location: result.url, componentsStripped: componentsStripped)
            } else {
                let error = mkcolError!;
                
                // Check for an error that looks like someone got in ahead of us and created the collection we were trying to create.
                if error.isFromExistingCollection() {
                    // Yup, possibly racing against some other client. Act as if the MKCOL succeeded.
                    // If we're wrong and this wasn't from another MKCOL, we'll get a reasonable error later.
                    mkcolSucceeded(location: location, componentsStripped: componentsStripped)
                    return
                }
                
                if goingBackUp {
                    // Huh. We could create some but not all? (Maybe just a network error or something?)
                    completion(createParentsResult.mkcolFailed(error: error, goingDown: false));
                } else if error.isFromMissingCollection() {
                    // Strip off another component and try again.
                    var components = componentsStripped;
                    let parent = location.deletingLastPathComponent();
                    components.append(toCreate);
                    self.tryCreateParents(levelsToCreate: levelsToCreate, location: parent, componentsStripped: components, goingBackUp: false, completion: completion)
                } else {
                    completion(createParentsResult.mkcolFailed(error: error, goingDown: true));
                }
            }
        })!;
        
        self.startCancellableOperation(mkcol);
    }
    
    public
    enum moveIntoPlaceResult {
        case succeeded(finalLocation: URL)
        case cancelled
        case failed(error: Error)
    }

    /// Helper function for atomic stores.
    public final
    func moveIntoPlace(fromTemporary storedTo: URL, to destinationFileInfo: ODAVFileInfo, makeParents: UInt, completion: @escaping (moveIntoPlaceResult)->Void)
    {
        do {
            let finalLocation = destinationFileInfo.originalURL!;
            
            if destinationFileInfo.exists {
                try self.connection.synchronousMove(storedTo, to: finalLocation, withDestinationETag: destinationFileInfo.eTag, overwrite: true)
            } else {
                try self.connection.synchronousMove(storedTo, toMissing: finalLocation)
            }
            
            completion(.succeeded(finalLocation: finalLocation));
        } catch {
            // debugPrint("didn't storeAtomic-MOVE", error, "makeParents=", makeParents, "dfiExists=", destinationFileInfo.exists);
            
            if !destinationFileInfo.exists && makeParents > 0 && error.isFromMoveToMissingCollection() {
                // It looks like not only are we not overwriting a file, but our destination collection doesn't exist.
                // Our caller has asked us to try to create the collection in this situation.
                let directoryToCreate = destinationFileInfo.originalURL.deletingLastPathComponent();
                self.tryCreateParents(levelsToCreate: makeParents, location: directoryToCreate) {
                    switch $0 {
                    case .succeeded(finalLocation: let newDestDir):
                        // Retry the move. But set makeParents to 0, since we have already made the parent directory, we think.
                        let newDestination = newDestDir.appendingPathComponent(destinationFileInfo.originalURL.lastPathComponent);
                        let newDestinationFileInfo = ODAVFileInfo(originalURL: newDestination, name: nil, exists: false, directory: false, size: 0, lastModifiedDate: nil)!;
                        self.moveIntoPlace(fromTemporary: storedTo, to: newDestinationFileInfo, makeParents: 0, completion: completion)
                    case .cancelled:
                        completion(.cancelled)
                    case .exceededLevels:
                        completion(.failed(error: error))
                    case .mkcolFailed(error: let mkcolError, goingDown: _):
                        completion(.failed(error: mkcolError))
                    }
                }
            } else {
                // Nope, this looks like a real error of some kind.
                // (It may be a move conflict, but the caller can detect that as well as we can.)
                completion(.failed(error: error))
            }
            return;
        }
    }
    
    /// Sets a timer's callbacks and starts it.
    ///
    /// - Parameters:
    ///   - timer: A timer which has been scheduled, but not started.
    ///   - cancellation: Optional block to invoke if the timer/operation is cancelled.
    ///   - completion: Block to invoke when the time expires.
    ///
    /// The callbacks will be invoked on self.callbackQueue.
    /// If no cancellation callback is set, we assume that the timer is only cancelled by operation cancellation, so we just call self.finish().
    public final
    func startCancellableTimer(_ timer: DispatchSourceTimer, onCancel cancellation: ( ()->Void )? = nil, onTimeout completion: @escaping () -> Void)
    {
        precondition(self.cancellableTimer == nil);
        assert(OperationQueue.current == self.callbackQueue);
        
        timer.setEventHandler {
            // debugPrint("end wait (time expired)");
            self.cancellableTimer = nil;
            self.callbackQueue.addOperation(completion);
        };
        timer.setCancelHandler {
            // debugPrint("end wait (canceled)");
            self.cancellableTimer = nil;
            if let callback = cancellation {
                self.callbackQueue.addOperation(callback);
            } else {
                assert(self.isCancelled);
                self.finish();
            }
        };
        
        // debugPrint("beginning to wait");
        self.cancellableTimer = timer;
        timer.resume();
    }

    override
    public func debugDictionary() -> NSMutableDictionary! {
        let dict = super.debugDictionary()!;
        
        if let err = error_ {
            dict["error"] = err;
        }
        
        if let op = cancellableOperation {
            dict["cancellableOperation"] = op.debugDictionary();
        }
        
        if let tmr = cancellableTimer {
            dict["cancellableTimer"] = tmr;
        }
        
        return dict;
    }
}

/// Error predicates for specific situations.
internal
extension Error {
    
    /// Returns true if the error looks like something that'd occur if we tried to either PROPFIND a nonexistent collection or MKCOL inside a nonexistent collection.
    func isFromMissingCollection() -> Bool
    {
        return (self as NSError).hasUnderlyingErrorDomain(ODAVHTTPErrorDomain, code: Int(ODAV_HTTP_NOT_FOUND.rawValue))
    }
    
    /// Returns true if the error looks like something that'd occur if we tried to MOVE something to a missing collection.
    func isFromMoveToMissingCollection() -> Bool
    {
        let nserror = self as NSError;
        
        // According to RFC4918 [9.9.4], the correct response if we try to MOVE somewhere with a missing parent is 409 CONFLICT:
        //    "409 (Conflict) - A resource cannot be created at the destination until one or more intermediate collections have been created."
        // However, DAV server authors often get this one wrong.
        
        if let httpError_ = nserror.underlyingError(withDomain: ODAVHTTPErrorDomain) {
            let httpError = httpError_ as NSError
            let code = ODAVHTTPErrorCode(UInt32(httpError.code))
            
            if code == ODAV_HTTP_NOT_FOUND || code == ODAV_HTTP_GONE || code == ODAV_HTTP_CONFLICT {
                return true
            }
            
            // Some versions of Apache (up through version 2.4.25 at least) fail with 500 INTERNAL SERVER ERROR in this case. (Apache PR 39299)
            if (code == ODAV_HTTP_INTERNAL_SERVER_ERROR) {
                return true
            }
        }
        
        return false
    }
    
    /// Returns true if the error looks like we tried to MKCOL but somebody else got there first.
    func isFromExistingCollection() -> Bool
    {
        let error : NSError = self as NSError;
        if let davError = error.underlyingError(withDomain: ODAVHTTPErrorDomain) as NSError? {
            let code = ODAVHTTPErrorCode(UInt32(davError.code))
            if code == ODAV_HTTP_METHOD_NOT_ALLOWED || code == ODAV_HTTP_CONFLICT {
                return true;
            }
        }
        
        return false;
    }
    
    /// Returns true if the error looks like we tried the MOVE-into-place at the end of an atomic file write but somebody else got there first.
    func isFromAtomicWriteConflict() -> Bool
    {
        let error : NSError = self as NSError;
        if let davError = error.underlyingError(withDomain: ODAVHTTPErrorDomain) as NSError? {
            let code = ODAVHTTPErrorCode(UInt32(davError.code))
            if code == ODAV_HTTP_NOT_MODIFIED || code == ODAV_HTTP_CONFLICT || code == ODAV_HTTP_PRECONDITION_FAILED || code == ODAV_HTTP_LOCKED {
                return true;
            }
        }
        
        return false;
    }
    
    /// Returns true if it looks like something that would happen if we try to PUT something to a missing collection
    func isFromStoreIntoMissingCollection() -> Bool
    {
        let error : NSError = self as NSError;
        if let davError = error.underlyingError(withDomain: ODAVHTTPErrorDomain) as NSError? {
            let code = ODAVHTTPErrorCode(UInt32(davError.code))
            switch code {
            case ODAV_HTTP_NOT_FOUND, ODAV_HTTP_FORBIDDEN, ODAV_HTTP_METHOD_NOT_ALLOWED, ODAV_HTTP_CONFLICT:
                return true
            default:
                return false
            }
        }
        
        return false;
    }
}

