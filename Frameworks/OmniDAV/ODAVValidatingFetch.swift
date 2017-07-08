// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation
import OmniFoundation

@objc(ODAVValidatingFetchValidation) public
protocol ValidatingFetchValidation : NSObjectProtocol
{
    /// Returns whether the dependent ValidatingFetch operation has been canceled.
    /// Unfortunately not currently KVOable.
    var isCancelled : Bool { get };
    
    /// Cancels the ValidatingFetch; it is not necessary (or permitted) to also call acceptData/rejectData.
    func cancel();
    
    /// Indicates that the data supplied to the callback is acceptable and the fetch has succeeded.
    func acceptData();
    
    /// Indicates that the data supplied to the callback is unacceptable and the operation has failed.
    func rejectData(_: Error);
    
    /// Ask the operation to replace the data on the server with the specified data, then invoke the validation callback again with the new data (or with other data, if someone else modifies the file on the server).
    ///
    /// - Parameters:
    ///   - data: The updated data to store.
    ///   - makeParents: How many levels of parent collections to make for the destination.
    ///   - temporaryDirectory: A temporary directory into which to PUT the new data before MOVEing it to the destination.
    ///   - temporaryDirectoryParents: How many levels of parent collections to make for the temporary directory.
    @objc(substituteData:makeParents:temporaryDirectory:makeParents:)
    func substitute(data: Data, makeParents: UInt, temporaryDirectory: URL, makeParents temporaryDirectoryParents: UInt);
}

/// ODAVValidatingFetch retrieves a file and passes it to the supplied callback for consideration.
/// Unlike the straight-line code it replaces, it's cancellable.
///
/// The callback is given an object conforming to ODAVValidatingFetchValidation which it uses to
/// indicate whether it accepts this data. It can either call the methods on that object immediately,
/// or it can squirrel the object away and call the methods later (potentially on a different queue).
@objc(ODAVValidatingFetch) public
class ValidatingFetch : UtilityBaseOperation
{
    public typealias CallbackyThingyWhatsidoodle = (ValidatingFetchValidation, Data?, ODAVFileInfo) -> ();

    // Input properties
    private  let targetFileInfo : ODAVFileInfo;
    private  let startTime : CFAbsoluteTime;
    private  let validateRetrievedData : CallbackyThingyWhatsidoodle;
    
    // Working state
    private var tryCount : UInt = 0;
    private let maxTries : UInt = 3;
    
    /// Create a ODAVValidatingFetch operation.
    ///
    /// - Parameters:
    ///   - file: The file info of the file we expect to retrieve.
    ///   - connection: The DAV connection to use.
    ///   - callbackQueue: A serial queue used by this operation and also for invoking the callback.
    ///   - callback: A callback for acceptance of file contents. Invoked on callbackQueue.
    @objc public
    init(file: ODAVFileInfo, connection: ODAVConnection, callbackQueue: OperationQueue, callback: @escaping CallbackyThingyWhatsidoodle) {
        precondition(file != nil);
        self.targetFileInfo = file;
        self.validateRetrievedData = callback;
        self.startTime = CFAbsoluteTimeGetCurrent();
        super.init(connection: connection, cbq: callbackQueue);
    }

    override
    public func start()
    {
        super.start();
        if self.isCancelled {
            self.finish();
            return;
        }
        
        self.observeCancellation(true);
        
        self.callbackQueue.addOperation {
            let fileInfo = self.targetFileInfo;
            if fileInfo.exists {
                self.fetch();
            } else {
                self.checkForAcceptance(nil, fileInfo);
            }
        }
    }
    
    private
    func checkForAcceptance(_ data: Data?, _ fileInfo: ODAVFileInfo)
    {
        if self.isCancelled {
            self.finish();
            return;
        }
        
        // The validator will call back using our validation callback protocol, either immediately or later.
        // Since an immediate callback is possible, we need to be sure this is only called in situations where it's okay to call succeed/fail/storeAtomic again.
        // debugPrint("Calling validation cb with \( data?.count ?? -1 ) bytes")
        self.validateRetrievedData(Result(target: self, destination: fileInfo), data, fileInfo);
    }
    
    // ODAVValidatingFetchValidation implementation
    private
    class Result : NSObject, ValidatingFetchValidation
    {
        private let target : ValidatingFetch;
        private let fileInfo : ODAVFileInfo;
        #if DEBUG
        private var invoked : Bool = false;
        #endif
        
        fileprivate
        init(target t: ValidatingFetch, destination d: ODAVFileInfo) {
            target = t;
            fileInfo = d;
        }
        
        public
        var isCancelled : Bool {
            get {
                return target.isCancelled;
            }
        }
        
        public
        func cancel() {
            #if DEBUG
            assert(!invoked);
            invoked = true;
            #endif
            target.cancel();
        }
        
        public
        func acceptData() {
            #if DEBUG
            assert(!invoked);
            invoked = true;
            #endif
            target.succeed();
        }
        public
        func rejectData(_ delegateError: Error) {
            #if DEBUG
            assert(!invoked);
            invoked = true;
            #endif
            target.fail(delegateError);
        }
        public
        func substitute(data newData: Data, makeParents: UInt, temporaryDirectory: URL, makeParents makeTemporaryParents: UInt) {
            #if DEBUG
            assert(!invoked);
            invoked = true;
            #endif
            target.storeAtomic(newData, to: fileInfo, makeParents: makeParents, temporaryDirectory: temporaryDirectory, makeTemporaryParents: makeTemporaryParents);
        }
    }
    
    /// Fetch the file, and pass it to the delegate for appraisal.
    /// Fails the operation on failure, possibly using `recentError` as the "real" failure reason if this is an attempt to recover from a previous failure.
    private
    func fetch(recentError: Error? = nil)
    {
        tryCount += 1;
        
        // debugPrint("will fetch, try = \(tryCount)");

        let loc = targetFileInfo.originalURL;
        let op = connection.asynchronousGetContents(of: loc)!;
        op.didFinish = { (operation: ODAVAsynchronousOperation?, errorOrNil: Error?) -> () in
            self.cancellableOperation = nil
            if let fetchError = errorOrNil {
                // A missing file is passed to our delegate/callback as a nil data.
                // Other errors are either fatal or we retry a finite number of times.
                if let notFoundError = (fetchError as NSError).underlyingError(withDomain: ODAVHTTPErrorDomain, code: Int(ODAV_HTTP_NOT_FOUND.rawValue)) {
                    let failingURL = ((notFoundError as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? (operation?.url) ?? loc;
                    let missingFile = ODAVFileInfo(originalURL: failingURL, name: nil, exists: false, directory: false, size: 0, lastModifiedDate: nil)!;
                    // Allow the callback to either accept the missing-file state, or provide an alternative in the form of non-nil data.
                    self.checkForAcceptance(nil, missingFile);
                } else if let previousError = recentError {
                    // We couldn't store it, and we couldn't re-read it either; probably can't recover. Return the storage failure to the caller though, since it's arguably the more relevant error.
                    self.fail(previousError);
                } else if (self.tryCount < self.maxTries) {
                    self.waitThenFetch(forSeconds: 0.25, backoff: true)
                } else {
                    self.fail(fetchError);
                }
                return;
            } else {
                let opf = operation!;
                let responseData = opf.resultData!;  // Failure to get any data should have been reported to us as a non-nil errorOrNil
                
                let opc = opf as! ODAVOperation; // It doesn't seem to be possible to cast to "ODAVOperation <ODAVAsynchronousOperation>" in Swift, sigh
                let responseETag = opc.value(forResponseHeader: "ETag");
                let responseMTime : Date?;
                
                if let mtime = opc.value(forResponseHeader: "Last-Modified-Date") {
                    responseMTime = ODAVConnection.date(from: mtime)
                } else {
                    responseMTime = nil
                }
                
                let responseFileInfo = ODAVFileInfo(originalURL: loc, name: nil, exists: true, directory: false, size: off_t(responseData.count), lastModifiedDate: responseMTime, eTag: responseETag)!;
                
                self.checkForAcceptance(responseData, responseFileInfo);
                return;
            }
        }
        self.startCancellableOperation(op);
    }
    
    /// Tries to store an updated file, then re-reads it from the server to make sure we have the same thing the server does (this should not really be necessary, but it lets us update our etag value, and helps protect against servers that might not implement conditional moves completely correctly).
    ///
    /// - Parameters:
    ///   - encryptedKeyTable: The data to store.
    ///   - to: The location to store to. The "exists" and "ETag" properties are consulted to produce a conditional store.
    ///   - makeParents: The number of levels of parent directory of the destination to try to make (defaults to 0).
    ///   - temporaryDirectory: The temporary directory to use for the atomic PUT-then-MOVE sequence. (The file will be randomly named in that directory.)
    ///   - makeTemporaryParents: The number of levels of parent directory of the temporary directory to try to make (defaults to 0).
    private
    func storeAtomic(_ encryptedKeyTable: Data, to dfi: ODAVFileInfo, makeParents: UInt = 0, temporaryDirectory remoteTemporaryDirectory: URL, makeTemporaryParents: UInt = 0)
    {
        assert(OperationQueue.current == self.callbackQueue);
        
        // debugPrint("will storeAtomic", dfi, makeParents, makeTemporaryParents);
        
        let temporaryLocation = remoteTemporaryDirectory.appendingPathComponent(OFXMLCreateID(), isDirectory: false);
        let storeOp = connection.asynchronousPut(encryptedKeyTable, to: temporaryLocation)!;
        storeOp.didFinish = { (operation: ODAVAsynchronousOperation?, errorOrNil: Error?) -> () in
            self.cancellableOperation = nil

            // debugPrint("did storeAtomic-PUT");
            
            if let writeTempError = errorOrNil {
                
                // Try creating the temporary directory.
                if makeTemporaryParents > 0 && writeTempError.isFromStoreIntoMissingCollection() {
                    self.tryCreateParents(levelsToCreate: makeTemporaryParents, location: remoteTemporaryDirectory) {
                        switch $0 {
                        case .cancelled:
                            self.finish();
                        case .succeeded(finalLocation: let newTempDir):
                            self.storeAtomic(encryptedKeyTable, to: dfi, makeParents: makeParents, temporaryDirectory: newTempDir, makeTemporaryParents: 0);
                        case .mkcolFailed(error: let mkcolError, goingDown: _):
                            self.fail(mkcolError);
                        default:
                            self.fail(writeTempError);
                        }
                    }
                } else {
                    // We couldn't even store the temporary file. This isn't a conflict with another client; this is some other problem which we should just report to our caller.
                    self.fail(writeTempError);
                }
                
            } else {
                let opf = operation!;
                let storedTo = opf.resultLocation() ?? opf.url ?? temporaryLocation;
                
                if self.isCancelled {
                    self.cleanup(temporaryFile: storedTo);
                    self.finish();
                    return;
                }
                
                // debugPrint("will storeAtomic-MOVE", storedTo, dfi.originalURL, makeParents);
                
                // We succeeded in writing the temporary file. Now try to move it into its final location.
                self.moveIntoPlace(fromTemporary: storedTo, to: dfi, makeParents: makeParents) {
                    switch $0 {
                    case .cancelled:
                        self.cleanup(temporaryFile: storedTo);
                        self.finish();
                    case .succeeded:
                        // We successfully stored an updated key table.
                        // Re-fetch the file to be absolutely sure we're using the same thing the server has.
                        // debugPrint("did storeAtomic-MOVE");
                        self.fetch();
                    case .failed(error: let moveError):
                        // debugPrint("didn't storeAtomic-MOVE", moveError);
                        self.cleanup(temporaryFile: storedTo);
                        if moveError.isFromAtomicWriteConflict() {
                            // If it's an error that could plausibly be because someone else updated it out from under us, clear our cache, sleep briefly, and start over from the top to pick up the change which some other client just wrote.
                            self.waitThenFetch(forSeconds: 0.25, backoff: true, recentError: moveError)
                        } else {
                            // Nope, this looks like a real error of some kind.
                            self.fail(moveError);
                        }
                    }
                }
            }
        };
        self.startCancellableOperation(storeOp);
    }
    
    private
    func cleanup(temporaryFile: URL)
    {
        // The move failed; try cleaning up the temporary file.
        let cleanup = self.connection.asynchronousDelete(temporaryFile, withETag: nil)!;
        cleanup.didFinish = { _,_ -> () in
            // Don't actually need to do anything here; this is a fire-and-forget cleanup operation.
            return;
        };
        cleanup.start(withCallbackQueue: self.callbackQueue);
    }
    
    private
    func waitThenFetch(forSeconds seconds: CFTimeInterval, backoff: Bool, recentError: Error? = nil)
    {

        let timer = DispatchSource.makeTimerSource();

        if backoff {
            // Random exponential backoff.
            var soFar : CFTimeInterval = CFAbsoluteTimeGetCurrent() - self.startTime;
            if soFar > 20 {
                soFar = 20;
            }
            
            // Additional wait of anywhere from 0.5 to 1.0 times our original start time.
            let backoffDelay = ( Double(1024 + (OFRandomNext32() % 1024)) / 2048.0 ) * soFar;
            let seconds = (seconds > backoffDelay) ? seconds : backoffDelay;
            
            // Tell the system that it has tons of leeway in scheduling this retry (up to 1/2 of soFar).
            timer.scheduleOneshot(deadline: DispatchTime.now() + seconds,
                                  leeway: DispatchTimeInterval.milliseconds(Int(500.0 * soFar)));
        } else {
            timer.scheduleOneshot(deadline: DispatchTime.now() + seconds);
        }
        
        self.startCancellableTimer(timer) {
            if self.isCancelled {
                self.finish();
                return;
            }
            
            self.fetch(recentError: recentError);
        }
    }
    
    override
    public func debugDictionary() -> NSMutableDictionary! {
        let dict = super.debugDictionary()!;
        
        dict.setUnsignedIntegerValue(tryCount, forKey: "tryCount");
        dict["targetFileInfo"] = targetFileInfo;
        
        return dict;
    }
}

